//
//  SessionDetailView.swift
//  TwinMindRecorder
//
//  Created by Jerry Zhang on 2025-07-03.
//

import SwiftUI
import SwiftData
import UIKit

struct SessionDetailView: View {
    @EnvironmentObject var transcriptionService: AudioTranscriptionService

    @Environment(\.modelContext) private var modelContext
    let session: RecordingSession

    // Refreshable data source
    @State private var segments: [AudioSegment] = []
    
    @State private var isSharing = false
    @State private var isSharingFile = false
    @State private var shareItem: URL? = nil
    


    var body: some View {
        List {
            // Session Info
            Section(header: Text("Session Info")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.title ?? "Untitled Session")
                        .font(.headline)
                    Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Total Duration: \(formatDuration(session.totalDuration))")
                        .font(.caption2)
                }
                .padding(.vertical, 4)
            }

            // Transcription Progress
            Section(header: Text("Transcription Progress")) {
                ProgressView(value: session.transcriptionProgress)
                Text("\(session.completedTranscriptions.count) of \(session.segments.count) completed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Segment List
            Section(header: Text("Segments")) {
                ForEach(segments.sorted(by: { $0.startTime < $1.startTime })) { segment in
                    SegmentRowView(segment: segment, transcriptionService: transcriptionService, modelContext: modelContext)
                }
            }
        }
        .navigationTitle("Session Details")
        .sheet(isPresented: $isSharing) {
            ShareSheet(activityItems: [session.fullTranscriptionText])
        }
        .sheet(isPresented: $isSharingFile) {
            if let file = shareItem {
                ShareSheet(activityItems: [file])
            }
        }
        .onAppear {
            segments = session.segments
        }
        .refreshable {
            segments = session.segments
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        isSharing = true
                    } label: {
                        Label("Copy Text", systemImage: "doc.on.doc")
                    }

                    Button {
                        exportTranscriptionAsTextFile()
                    } label: {
                        Label("Export as .txt", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }


    }
    func exportTranscriptionAsTextFile() {
        let text = session.fullTranscriptionText
        let fileName = (session.title ?? "Transcription").replacingOccurrences(of: " ", with: "_")
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).txt")

        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            // Share the file using ShareSheet
            shareItem = fileURL
            isSharingFile = true
        } catch {
            print("❌ Failed to write .txt file: \(error)")
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .short
        return formatter.string(from: duration) ?? "0s"
    }
}



struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // Nothing to update
    }
}
