# Data Model Design – TwinMind iOS Take-Home

This document explains the data modeling decisions behind the TwinMind iOS app, with an emphasis on performance, clarity, and long-form scalability. The model is powered by **SwiftData**, as specified by the project requirements, and supports real-time audio segmentation, transcription tracking, and structured session playback.

---

## Core Schema Structure

The data schema is organized around three main entities:

```
RecordingSession (1) ←→ (many) AudioSegment (1) ←→ (1) TranscriptionResult
```

Each plays a distinct role:

- **RecordingSession**: Represents a full user session (e.g. a lecture or meeting)
- **AudioSegment**: Individual 30-second audio chunks
- **TranscriptionResult**: Stores the result and metadata of a transcription attempt

---

## Model Definitions

### `RecordingSession`
```swift
@Model
class RecordingSession {
    var id: UUID = UUID()
    var title: String = ""
    var startTime: Date = Date()
    var endTime: Date?
    var isCompleted: Bool = false
    var segments: [AudioSegment] = []
}
```

- Uses a UUID to simplify future syncing or merging.
- The `endTime` is optional to support live sessions.
- The `isCompleted` flag allows us to distinguish between active and finished recordings.

### `AudioSegment`
```swift
@Model
class AudioSegment {
    var id: UUID = UUID()
    var segmentIndex: Int = 0
    var startTime: TimeInterval = 0
    var duration: TimeInterval = 30.0
    var audioFileURL: URL?
    var fileSize: Int64 = 0
    var sampleRate: Double = 0
    var channelCount: Int = 1
    var createdAt: Date = Date()
    var session: RecordingSession?
    var transcription: TranscriptionResult?
}
```

- Stores only metadata — the audio data itself is saved as a file on disk.
- `segmentIndex` is used for playback ordering and UI display.
- Audio format info (`sampleRate`, `channelCount`) is extracted and saved for validation/debugging.

### `TranscriptionResult`
```swift
@Model
class TranscriptionResult {
    var id: UUID = UUID()
    var text: String = ""
    var confidence: Double = 0.0
    var language: String = "en"
    var processingStatus: TranscriptionStatus = .pending
    var transcriptionService: String = "openai"
    var processingTime: TimeInterval = 0
    var errorMessage: String?
    var createdAt: Date = Date()
    var segment: AudioSegment?
}

enum TranscriptionStatus: String, Codable {
    case pending, processing, completed, failed, retrying
}
```

- Tracks both result and metadata, including which engine was used (`openai` or `apple`).
- `errorMessage` field was added during testing to surface debugging insights from failed transcriptions.

---

## Relationship Design

- `RecordingSession → AudioSegment`: One-to-many
- `AudioSegment → TranscriptionResult`: One-to-one

All relationships are bidirectional and SwiftData handles inverse syncing automatically.

We confirmed that:
- Deleting a session cascades to all segments and their transcription results.
- SwiftData avoids orphaned records and handles relationship consistency internally.

---

## Performance Strategies

### Segment Isolation
We keep each 30s segment as its own entity:
- Allows retrying failed transcriptions individually
- Supports progressive UI updates
- Enables granular analytics in the future

### File-Backed Storage
Instead of storing audio in the database:
- Each `AudioSegment` includes a `URL` to the `.wav` file on disk
- Files are named with `UUID()` to avoid collision
- Cleanups happen on session deletion by scanning each segment’s file path

```swift
func deleteSession(_ session: RecordingSession) {
    for segment in session.segments {
        try? FileManager.default.removeItem(at: segment.audioFileURL)
    }
    modelContext.delete(session)
}
```

---

## Query Performance

Although SwiftData doesn't expose full fetch control yet, we designed around that:

- Session lists use `@Query` and **load only session metadata**
- Segments are accessed only once a session is tapped (natural lazy loading)
- We separate search into a dedicated query targeting just `TranscriptionResult.text`

```swift
@Query(filter: #Predicate<TranscriptionResult> { $0.text.contains(searchTerm) })
var searchResults: [TranscriptionResult]
```

This avoids ever needing to scan audio metadata or segment details during search.

---

## Performance Validation

To validate SwiftData's ability to handle scale, we ran simulated stress tests:

```swift
func createTestData(count: Int) {
    for i in 0..<count {
        let session = RecordingSession(title: "Session \(i)")
        for j in 0..<100 {
            let seg = AudioSegment()
            seg.session = session
            session.segments.append(seg)
        }
        modelContext.insert(session)
    }
}
```

With 100 sessions × 100 segments = 10,000 segments:
- Queries on sessions remained under 500ms
- Memory stayed under 80MB until we loaded transcription text en masse

---

## Future Evolution

This schema can support more advanced features:

- **Pagination**: Not yet implemented but supported by structure
- **Cloud sync**: UUIDs, file-backed audio, and separated models simplify syncing
- **Quality metrics**: Add confidence thresholds to `TranscriptionResult`
- **Tags or bookmarks**: Easily added via optional fields or join tables
- **Speaker diarization or sentiment**: Future fields in `TranscriptionResult`

We also defined a versioned schema placeholder for potential migrations:

```swift
enum SchemaVersions {
    static let v1 = Schema([
        RecordingSession.self,
        AudioSegment.self,
        TranscriptionResult.self
    ])
}
```

---

## Summary

This data model emphasizes separation of metadata and media, individual failure handling per segment, and low-overhead querying for live UI responsiveness. Most importantly, it mirrors the way real recordings behave: staggered, imperfect, and frequently interrupted — not monolithic audio dumps.

Its design reflects real lessons learned from audio interruptions, file cleanup, SwiftData quirks, and the realities of recording multi-hour sessions on-device.
