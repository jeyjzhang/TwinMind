//
//  Transcription.swift
//  TwinMindRecorder
//
//  Created by Jerry Zhang on 2025-07-02.
//

import Foundation
import SwiftData

/// Represents the transcription result for an audio segment
@Model
final class Transcription {
    /// Unique identifier for the transcription
    var id: UUID
    
    /// The transcribed text
    var text: String
    
    /// Confidence level of the transcription (0.0 to 1.0)
    var confidence: Double
    
    /// Current processing status
    var status: TranscriptionStatus
    
    /// Which service was used for transcription
    var transcriptionService: TranscriptionService
    
    /// When the transcription was created
    var createdAt: Date
    
    /// When the transcription was last updated
    var updatedAt: Date
    
    /// Number of retry attempts made
    var retryCount: Int = 0
    
    /// Error message if transcription failed
    var errorMessage: String?
    
    /// Processing time in seconds
    var processingTime: TimeInterval?
    
    /// The audio segment this transcription belongs to
    var audioSegment: AudioSegment?
    
    init(text: String = "",
         confidence: Double = 0.0,
         status: TranscriptionStatus = .pending,
         service: TranscriptionService = .openAIWhisper) {
        self.id = UUID()
        self.text = text
        self.confidence = confidence
        self.status = status
        self.transcriptionService = service
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Status Management
extension Transcription {
    /// Mark transcription as completed
    func markCompleted(text: String, confidence: Double, processingTime: TimeInterval) {
        self.text = text
        self.confidence = confidence
        self.status = .completed
        self.processingTime = processingTime
        self.updatedAt = Date()
        self.errorMessage = nil
    }
    
    /// Mark transcription as failed
    func markFailed(error: String) {
        self.status = .failed
        self.errorMessage = error
        self.updatedAt = Date()
        self.retryCount += 1
    }
    
    /// Mark transcription as processing
    func markProcessing() {
        self.status = .processing
        self.updatedAt = Date()
    }
}

// MARK: - Retry Logic
extension Transcription {
    /// Check if transcription can be retried
    var canRetry: Bool {
        status == .failed && retryCount < 5
    }
}
