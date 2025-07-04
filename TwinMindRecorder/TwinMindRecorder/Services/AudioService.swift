//
//  AudioService.swift
//  TwinMindRecorder
//
//  Created by Jerry Zhang on 2025-07-02.
//

import Foundation
import AVFoundation
import SwiftData
import AVFAudio

/// Handles all audio recording functionality using AVAudioEngine
@MainActor
class AudioService: ObservableObject {
    // MARK: - Published Properties (for UI updates)
    @Published var isRecording = false
    @Published var currentSession: RecordingSession?
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    @Published var hasPermission = false

    
    // MARK: - Audio Engine Components
    private var audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingTimer: Timer?
    private var segmentTimer: Timer?
    
    // MARK: - Recording Configuration
    private let segmentDuration: TimeInterval = 30.0 // 30-second segments
    private var currentSegmentStartTime: TimeInterval = 0
    private var segments: [AudioSegment] = []
    
    // MARK: - Model Context (for saving to database)
    private var modelContext: ModelContext?
    
    // Add Transcription Service
    private let transcriptionService = AudioTranscriptionService()

    
    init() {
        setupAudioSession()
    }
    
    /// Configure the audio session for recording
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Set category for recording with playback capability
            try audioSession.setCategory(.playAndRecord,
                                         mode: .default,
                                         options: [.defaultToSpeaker, .allowBluetooth])
            
            // Request microphone permission (old way - works fine)
            audioSession.requestRecordPermission { [weak self] allowed in
                DispatchQueue.main.async {
                    self?.hasPermission = allowed
                    if !allowed {
                        print("Microphone permission denied")
                    }
                }
            }
            
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
}

// MARK: - Recording Controls
extension AudioService {
    /// Start a new recording session
    func startRecording(title: String? = nil, modelContext: ModelContext) {
        guard !isRecording else { return }
        
        self.modelContext = modelContext
        
        do {
            // Create new recording session
            let session = RecordingSession(title: title)
            self.currentSession = session
            modelContext.insert(session)
            
            // Setup audio engine for recording
            try setupAudioEngine()
            
            // Start the audio engine
            try audioEngine.start()
            
            // Update state
            isRecording = true
            recordingDuration = 0
            currentSegmentStartTime = 0
            
            // Start timers
            startTimers()
            
            print("Recording started successfully")
            
        } catch {
            print("Failed to start recording: \(error)")
            isRecording = false
        }
    }
    
    /// Stop the current recording session
    func stopRecording() {
        guard isRecording else { return }
        
        // Stop audio engine
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        // Stop timers
        stopTimers()
        
        // Finalize current segment
        finalizeCurrentSegment()
        
        // Complete the session
        currentSession?.completeSession()
        
        // Save context
        try? modelContext?.save()
        
        // Reset state
        isRecording = false
        currentSession = nil
        recordingDuration = 0
        audioLevel = 0.0
        
        print("Recording stopped successfully")
    }
    /// Setup AVAudioEngine for recording with real-time processing
    private func setupAudioEngine() throws {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Create audio file URL for current segment
        let segmentURL = createSegmentFileURL()
        
        // Create audio file for writing
        audioFile = try AVAudioFile(forWriting: segmentURL,
                                   settings: recordingFormat.settings)
        
        // Install tap for real-time audio processing
        inputNode.installTap(onBus: 0,
                           bufferSize: 1024,
                           format: recordingFormat) { [weak self] buffer, time in
            
            // Write audio to file
            try? self?.audioFile?.write(from: buffer)
            
            // Calculate audio level for UI visualization
            self?.updateAudioLevel(from: buffer)
        }
    }
    
    /// Create unique file URL for audio segment
    private func createSegmentFileURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory,
                                                   in: .userDomainMask).first!
        let fileName = "segment_\(UUID().uuidString).wav"
        return documentsPath.appendingPathComponent(fileName)
    }
    
    /// Update audio level for real-time visualization
    private func updateAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0.0
        
        // Calculate RMS (Root Mean Square) for audio level
        for i in 0..<frameLength {
            sum += channelData[i] * channelData[i]
        }
        
        let rms = sqrt(sum / Float(frameLength))
        
        // Update on main thread for UI
        DispatchQueue.main.async {
            self.audioLevel = rms
        }
    }
}

// MARK: - Timer Management (ADD THIS - NEW EXTENSION)
extension AudioService {
    /// Start recording and segment timers
    private func startTimers() {
        // Timer for updating recording duration (every 0.1 seconds)
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.recordingDuration += 0.1
        }
        
        // Timer for creating new segments (every 30 seconds)
        segmentTimer = Timer.scheduledTimer(withTimeInterval: segmentDuration, repeats: true) { [weak self] _ in
            self?.createNewSegment()
        }
    }
    
    /// Stop all timers
    private func stopTimers() {
        recordingTimer?.invalidate()
        segmentTimer?.invalidate()
        recordingTimer = nil
        segmentTimer = nil
    }
    
    // In createNewSegment method, add logging:
    private func createNewSegment() {
        print("🔥 createNewSegment called at \(recordingDuration)s")
        
        // Finalize current segment
        print("🔥 About to finalize current segment")
        finalizeCurrentSegment()
        print("🔥 Finished finalizing current segment")
        
        // Start new segment
        currentSegmentStartTime = recordingDuration
        print("🔥 About to setup new audio engine")
        
        // Setup new audio file for next segment
        do {
            let segmentURL = createSegmentFileURL()
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            // Create new audio file
            audioFile = try AVAudioFile(forWriting: segmentURL,
                                       settings: recordingFormat.settings)
            print("🔥 Successfully created new audio file: \(segmentURL.lastPathComponent)")
            
        } catch {
            print("🔥 FAILED to create new audio file: \(error)")
        }
    }
    
    /// Finalize the current audio segment and save to database
    private func finalizeCurrentSegment() {
        guard let audioFile = audioFile,
              let session = currentSession,
              let modelContext = modelContext else { return }
        
        // Get file path relative to Documents directory
        let fileName = audioFile.url.lastPathComponent
        
        // Create audio segment
        let segment = AudioSegment(
            audioFilePath: fileName,
            startTime: currentSegmentStartTime,
            duration: min(segmentDuration, recordingDuration - currentSegmentStartTime)
        )
        
        // Set up relationships
        segment.session = session
        session.segments.append(segment)
        
        // Create pending transcription
        let transcription = Transcription()
        segment.transcription = transcription
        
        // Save to database
        modelContext.insert(segment)
        modelContext.insert(transcription)
        
        transcriptionService.queueForTranscription(segment, modelContext: modelContext)

        print("Created segment: \(fileName)")
        
        
    }
}
