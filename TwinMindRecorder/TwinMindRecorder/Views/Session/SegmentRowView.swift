//
//  SegmentRowView.swift
//  TwinMindRecorder
//
//  Created by Jerry Zhang on 2025-07-05.
//

import SwiftUI
import SwiftData
import SwiftUI
import SwiftData
import UIKit

struct SegmentRowView: View {
    let segment: AudioSegment
    let transcriptionService: AudioTranscriptionService
    let modelContext: ModelContext

    @State private var showingShareSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Segment @ \(formatTime(segment.startTime))")
                .font(.subheadline)
                .bold()

            switch segment.transcription?.status {
            case .completed:
                VStack(alignment: .leading, spacing: 4) {
                    Text(segment.transcription?.text ?? "[No Text]")
                        .font(.body)

                    if segment.transcription?.transcriptionService == .appleSpeech {
                        Text("(via Apple Speech)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

            case .queued, .processing:
                Label(segment.transcription?.status == .processing ? "Processing..." : "Queued", systemImage: "hourglass")
                    .foregroundColor(.blue)
                    .font(.caption)

            case .failed:
                VStack(alignment: .leading, spacing: 4) {
                    Label("Failed: \(segment.transcription?.errorMessage ?? "Unknown")", systemImage: "xmark.octagon")
                        .foregroundColor(.red)
                        .font(.caption)

                    if segment.transcription?.canRetry ?? false {
                        Button {
                            transcriptionService.queueForTranscription(segment, modelContext: modelContext)
                            print("🔁 Manually requeued segment: \(segment.audioFilePath)")
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                }

            default:
                Text("Waiting for transcription")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            // 🔊 Export button for debugging
            Button("Export .wav") {
                showingShareSheet = true
            }
            .font(.caption2)

        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingShareSheet) {
            ActivityView(fileURL: segment.audioFileURL)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
