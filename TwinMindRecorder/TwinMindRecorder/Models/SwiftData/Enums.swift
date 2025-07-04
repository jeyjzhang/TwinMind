//
//  Enums.swift
//  TwinMindRecorder
//
//  Created by Jerry Zhang on 2025-07-02.
//

import Foundation


// Recording state for sessions
enum RecordingState: String, Codable, CaseIterable {
    case stopped = "stopped"
    case recording = "recording"
    case paused = "paused"
    case completed = "completed"
    case error = "error"
}

// Transcription processing status
enum TranscriptionStatus: String, Codable, CaseIterable {
    case pending = "pending"           // Waiting to be processed
    case processing = "processing"     // Currently being transcribed
    case completed = "completed"       // Successfully transcribed
    case failed = "failed"            // Transcription failed
    case queued = "queued"            // Queued for processing (offline)
}

// Available transcription services
enum TranscriptionService: String, Codable, CaseIterable {
    case openAIWhisper = "openai_whisper"
    case appleSpeech = "apple_speech"
    case localWhisper = "local_whisper"
    
    var displayName: String {
        switch self {
        case .openAIWhisper:
            return "OpenAI Whisper"
        case .appleSpeech:
            return "Apple Speech Recognition"
        case .localWhisper:
            return "Local Whisper"
        }
    }
}

// Audio quality settings
enum AudioQuality: String, CaseIterable {
    case low = "low"           // 22kHz, 16-bit
    case medium = "medium"     // 44kHz, 16-bit
    case high = "high"         // 48kHz, 24-bit
    
    var sampleRate: Double {
        switch self {
        case .low: return 22050.0
        case .medium: return 44100.0
        case .high: return 48000.0
        }
    }
    
    var bitDepth: Int {
        switch self {
        case .low, .medium: return 16
        case .high: return 24
        }
    }
}
