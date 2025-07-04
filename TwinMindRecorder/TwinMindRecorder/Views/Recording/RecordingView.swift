//
//  RecordingView.swift
//  TwinMindRecorder
//
//  Created by Jerry Zhang on 2025-07-02.
//

import SwiftUI
import SwiftData

struct RecordingView: View {
    @StateObject private var audioService = AudioService()
    @Environment(\.modelContext) private var modelContext
    @State private var sessionTitle = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Recording Status
                VStack(spacing: 10) {
                    Text(audioService.isRecording ? "Recording..." : "Ready to Record")
                        .font(.title2)
                        .foregroundColor(audioService.isRecording ? .red : .primary)
                    
                    if audioService.isRecording {
                        Text(formatDuration(audioService.recordingDuration))
                            .font(.title)
                            .monospacedDigit()
                    }
                }
                
                // Audio Level Visualization
                if audioService.isRecording {
                    AudioLevelView(level: audioService.audioLevel)
                }
                
                // Session Title Input
                if !audioService.isRecording {
                    TextField("Session Title (Optional)", text: $sessionTitle)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)
                }
                
                // Recording Controls
                VStack(spacing: 20) {
                    if audioService.isRecording {
                        Button("Stop Recording") {
                            audioService.stopRecording()
                            sessionTitle = "" // Reset title
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.red)
                    } else {
                        Button("Start Recording") {
                            let title = sessionTitle.isEmpty ? nil : sessionTitle
                            audioService.startRecording(title: title, modelContext: modelContext)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!audioService.hasPermission)
                    }
                }
                
                // Permission Status
                if !audioService.hasPermission {
                    Text("Microphone permission required")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Record")
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// Simple audio level visualization
struct AudioLevelView: View {
    let level: Float
    
    var body: some View {
        VStack {
            Text("Audio Level")
                .font(.caption)
                .foregroundColor(.secondary)
            
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        HStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.green)
                                .frame(width: geometry.size.width * CGFloat(min(level * 10, 1.0)))
                            Spacer()
                        }
                    )
            }
            .frame(height: 20)
            .padding(.horizontal)
        }
    }
}

#Preview {
    RecordingView()
}
