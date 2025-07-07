
## Known Issues

### Audio File Validity (Whisper Rejections)
- Some `.wav` files — particularly after interruptions or route changes — occasionally fail Whisper transcription with vague "invalid file" errors.
- Cause was traced to improper `AVAudioEngine` shutdown before finalizing segments. Fixes were applied (`stop()` + `reset()`), but race conditions may still persist during fast route switches or background transitions.

### Audio Route Change Instability
- Unplugging wired headphones or toggling Bluetooth devices mid-segment sometimes causes `AVAudioIONodeImpl` crashes due to mismatched hardware sample rates.
- Engine restarts were attempted, including manual sample rate validation, but not always successful. This remains a known instability in audio session handling.

### Offline Transcription Queue
- Offline segments are queued using `OfflineQueueManager`, but error handling is brittle if `modelContext` isn’t passed properly (e.g., from a background thread).
- Can crash on retry or fail silently. Would benefit from refactor to fully isolate retry logic and validate segment state before processing.

### Apple Speech Fallback Reliability
- Apple Speech was implemented as a fallback after 5 failed Whisper attempts.
- However, file compatibility is fragile. Even minor issues like file locks or missing audio duration can cause silent failures.
- File validation before fallback is minimal and should be hardened with additional diagnostics.

### Incomplete Audio File Encryption
- No custom encryption implemented. Relies only on `.completeUntilFirstUserAuthentication` file protection.
- Sensitive audio files are not encrypted at rest beyond iOS defaults.

### No In-App Playback
- Export via share sheet works, but there is no UI for playback or previewing audio segments directly within the app.

---

## Areas for Improvement

### Background Termination Handling
- App supports background recording via `UIBackgroundModes`, but behavior during low battery, system memory pressure, or app termination mid-segment was not fully tested.
- Future improvement: Store segment state preemptively and detect incomplete recordings on launch.

### Performance Optimization for Large Datasets
- App was architected with 10K+ segments in mind (SwiftData relationships, potential pagination), but no pagination or batch query optimization was implemented.
- UI may degrade when viewing large session histories or performing rapid navigation.
- Given more time, we would implement cursor-based pagination and limit the number of segments fetched in `SessionDetailView`.

### Battery and Memory Profiling
- Long-form recording (e.g. 12+ hours) is supported in architecture, but not tested under real-world constraints like low battery or background wakeups.
- No battery usage or memory footprint metrics were collected. Given more time, we would simulate extended use, monitor memory graphs, and instrument background task expiration events.

### Accessibility Audit
- Basic accessibility labels and VoiceOver traits were added, but a full audit was not performed.
- UI should be reviewed for focus order, dynamic text support, and haptics where appropriate.

### Edge Case Testing and Error Surfacing
- Some transcription errors, network issues, or malformed files do not surface clearly to the user.
- Future iterations would benefit from UI feedback for failed transcriptions, clearer diagnostics, and manual override tools.

---

## Deferred Features

These features were planned but not implemented due to time constraints:

- Segment pagination for large sessions
- User-configurable audio quality settings
- Multi-language transcription selection
- In-app WAV/M4A audio preview
- Cloud sync or export to third-party storage (iCloud, Files)
- Automatic cleanup of failed or stale segments
- Secure transmission (encryption-in-transit beyond HTTPS)
