//
//  AudioSegment.swift
//  TwinMindRecorder
//
//  Created by Jerry Zhang on 2025-07-02.
//

import Foundation
import SwiftData

/// Represents a 30-second audio segment within a recording session
@Model
final class AudioSegment {
    /// Unique identifier for the segment
    var id: UUID
    
    /// File path where the audio data is stored (relative to Documents directory)
    var audioFilePath: String
    
    /// Start time within the recording session (in seconds from session start)
    var startTime: TimeInterval
    
    /// Duration of this segment in seconds (typically 30 seconds)
    var duration: TimeInterval
    
    /// Audio quality metadata
    var sampleRate: Double = 44100.0
    var bitDepth: Int = 16
    var channelCount: Int = 1
    
    /// File size in bytes for storage management
    var fileSizeBytes: Int64 = 0
    
    /// When this segment was created
    var createdAt: Date
    
    /// The recording session this segment belongs to
    var session: RecordingSession?
    
    /// The transcription for this segment (optional - may not exist yet)
    @Relationship(deleteRule: .cascade)
    var transcription: Transcription?
    
    init(audioFilePath: String, startTime: TimeInterval, duration: TimeInterval) {
        self.id = UUID()
        self.audioFilePath = audioFilePath
        self.startTime = startTime
        self.duration = duration
        self.createdAt = Date()
    }
}

// MARK: - File Management
extension AudioSegment {
    /// Get the full file URL for the audio data
    var audioFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory,
                                                   in: .userDomainMask).first!
        return documentsPath.appendingPathComponent(audioFilePath)
    }
    
    /// Check if the audio file exists on disk
    var audioFileExists: Bool {
        FileManager.default.fileExists(atPath: audioFileURL.path)
    }
    
    /// Get human-readable file size
    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }
    
    /// Delete the audio file from disk
    func deleteAudioFile() throws {
        if audioFileExists {
            try FileManager.default.removeItem(at: audioFileURL)
        }
    }
}
