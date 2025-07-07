//
//  RecordingViewModel.swift
//  TwinMindRecorder
//
//  Created by Jerry Zhang on 2025-07-02.
//

import Foundation
import AVFoundation
import SwiftData
import AVFAudio
import UIKit

/// Handles all audio recording functionality using AVAudioEngine
@MainActor
class RecordingViewModel: ObservableObject {
    // MARK: - Published Properties (for UI updates)
    @Published var isRecording = false
    @Published var currentSession: RecordingSession?
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    @Published var hasPermission = false
    
    @Published var hasLowStorage = false
    private var selectedQuality: AudioQuality = .medium

    @Published var audioEngineWasHealthy = true

    
    // MARK: - Audio Engine Components
    private var audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingTimer: Timer?
    private var segmentTimer: Timer?
    
    // MARK: - Recording Configuration
    @Published var segmentDuration: TimeInterval = 30.0
    
    private var currentSegmentStartTime: TimeInterval = 0
    private var segments: [AudioSegment] = []
    
    
    // MARK: - Model Context (for saving to database)
    private var modelContext: ModelContext?
    
    // Add Transcription Service
    private let transcriptionService = AudioTranscriptionService()

    
    init() {
        setupAudioSession()
        setupAudioSessionObservers()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /// Configure the audio session for recording
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            try audioSession.setCategory(.playAndRecord,
                                         mode: .default,
                                         options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            // Request mic permission
            audioSession.requestRecordPermission { [weak self] allowed in
                DispatchQueue.main.async {
                    self?.hasPermission = allowed
                    if !allowed {
                        print("Microphone permission denied")
                    }
                }
            }
            
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
    }
}

// MARK: - Recording Controls
extension RecordingViewModel {
    func hasSufficientStorage(minimumBytes: Int64 = 100 * 1024 * 1024) -> Bool {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

        do {
            let values = try documentsPath.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            let available = values.volumeAvailableCapacityForImportantUsage ?? 0
            let availableMB = Double(available) / (1024 * 1024)
            print("📦 Available space: \(availableMB.rounded()) MB")
            
            return available > minimumBytes
            
        } catch {
            print("❌ Failed to check available storage: \(error)")
            return true // Assume yes, to not block recording
        }
    }

    
    /// Start a new recording session
    func startRecording(title: String? = nil, modelContext: ModelContext, quality: AudioQuality = .medium) {
        guard !isRecording else { return }
        
        guard hasSufficientStorage() else {
            hasLowStorage = true
            print("⚠️ Not enough storage to start recording")
            return
        }
        hasLowStorage = false


        self.selectedQuality = quality

        self.modelContext = modelContext
        
        do {
            // Create new recording session
            let session = RecordingSession(title: title)
            self.currentSession = session
            modelContext.insert(session)
            
            // Setup audio engine for recording
            try setupAudioEngine()
            
            audioEngine.prepare()
            
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
        audioFile = nil
        
        Thread.sleep(forTimeInterval: 0.2)

        
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
        let inputFormat = audioEngine.inputNode.inputFormat(forBus: 0)
        let settings = inputFormat.settings


        //print("🎛 Mic format: \(recordingFormat.sampleRate) Hz, \(recordingFormat.channelCount) channels")

        
        // Create audio file URL for current segment
        let segmentURL = createSegmentFileURL()
        
        // Create audio file for writing
        audioFile = try AVAudioFile(forWriting: segmentURL, settings: settings)

        let tapFormat = inputNode.inputFormat(forBus: 0)

        // Install tap for real-time audio processing
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, time in
            try? self?.audioFile?.write(from: buffer)
            self?.updateAudioLevel(from: buffer)
        }

    }
    
    /// Create unique file URL for audio segment
    private func createSegmentFileURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileName = "segment_\(UUID().uuidString).wav"
        let url = documentsPath.appendingPathComponent(fileName)

        // Encrypt at rest with iOS file protection
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        try? FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)

        return url
    }

    
    /// Update audio level for real-time visualization
    private func updateAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }  // Add this check
        
        var sum: Float = 0.0
        
        for i in 0..<frameLength {
            sum += channelData[i] * channelData[i]
        }
        
        let rms = sqrt(sum / Float(frameLength))
        
        // Fix NaN values
        let safeRMS = rms.isNaN || rms.isInfinite ? 0.0 : rms
        
        DispatchQueue.main.async {
            self.audioLevel = safeRMS
        }
    }
}

// MARK: - Timer Management
extension RecordingViewModel {
    /// Start recording and segment timers
    private func startTimers() {
        // Timer for updating recording duration (every 0.1 seconds)
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.recordingDuration += 0.1
        }
        
        // Timer for creating new segments
        segmentTimer = Timer.scheduledTimer(withTimeInterval: segmentDuration, repeats: true) { [weak self] _ in
            self?.createNewSegment()
        }
        
        
        print("🕒 Segment timer started with duration: \(segmentDuration) seconds")

        
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
        guard isRecording && audioEngine.isRunning else {
            print("⏸ Skipping segment — recording is paused or engine not running")
            return
        }
        guard isRecording, audioEngine.isRunning, audioEngineWasHealthy else {
            print("⏸ Skipping segment — engine state unhealthy")
            return
        }


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
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]

            // Create new audio file
            audioFile = try AVAudioFile(forWriting: segmentURL,
                                        settings: [
                                            AVFormatIDKey: kAudioFormatLinearPCM,
                                            AVSampleRateKey: selectedQuality.sampleRate,
                                            AVLinearPCMBitDepthKey: selectedQuality.bitDepth,
                                            AVNumberOfChannelsKey: 1,
                                            AVLinearPCMIsFloatKey: false,
                                            AVLinearPCMIsBigEndianKey: false
                                        ]
)
            print("🔥 Successfully created new audio file: \(segmentURL.lastPathComponent)")
            
        } catch {
            print("🔥 FAILED to create new audio file: \(error)")
        }
    }
    
    /// Finalize the current audio segment and save to database
    private func finalizeCurrentSegment() {
        guard let file = audioFile, file.length > 0 else {
            print("⛔️ Skipping segment finalization — no audio written")
            return
        }

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
        
        // After modelContext.insert(transcription)
        let asset = AVAsset(url: segment.audioFileURL)
        print("🧾 Segment asset duration: \(CMTimeGetSeconds(asset.duration))s")

        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: segment.audioFileURL.path)
            print("📄 Segment file size: \(attrs[.size] ?? 0) bytes")
        } catch {
            print("❌ Failed to get file attributes: \(error)")
        }

        
        transcriptionService.queueForTranscription(segment, modelContext: modelContext)

        print("Created segment: \(fileName)")
        
        Task {
            let m4aURL = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(fileName.replacingOccurrences(of: ".wav", with: ".m4a"))

            do {
                try await AudioConversionService.convertToM4A(inputURL: segment.audioFileURL, outputURL: m4aURL)
                print("🎵 M4A exported: \(m4aURL.lastPathComponent)")
            } catch {
                print("❌ M4A conversion failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Simple Interruption Handling
extension RecordingViewModel {
    
    /// Setup basic audio interruption observer
    private func setupAudioSessionObservers() {
        print("🔧 Setting up audio interruption observer")

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        

    }
    
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        print("🎧 Audio route changed — reason: \(reason)")

        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable, .categoryChange:
            
            if isRecording {
                print("🔄 Rebuilding audio engine due to route change")

                // Stop engine and tap
                audioEngine.stop()
                audioEngine.reset()
                audioEngine.inputNode.removeTap(onBus: 0)
                
                do {
                    try setupAudioEngine()
                    audioEngine.prepare()
                    try audioEngine.start()
                    print("✅ Audio engine restarted after route change")
                } catch {
                    print("❌ Failed to restart audio engine: \(error)")
                }
            }

        default:
            break
        }
    }


    
    @objc private func handleAudioInterruption(_ notification: Notification) {
        print("🔧 INTERRUPTION NOTIFICATION RECEIVED!")  // Add this line
        
        guard let userInfo = notification.userInfo,
              let interruptionType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt else {
            print("🔧 No userInfo or interruption type")  // Add this line
            return
        }
        
        print("🔧 Interruption type: \(interruptionType)")  // Add this line

        switch AVAudioSession.InterruptionType(rawValue: interruptionType) {
        case .began:
            handleInterruptionBegan()
            
        case .ended:
            let options = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = (options & AVAudioSession.InterruptionOptions.shouldResume.rawValue) != 0
            handleInterruptionEnded(shouldResume: shouldResume)
            
        default:
            break
        }
    }
    
    private func handleInterruptionBegan() {
        segmentTimer?.invalidate()
        segmentTimer = nil
        print("⏸ Segment timer paused due to interruption")

        print("🎵 Audio interruption began (call, Siri, etc.)")
        
        if isRecording {
            // Simple approach: just pause the engine
            audioEngine.pause()
            print("🎵 Recording paused")
        }
    }
    
    private func handleInterruptionEnded(shouldResume: Bool) {
        print("🎵 Audio interruption ended - shouldResume: \(shouldResume)")
        
        if isRecording && shouldResume {
            do {
                audioEngine.inputNode.removeTap(onBus: 0)
                try setupAudioEngine()
                audioEngine.prepare()
                try audioEngine.start()
                print("🎵 Recording resumed with new audio tap")
            } catch {
                print("🎵 Failed to resume audio engine: \(error)")
            }
        }
        if shouldResume {
            startTimers()
            print("▶️ Segment timer resumed")
        }

    }
    @objc private func handleAppWillResignActive() {
        print("📱 App moving to background")
        if isRecording {
            try? AVAudioSession.sharedInstance().setActive(true)
            print("✅ AVAudioSession kept active in background")
        }
    }

    @objc private func handleAppDidBecomeActive() {
        print("📱 App back to foreground")
    }

}
