# TwinMind iOS Audio Recorder

An iOS app for capturing real-time audio, segmenting it automatically, and transcribing it with a combination of OpenAI Whisper API and local fallback models. Built with Swift, SwiftUI, SwiftData, and AVFoundation.

## Setup Instructions

1. Clone the repo:

   ```bash
   git clone https://github.com/YOUR_USERNAME/twinmind-recorder.git
   ```

2. Open in Xcode (ensure you're using Xcode 15+).

3. Add your OpenAI API key:

   * Create `Secrets.xcconfig` in the root directory:

     ```
     OPENAI_API_KEY=sk-proj-...
     ```
   * In Xcode, go to Project > Info > Configurations and set your Debug and Release builds to use this file.

4. Build & run on a physical iOS device (mic required).

## More detailed documentation in individual MD files

## Features

* Continuous background recording with segmentation (default: 30s)
* Whisper API + automatic fallback to Apple Speech if API fails 5+ times
* Visual audio level monitoring
* Offline queue for retrying failed transcriptions
* SwiftData-based session/segment model with 1\:many relationships
* Export transcription text as `.txt`
* VoiceOver and accessibility labels for major UI components
* Session list with pull-to-refresh, virtualization
* Transcription progress indicators per session

## Architecture Overview

### MVVM + Services

* `RecordingViewModel`: Main AVAudioEngine manager
* `AudioTranscriptionService`: Whisper + Apple Speech, retry logic
* `AudioConversionService`: WAV→M4A conversion and transcription
* `OfflineQueueManager`: Handles retryable audio segments

### Storage

* SwiftData used to store:

  * `RecordingSession`
  * `AudioSegment`
  * `Transcription`
* Relationships fully modeled with lazy loading

### Security

* API key stored in Keychain
* Audio files use `.completeUntilFirstUserAuthentication` file protection

## Audio System Design

* Uses `AVAudioEngine` with manual tap and segmentation timers
* Handles:

  * Audio interruptions (`AVAudioSession.InterruptionType`)
  * Audio route changes (e.g. headphone plug/unplug)
  * Background audio (ensures session remains active)
* Supports Bluetooth + built-in mic
* Detects engine state before processing each segment

## Data Model Design

```swift
RecordingSession {
  var id: UUID
  var title: String?
  var startTime: Date
  var segments: [AudioSegment]
}

AudioSegment {
  var id: UUID
  var audioFilePath: String
  var startTime: TimeInterval
  var duration: TimeInterval
  var transcription: Transcription?
}

Transcription {
  var id: UUID
  var status: .queued | .processing | .completed | .failed
  var text: String?
  var errorMessage: String?
  var retryCount: Int
}
```

## Known Issues / Areas for Improvement

* No automatic cleanup of old audio files yet
* Local fallback works but is not optimized for Whisper.cpp
* No waveform visualization
* File export supports `.txt`, not `.m4a` yet
* No integration with Core ML on-device models (planned)

## Testing Summary

* ✅ Manual tests for:

  * Audio interruptions and route changes
  * Network drop / retry logic
  * App termination mid-recording
*  Minimal unit tests (due to time constraints)

## Acknowledgements

* OpenAI Whisper API
* Apple Speech framework
* Inspired by Apple's AudioUnit sample code

---

> Built by Jerry Zhang for the TwinMind iOS Developer take-home assignment.
