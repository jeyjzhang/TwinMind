//
//  RecordingSessoin.swift
//  TwinMindRecorder
//
//  Created by Jerry Zhang on 2025-07-02.
//

import Foundation
import SwiftData
import UIKit

// Represents a complete recording session that can contain multiple audio segments
@Model
final class RecordingSession {
    /// Unique identifier for the session
    var id: UUID
    
    /// When the recording session started
    var startTime: Date
    
    /// When the recording session ended (nil if still recording)
    var endTime: Date?
    
    /// User-provided title for the session (optional)
    var title: String?
    
    /// All audio segments that belong to this session
    @Relationship(deleteRule: .cascade, inverse: \AudioSegment.session)
    var segments: [AudioSegment] = []
    
    /// Current recording state
    var recordingState: RecordingState

    
    /// Session metadata for debugging/analytics
    var deviceModel: String?
    var appVersion: String?
    
    init(title: String? = nil) {
        self.id = UUID()
        self.startTime = Date()
        self.title = title
        self.recordingState = RecordingState.stopped  // Set in init instead
        self.deviceModel = UIDevice.current.model
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}

// MARK: - Session Properties
extension RecordingSession {
    /// Total duration of the session in seconds
    var totalDuration: TimeInterval {
        guard let endTime = endTime else {
            // If still recording, calculate duration from start time to now
            return Date().timeIntervalSince(startTime)
        }
        return endTime.timeIntervalSince(startTime)
    }
    
    /// Check if the session is currently recording
    var isRecording: Bool {
        recordingState == .recording
    }
    
    /// Get transcription progress (0.0 to 1.0)
    var transcriptionProgress: Double {
        guard !segments.isEmpty else { return 0.0 }
        let completedCount = completedTranscriptions.count
        return Double(completedCount) / Double(segments.count)
    }
}

// MARK: - Transcription Helpers
extension RecordingSession {
    /// Get all segments with completed transcriptions
    var completedTranscriptions: [AudioSegment] {
        segments.filter { $0.transcription?.status == .completed }
    }
    
    /// Get the full transcription text for the session
    var fullTranscriptionText: String {
        completedTranscriptions
            .sorted { $0.startTime < $1.startTime }
            .compactMap { $0.transcription?.text }
            .joined(separator: " ")
    }
}

// MARK: - Session Actions
extension RecordingSession {
    /// Mark session as completed
    func completeSession() {
        self.endTime = Date()
        self.recordingState = .completed
    }
}

