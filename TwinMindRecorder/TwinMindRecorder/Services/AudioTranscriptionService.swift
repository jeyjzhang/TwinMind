import Foundation
import SwiftData
import UIKit
import Speech
import Network

// MARK: - API Models
struct WhisperRequest {
    let audioData: Data
    let fileName: String
    let model: String = "whisper-1"
    let language: String? = nil
}

struct WhisperResponse: Codable {
    let text: String
}

struct TranscriptionError: Error, LocalizedError {
    let message: String
    let isRetryable: Bool
    
    var errorDescription: String? { message }
    
    static let networkError = TranscriptionError(message: "Network connection failed", isRetryable: true)
    static let rateLimitError = TranscriptionError(message: "Rate limit exceeded", isRetryable: true)
    static let authError = TranscriptionError(message: "Authentication failed", isRetryable: false)
    static let fileSizeError = TranscriptionError(message: "File too large", isRetryable: false)
    static let serverError = TranscriptionError(message: "Server error", isRetryable: true)
}

/// Handles audio transcription using OpenAI Whisper API with retry logic and local fallback
@MainActor
class AudioTranscriptionService: ObservableObject {
    
    // MARK: - Configuration
    private var apiKey: String {
        (try? KeychainManager.loadAPIKey()) ?? ""
    }
    private let baseURL = "https://api.openai.com/v1/audio/transcriptions"
    private let maxRetryCount = 5
    private let maxFileSize = 25 * 1024 * 1024 // 25MB
    
    // MARK: - Processing Queue
    @Published var isProcessing = false
    @Published var queueCount = 0
    private var processingQueue: [AudioSegment] = []
    private let monitor = NWPathMonitor()
    
    // MARK: - Dependencies
    private var modelContext: ModelContext?
    
    @Published var isOnline: Bool = true

    
    
    init(){
        if let loadedKey = try? KeychainManager.loadAPIKey() {
            print("🔐 Loaded API key from Keychain: \(loadedKey.prefix(6))...")
        } else {
            print("🔐 Failed to load API key from Keychain")
        }
    }

    
    // MARK: - Public Interface
    
    /// Add an audio segment to the transcription queue
    func queueForTranscription(_ segment: AudioSegment, modelContext: ModelContext) {
        print("📩 Queued segment: \(segment.audioFileURL.lastPathComponent)")
        self.modelContext = modelContext
        
        // Create transcription record if it doesn't exist
        if segment.transcription == nil {
            let transcription = Transcription(status: .queued, service: .openAIWhisper)
            segment.transcription = transcription
            modelContext.insert(transcription)
        }
        
        // Add to processing queue
        processingQueue.append(segment)
        queueCount = processingQueue.count
        
        // Start processing if not already running
        if !isProcessing {
            Task {
                await processQueue()
            }
        }
    }
    
    func startNetworkMonitor(sessions: [RecordingSession]) {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let nowOnline = path.status == .satisfied
                self?.isOnline = nowOnline
                print("📡 Network status: \(nowOnline ? "Online" : "Offline")")

                if nowOnline {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        print("📶 Debounced network reconnect, attempting retry...")
                        self?.retryPendingSegments(from: sessions)
                    }
                }
            }
        }

        let queue = DispatchQueue(label: "NetworkMonitor")
        monitor.start(queue: queue)
    }
    
    @MainActor
    func retryOfflineSegments(from sessions: [RecordingSession]) async {
        let ids = await OfflineQueueManager.shared.all()
        
        for id in ids {
            for session in sessions {
                if let segment = session.segments.first(where: { $0.audioFilePath == id }) {
                    print("🌐 Requeuing offline segment: \(id)")
                    queueForTranscription(segment, modelContext: modelContext!)
                    await OfflineQueueManager.shared.remove(id)
                }
            }
        }
    }


    /// Process all queued transcriptions
    private func processQueue() async {
        isProcessing = true
        
        while !processingQueue.isEmpty {
            let segment = processingQueue.removeFirst()
            queueCount = processingQueue.count
            
            await transcribeSegment(segment)
            
            // Small delay between requests to avoid rate limiting
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        isProcessing = false
    }
    
    // MARK: - Core Transcription Logic
    
    /// Transcribe a single audio segment with retry logic
    private func transcribeSegment(_ segment: AudioSegment) async {
        print("🎙️ Transcribing segment: \(segment.audioFileURL.lastPathComponent)")
        guard let transcription = segment.transcription else {
            print("❌ No transcription record found for segment")
            return
        }
        
        // Update status to processing
        transcription.markProcessing()
        
        do {
            // Load audio file data using the segment's audioFileURL property
            guard let audioData = try? Data(contentsOf: segment.audioFileURL) else {
                throw TranscriptionError(message: "Could not load audio file", isRetryable: false)
            }
            
            // Validate file size
            guard audioData.count <= maxFileSize else {
                throw TranscriptionError.fileSizeError
            }
            
            // Attempt transcription with retry logic
            let transcriptionText = try await transcribeWithRetry(
                audioData: audioData,
                fileName: segment.audioFileURL.lastPathComponent
            )
            
            // Success - update transcription record
            transcription.markCompleted(text: transcriptionText, confidence: 1.0, processingTime: 0)
            transcription.retryCount = 0
            
            print("✅ Transcribed segment: \(segment.audioFileURL.lastPathComponent)")
            
        } catch {
            // Handle failure
            transcription.retryCount += 1
            
            if transcription.retryCount >= maxRetryCount {
                print("🔄 Switching to local transcription after \(transcription.retryCount) failures")
                await handleLocalFallback(segment: segment, transcription: transcription)
            } else {
                transcription.markFailed(error: error.localizedDescription)
                print("❌ Transcription failed for \(segment.audioFileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        // Save changes to SwiftData
        saveContext()
    }
    
    /// Retry logic with exponential backoff
    private func transcribeWithRetry(audioData: Data, fileName: String) async throws -> String {
        let request = WhisperRequest(audioData: audioData, fileName: fileName)
        
        for attempt in 0..<maxRetryCount {
            do {
                return try await performAPITranscription(request)
            } catch let error as TranscriptionError {
                // Don't retry non-retryable errors
                if !error.isRetryable {
                    throw error
                }
                
                // Don't retry on last attempt
                if attempt == maxRetryCount - 1 {
                    throw error
                }
                
                // Exponential backoff: 1s, 2s, 4s, 8s, 16s
                let delay = pow(2.0, Double(attempt))
                print("🔄 Attempt \(attempt + 1) failed: \(error.message). Retrying in \(delay)s")
                
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        throw TranscriptionError.serverError
    }
    
    /// Perform the actual API call to OpenAI Whisper
    private func performAPITranscription(_ request: WhisperRequest) async throws -> String {
        // Create multipart form data
        let boundary = "Boundary-\(UUID().uuidString)"
        let httpBody = createMultipartBody(request: request, boundary: boundary)
        
        print("📡 Sending request to OpenAI Whisper for \(request.fileName)")

        // Build URL request
        guard let url = URL(string: baseURL) else {
            throw TranscriptionError(message: "Invalid URL", isRetryable: false)
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = httpBody
        urlRequest.timeoutInterval = 30.0
        
        // Perform request with background task support
        let (data, response) = try await performBackgroundRequest(urlRequest)
        
        // Handle response
        do {
            let (data, response) = try await performBackgroundRequest(urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranscriptionError.networkError
            }

            return try handleAPIResponse(data: data, statusCode: httpResponse.statusCode)

        } catch let error as URLError where error.code == .notConnectedToInternet {
            print("🚫 No internet. Queuing segment for later retry")
            await OfflineQueueManager.shared.add(request.fileName)
            throw TranscriptionError.networkError
        }

    }
    
    /// Perform network request with background task support
    private func performBackgroundRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        // Start background task to continue if app backgrounds
        let backgroundTask = await UIApplication.shared.beginBackgroundTask {
            print("⚠️ Background task expired during transcription")
        }
        
        defer {
            if backgroundTask != .invalid {
                Task { @MainActor in
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                }
            }
        }
        
        return try await URLSession.shared.data(for: request)
    }
    
    /// Handle API response and extract transcription text
    private func handleAPIResponse(data: Data, statusCode: Int) throws -> String {
        switch statusCode {
        case 200...299:
            // Success - parse response
            let response = try JSONDecoder().decode(WhisperResponse.self, from: data)
            return response.text
            
        case 400:
            throw TranscriptionError(message: "Bad request - invalid audio file", isRetryable: false)
            
        case 401:
            let serverMessage = try? String(data: data, encoding: .utf8) ?? "No details"
            throw TranscriptionError(message: "Authentication failed: \(serverMessage)", isRetryable: false)

            
        case 413:
            throw TranscriptionError.fileSizeError
            
        case 429:
            throw TranscriptionError.rateLimitError
            
        case 500...599:
            throw TranscriptionError.serverError
            
        default:
            throw TranscriptionError(message: "HTTP \(statusCode)", isRetryable: true)
        }
    }
    
    /// Create multipart form data for file upload
    private func createMultipartBody(request: WhisperRequest, boundary: String) -> Data {
        var body = Data()
        
        // Add file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(request.fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!) // Fixed: wav not m4a
        body.append(request.audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append(request.model.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add language if specified
        if let language = request.language {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append(language.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
    
    // MARK: - Local Fallback Implementation
    
    /// Handle local transcription fallback
    private func handleLocalFallback(segment: AudioSegment, transcription: Transcription) async {
        print("🔄 Starting local fallback for: \(segment.audioFileURL.lastPathComponent)")
        
        do {
            // Strategy 1: Try direct transcription of WAV file first
            print("📝 Strategy 1: Direct WAV transcription")
            let directText = try await AudioConversionService.transcribeDirectly(wavURL: segment.audioFileURL)
            
            // Success with direct transcription
            transcription.markCompleted(text: directText, confidence: 0.9, processingTime: 0)
            transcription.transcriptionService = .appleSpeech
            print("✅ Direct WAV transcription succeeded!")
            return
            
        } catch {
            print("⚠️ Direct transcription failed: \(error.localizedDescription)")
            print("📝 Strategy 2: Convert to M4A then transcribe")
            
            // Strategy 2: Convert to M4A and then transcribe
            do {
                let convertedURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("converted_\(UUID().uuidString).m4a")
                
                // Use the improved async conversion
                try await AudioConversionService.convertToM4A(inputURL: segment.audioFileURL, outputURL: convertedURL)
                
                // Try transcription on converted file
                let convertedText = try await transcribeConvertedFile(fileURL: convertedURL)
                
                transcription.markCompleted(text: convertedText, confidence: 0.8, processingTime: 0)
                transcription.transcriptionService = .appleSpeech
                print("✅ M4A conversion + transcription succeeded!")
                
                // Clean up temporary file
                try? FileManager.default.removeItem(at: convertedURL)
                
            } catch {
                print("❌ Both local strategies failed: \(error.localizedDescription)")
                transcription.markFailed(error: "All transcription methods failed: \(error.localizedDescription)")
            }
        }
    }

    /// Transcribe a converted M4A file
    private func transcribeConvertedFile(fileURL: URL) async throws -> String {
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status) // Send result back to await
            }
        }
        guard await authStatus == .authorized else {
            throw TranscriptionError(message: "Speech recognition not authorized", isRetryable: false)
        }
        
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw TranscriptionError(message: "Speech recognizer unavailable", isRetryable: false)
        }
        
        print("🎙️ Transcribing converted M4A file: \(fileURL.lastPathComponent)")
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: fileURL)
            request.shouldReportPartialResults = false
            
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: TranscriptionError(message: "M4A transcription failed: \(error.localizedDescription)", isRetryable: false))
                } else if let result = result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
    
    /// Perform local transcription using iOS Speech Recognition
    private func transcribeLocally(fileURL: URL) async throws -> String {
        let authStatus = await SFSpeechRecognizer.authorizationStatus()
        if authStatus != .authorized {
            print("🛑 Speech recognition not authorized: \(authStatus.rawValue)")
            throw TranscriptionError(message: "Speech recognition not authorized", isRetryable: false)
        }

        // Print format details
        print("🧾 Final file format:")
        let asset = AVAsset(url: fileURL)
        print("⏱️ Segment duration: \(CMTimeGetSeconds(asset.duration)) seconds")
        for track in asset.tracks {
            print("🎛 Track: \(track.mediaType), \(track.naturalTimeScale) Hz, \(track.formatDescriptions)")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

            guard let recognizer = recognizer, recognizer.isAvailable else {
                return continuation.resume(throwing: TranscriptionError(message: "Local recognizer unavailable", isRetryable: false))
            }

            let request = SFSpeechURLRecognitionRequest(url: fileURL)

            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: TranscriptionError(message: "Local transcription failed: \(error.localizedDescription)", isRetryable: false))
                } else if let result = result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    
    /// Save changes to SwiftData context
    private func saveContext() {
        guard let modelContext = modelContext else { return }
        
        do {
            try modelContext.save()
        } catch {
            print("❌ Failed to save transcription context: \(error)")
        }
    }
    
    @MainActor
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    
    @MainActor
    func retryPendingSegments(from sessions: [RecordingSession]) {
        print("💥 retryPendingSegments called with \(sessions.count) sessions")

        guard let context = modelContext else {
            print("❌ retryPendingSegments aborted — modelContext is nil")
            return
        }
        
        for session in sessions {
            for segment in session.segments {
                guard let transcription = segment.transcription else { continue }

                if transcription.status == .queued || (transcription.status == .failed && transcription.canRetry) {
                    print("🔁 Auto-retrying segment: \(segment.audioFilePath)")
                    guard let context = modelContext else {
                        print("❌ Cannot retry segment, modelContext is nil")
                        continue
                    }
                    queueForTranscription(segment, modelContext: context)
                }
            }
        }
    }

    
}
