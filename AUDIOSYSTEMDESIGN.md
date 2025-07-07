## Audio Architecture Overview
The audio system is built around AVAudioEngine with a custom timer-driven segmentation loop. It supports:

Real-time segmentation of live audio streams

Microphone level visualization

Background-safe, long-form recording

Interrupt-resilient session management

Post-processing for transcription readiness

While AVAudioEngine was part of the assignment requirement, we chose to implement our own timer-based segmentation layer rather than relying on timestamps inside the audio buffer, to maximize reliability during route changes and engine stalls.

We avoided AVAudioRecorder due to its limitations around mid-stream segmentation and opted for installTap via inputNode for full control over the buffer pipeline.

## Real-Time Recording & Segmentation
Audio is captured by installing a tap on the engine’s input node and writing buffers to disk in .wav format:

swift
Copy
Edit
inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, time in
    try? self.audioFile?.write(from: buffer)
    self.updateAudioLevel(from: buffer)
}
A timer triggers every N seconds (default 30s) to:

Finalize and close the current file

Save metadata to SwiftData

Spawn a new .wav file and reinitialize the engine

This timer-based segmentation is completely decoupled from the audio buffer itself, ensuring that segments are created reliably even under iOS interruptions or route changes.

## Audio Format Decisions
Stage    Format    Reason
Live capture    WAV    Low-latency, compatible with AVFoundation, lossless
Post-process    M4A    Required by Whisper API
Upload    M4A    Sent to OpenAI via multipart/form-data
Fallback use    WAV    Used for Apple Speech recognition

Although we record in WAV (for control and quality), Whisper requires .m4a input. We convert the segment using AVAssetExportSession during post-processing.

Filenames are UUID-based to prevent collisions. SwiftData stores the file path for retrieval and deletion.

## Apple Speech Fallback – Unexpected Hurdles
A major requirement was a fallback to Apple’s on-device speech recognition after 5 Whisper failures.

We integrated SFSpeechRecognizer and attempted to use .wav segments via AVAudioFile(url:), but consistently hit unhelpful errors like:

“The file couldn’t be opened.”

This bug cost us hours. The root issue turned out to be that the audio engine was not completely stopped and finalized. Even though the .wav file existed and had content, it remained locked and inaccessible.

Fix: We explicitly stopped and reset the engine before finalizing the file:

swift
Copy
Edit
audioEngine.stop()
audioEngine.reset()
audioFile = nil
Once implemented, both Whisper and Apple Speech were able to transcribe the file — revealing how long AVAudioEngine holds onto file locks even after writing completes.

This debugging cycle taught us to treat engine teardown as an essential part of file lifecycle.

## Audio Level Visualization
We calculate microphone loudness using RMS (Root Mean Square) of each audio buffer:

swift
Copy
Edit
let rms = sqrt(sum / Float(frameLength))
This yields a natural-feeling volume meter and avoids the spiky behavior of peak detection.

## Background Recording Support
We enabled audio background mode in Info.plist:

xml
Copy
Edit
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
We also use UIApplication.shared.beginBackgroundTask() during file finalization and transcription to ensure iOS doesn’t terminate the app mid-process.

Tested behaviors:

Locking the screen mid-recording

App switching during recording

Background recording under low battery

## Interruption Handling
✅ Working Cases
Siri activation

Phone calls

Bluetooth route changes

Control Center output switch

Each of these triggers AVAudioSessionInterruptionNotification or a route change event. Our strategy is:

Pause the audio engine

Pause the segment timer

Rebuild the engine and resume tap after the interruption ends

⚠️ Known Issue: Headphone Edge Case
Rapidly plugging/unplugging wired headphones or toggling AirPods mid-segment can sometimes cause:

AVAudioEngine crash: format.sampleRate == hwFormat.sampleRate assertion

This seems tied to sample rate mismatches after the route changes. We’ve tried:

Resetting the engine

Re-reading the hardware format before installing the tap

Matching input format manually

Still, the issue appears sporadically. We now log the incident and attempt a soft recovery, but this area needs further hardening.

## Error Handling & Resilience
Failure Type    Mitigation
Whisper rejects file    Log + fallback to Apple Speech
Apple Speech fails    Only used after 5 Whisper failures
File has 0s duration    Skip, don’t queue for transcription
Audio file not finalized    Reset engine every segment cycle
Route change engine crash    Try full engine re-init and recovery

## Testing & Validation
We tested the following scenarios:

Siri / phone call interruptions

AirPods unplugged mid-recording

Recording while backgrounded

Exported file playback and share

Retry after network loss or Whisper failure

## Takeaways
AVAudioEngine gives fine control but requires rigorous teardown to avoid locking files or stalling taps.

Apple Speech requires fully finalized files — not just valid paths or content.

Timer-based segmentation is more robust than buffer-tied timestamps in a mobile context.

Route changes remain the least predictable area, and demand low-level sample rate inspection to avoid crashes.
