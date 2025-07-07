# Architecture Overview – TwinMind iOS Take-Home

This document captures the architectural decisions, tradeoffs, and evolution of the TwinMind Recorder app. Built over a few focused days, it reflects not just a response to a spec—but a deeper engagement with audio system design, SwiftData modeling, and real-world edge cases in iOS development.

---

## System Design Philosophy

The app is built around a **MVVM + service-layer** architecture:

View (SwiftUI) → ViewModel (ObservableObject) → Service Layer → Model (SwiftData)


Each layer plays a distinct role:

- **SwiftUI Views** handle display and user interaction only.
- **ViewModels** manage state, AVAudioEngine control, and publishing.
- **Service classes** handle long-running or async tasks like transcription and conversion.
- **SwiftData Models** persist all domain data (recordings, segments, transcripts) in a structured schema.

This separation enabled rapid iteration and makes the system more testable and modular.

---

## Core Components

### Views
- `RecordingView`: Live audio meter, duration, and controls. Uses `@Published` state.
- `SessionListView`: Lists completed sessions with live transcription status.
- `SessionDetailView`: Shows 30s segments, status indicators, and transcription text.

### ViewModels
- `RecordingViewModel`: Controls the AVAudioEngine lifecycle, manages segmentation and file creation, handles route/interruption events, and publishes real-time state (`isRecording`, `audioLevel`, etc).

### Services
- `AudioTranscriptionService`: Handles Whisper API upload, retry/backoff, and Apple Speech fallback.
- `AudioConversionService`: Converts `.wav` → `.m4a` using `AVAssetExportSession`.
- `OfflineQueueManager`: Manages retry attempts for failed segments, with network awareness.

---

## Data Flow Overview

1. **User starts recording**
2. **AVAudioEngine** captures buffers via `installTap` and writes them to `.wav`
3. Every 30 seconds:
   - Current file is finalized
   - Metadata saved to `AudioSegment` via SwiftData
   - File queued for transcription
4. Transcription result updates the linked `Transcription` model
5. SwiftUI reflects changes automatically via `@Query`

---

## Engineering Tradeoffs and Rationale

### AVAudioEngine vs AVAudioRecorder

This wasn’t a design decision—it was a requirement. But we leaned into the flexibility `AVAudioEngine` provides:

- Tapped the input node directly to stream buffers to disk.
- Could visualize live audio levels with custom RMS computation.
- Enabled precise control over file start/stop around 30s marks.

Downside: AVAudioEngine brings more surface area for bugs—especially around audio route changes and file locking. We invested heavily in defensive handling (see Audio System docs).

---

### SwiftData as Persistence Layer

We originally considered Core Data but chose SwiftData because:

- `@Model` and `@Query` simplify binding SwiftUI state.
- Relationships (`RecordingSession` → `AudioSegment` → `Transcription`) are intuitive and easy to query.
- Prototype-speed was essential, and SwiftData enabled rapid iteration.

Performance-wise:
- Segment relationships are only queried when needed (no eager loading).
- Views like `SessionListView` use pagination-friendly structures, though full lazy loading would be a future addition.

---

### MVVM for Modular Separation

MVVM offered a clean structure:

- View logic never touches the audio engine.
- RecordingViewModel owns the lifecycle of each session.
- All long-running work (conversion, upload) is kicked off from services, not Views.

This structure became essential when we introduced background handling and retry logic, which need to outlive any single view’s lifecycle.

---

## Notable Architectural Enhancements

### Audio File Lifecycle
- All filenames use `UUID()` to avoid naming conflicts.
- Files written as `.wav` to allow uncompressed, low-latency writing.
- Later converted to `.m4a` before upload to Whisper.
- SwiftData stores only relative paths (not blobs).

### File Protection
We enabled `FileProtectionType.completeUntilFirstUserAuthentication` on all written segments for better at-rest security (pending full encryption).

### Offline Queueing
We added `NWPathMonitor` and deferred transcription attempts until the device was online again. These segments persist across app launches and are retried safely in background-safe tasks.

---

## Real-World Debugging Moments

### 1. **Apple Speech Wouldn’t Recognize Our Files**
This became a significant rabbit hole. Even though `.wav` files existed and had content, Apple’s `SFSpeechRecognizer` threw cryptic errors like:

> "The file couldn't be opened."

Eventually, we realized AVAudioEngine was **not fully stopped**, and the file lock wasn't released—despite the file existing. Adding `audioEngine.stop()` and `reset()` before segment handoff fixed it.

This reinforced how tightly AVAudioEngine holds file handles.

---

### 2. **modelContext Injection Edge Cases**
Some background tasks (like retrying failed transcriptions) initially crashed because `@Environment(\.modelContext)` was unavailable in non-view scopes. We later ensured it was passed explicitly to all services, or accessed safely using a wrapper.

---

### 3. **UI Not Updating After State Changes**
Despite using `@Query`, we found UI elements didn’t always reflect transcription state updates. This was due to SwiftData not always triggering view updates for nested relationships (e.g., `segment.transcription.status`). In some places, we worked around this by refreshing lists or adding explicit state bindings.

---

## Planned Scalability Improvements

- **Pagination**: Current `SessionListView` loads all sessions—future versions will limit with offsets or time windows.
- **Directory structure**: 10K+ files in a single folder is suboptimal. We plan to bucket files into subdirectories by session UUID or date.
- **On-device model switching**: We laid groundwork for quality-based fallback (e.g. Apple if Whisper fails + confidence is low).
- **Better crash recovery**: Currently mid-segment crashes may result in 0s duration files. Auto-cleanup and retry logic will be improved.

---

## Reflections on the Architecture

What started as a simple MVVM app quickly grew into a production-grade audio recorder. The architecture scaled well under pressure, especially:

- Handling route changes mid-segment
- Surviving backgrounding + low memory situations
- Keeping the UI reactive without over-fetching data

The service-oriented approach gave us flexibility: conversion, transcription, and offline logic all evolved independently.

Overall, this architecture reflects real-world constraints, debug-driven learning, and a focus on resilience—something critical for any system aspiring to become a user’s "second brain."

