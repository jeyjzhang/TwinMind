import Foundation
import SwiftData
import UIKit

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
    private let apiKey = ""
    private let baseURL = "https://api.openai.com/v1/audio/transcriptions"
    private let maxRetries = 5
    private let maxFileSize = 25 * 1024 * 1024 // 25MB
    private let maxConsecutiveFailures = 5
    
    // MARK: - Processing Queue
    @Published var isProcessing = false
    @Published var queueCount = 0
    private var processingQueue: [AudioSegment] = []
    private var consecutiveFailures = 0
    
    // MARK: - Dependencies
    private var modelContext: ModelContext?
    
    // MARK: - Public Interface
    
    /// Add an audio segment to the transcription queue
    func queueForTranscription(_ segment: AudioSegment, modelContext: ModelContext) {
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
                audioData: audioData,
                fileName: segment.audioFileURL.lastPathComponent
            )
            
            // Success - update transcription record
            transcription.markCompleted(text: transcriptionText, confidence: 1.0, processingTime: 0)
            consecutiveFailures = 0
            
            print("✅ Transcribed segment: \(segment.audioFileURL.lastPathComponent)")
            
        } catch {
            // Handle failure
            consecutiveFailures += 1
            
            if consecutiveFailures >= maxConsecutiveFailures {
                print("🔄 Switching to local transcription after \(consecutiveFailures) failures")
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
        
        for attempt in 0..<maxRetries {
            do {
                return try await performAPITranscription(request)
            } catch let error as TranscriptionError {
                // Don't retry non-retryable errors
                if !error.isRetryable {
                    throw error
                }
                
                // Don't retry on last attempt
                if attempt == maxRetries - 1 {
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
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.networkError
        }
        
        return try handleAPIResponse(data: data, statusCode: httpResponse.statusCode)
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
            throw TranscriptionError.authError
            
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
        do {
            // Load audio file for local processing
            guard let audioData = try? Data(contentsOf: segment.audioFileURL) else {
                throw TranscriptionError(message: "Could not load audio file for local processing", isRetryable: false)
            }
            
            // Attempt local transcription
            let localText = try await transcribeLocally(audioData: audioData)
            
            // Update transcription record
            transcription.markCompleted(text: localText, confidence: 0.8, processingTime: 0)
            transcription.transcriptionService = .appleSpeech // Fixed: using correct enum
            
            print("✅ Local transcription completed for \(segment.audioFileURL.lastPathComponent)")
            
        } catch {
            transcription.markFailed(error: "Both API and local transcription failed: \(error.localizedDescription)")
            print("❌ Local transcription also failed for \(segment.audioFileURL.lastPathComponent): \(error.localizedDescription)")
        }
    }
    
    /// Perform local transcription using iOS Speech Recognition
    private func transcribeLocally(audioData: Data) async throws -> String {
        // TODO: Implement iOS Speech Recognition
        // For now, return placeholder
        return "[Local transcription - Implementation needed]"
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
    
    // MARK: - Public Utility Methods
    
    /// Reset consecutive failure count (call when network conditions improve)
    func resetFailureCount() {
        consecutiveFailures = 0
    }
    
    /// Check if service is in local fallback mode
    var isInLocalFallbackMode: Bool {
        return consecutiveFailures >= maxConsecutiveFailures
    }
}
