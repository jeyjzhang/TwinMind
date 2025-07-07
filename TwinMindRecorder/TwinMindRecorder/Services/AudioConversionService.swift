import AVFoundation
import Speech

struct AudioConversionService {
    
    // MARK: - Async Conversion Method
    static func convertToM4A(inputURL: URL, outputURL: URL) async throws {
        print("🔄 Starting conversion: \(inputURL.lastPathComponent) -> \(outputURL.lastPathComponent)")
        
        // First, let's inspect what we're working with
        let asset = AVAsset(url: inputURL)
        
        // Debug: Print asset information
        await printAssetInfo(asset)
        
        // Check if conversion is actually needed
        guard await needsConversion(asset) else {
            print("ℹ️ File is already in compatible format, copying instead of converting")
            try FileManager.default.copyItem(at: inputURL, to: outputURL)
            return
        }
        
        // Create export session with proper error handling
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ConversionError.cantCreateExportSession
        }
        
        // Configure export session
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Additional configuration for audio-only content
        exportSession.audioTimePitchAlgorithm = .spectral
        
        // Use async/await instead of semaphore
        await exportSession.export()
        
        // Check export status
        switch exportSession.status {
        case .completed:
            print("✅ Conversion completed successfully")
            
        case .failed:
            let errorMessage = exportSession.error?.localizedDescription ?? "Unknown export error"
            print("❌ Export failed: \(errorMessage)")
            throw ConversionError.exportFailed(errorMessage)
            
        case .cancelled:
            throw ConversionError.exportCancelled
            
        default:
            throw ConversionError.unexpectedStatus(exportSession.status)
        }
        
        // Verify output file exists
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw ConversionError.outputFileNotFound
        }
        
        print("✅ M4A file created: \(outputURL.lastPathComponent)")
    }
    
    // MARK: - Alternative: Direct Speech Recognition on WAV
    static func transcribeDirectly(wavURL: URL) async throws -> String {
        print("🎙️ Attempting direct transcription of WAV file")
        
        // Check Speech Recognition authorization
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status) // Send result back to await
            }
        }        
        guard await authStatus == .authorized else {
            throw ConversionError.speechNotAuthorized
        }
        
        // Create recognizer
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw ConversionError.recognizerUnavailable
        }
        
        // Debug: Check file format compatibility
        await printAssetInfo(AVAsset(url: wavURL))
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: wavURL)
            request.shouldReportPartialResults = false
            
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    print("❌ Direct transcription failed: \(error.localizedDescription)")
                    continuation.resume(throwing: ConversionError.transcriptionFailed(error.localizedDescription))
                } else if let result = result, result.isFinal {
                    print("✅ Direct transcription succeeded")
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private static func needsConversion(_ asset: AVAsset) async -> Bool {
        // Check if the audio tracks are in a format that Speech Recognition can handle
        let tracks = try? await asset.loadTracks(withMediaType: .audio)
        
        guard let audioTrack = tracks?.first else {
            print("⚠️ No audio tracks found")
            return true // Try conversion as fallback
        }
        
        // For now, always try direct transcription first
        return true
    }
    
    private static func printAssetInfo(_ asset: AVAsset) async {
        do {
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            
            print("📊 Asset Info:")
            print("   Duration: \(CMTimeGetSeconds(duration)) seconds")
            print("   Audio tracks: \(tracks.count)")
            
            for (index, track) in tracks.enumerated() {
                let formatDescriptions = try await track.load(.formatDescriptions)
                print("   Track \(index): \(formatDescriptions.count) format descriptions")
                
                // Print format details
                for desc in formatDescriptions {
                    if let audioDesc = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                        print("     Format: \(audioDesc.pointee.mSampleRate) Hz, \(audioDesc.pointee.mChannelsPerFrame) channels")
                    }
                }
            }
        } catch {
            print("⚠️ Could not load asset info: \(error)")
        }
    }
}

// MARK: - Custom Error Types
enum ConversionError: LocalizedError {
    case cantCreateExportSession
    case exportFailed(String)
    case exportCancelled
    case unexpectedStatus(AVAssetExportSession.Status)
    case outputFileNotFound
    case speechNotAuthorized
    case recognizerUnavailable
    case transcriptionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .cantCreateExportSession:
            return "Could not create export session"
        case .exportFailed(let message):
            return "Export failed: \(message)"
        case .exportCancelled:
            return "Export was cancelled"
        case .unexpectedStatus(let status):
            return "Unexpected export status: \(status)"
        case .outputFileNotFound:
            return "Converted file was not created"
        case .speechNotAuthorized:
            return "Speech recognition not authorized"
        case .recognizerUnavailable:
            return "Speech recognizer unavailable"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        }
    }
}
