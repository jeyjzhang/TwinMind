//
//  RecordingView.swift
//  TwinMindRecorder
//
//  Created by Jerry Zhang on 2025-07-02.
//

import SwiftUI
import SwiftData

struct RecordingView: View {
    @StateObject private var viewModel = RecordingViewModel()
    @Environment(\.modelContext) private var modelContext
    @State private var sessionTitle = ""
    @State private var selectedQuality: AudioQuality = .medium

    
    var body: some View {
        NavigationView {
            if viewModel.hasPermission {
                mainRecordingUI
            } else {
                permissionDeniedView
            }
            
        }
    }
    
    private var mainRecordingUI: some View {
        VStack(spacing: 30) {
            // Recording Status
            VStack(spacing: 10) {
                Text(viewModel.isRecording ? "Recording..." : "Ready to Record")
                    .font(.title2)
                    .foregroundColor(viewModel.isRecording ? .red : .primary)
                    .accessibilityLabel(viewModel.isRecording ? "Recording in progress" : "Ready to record")
                
                if viewModel.isRecording {
                    Text(formatDuration(viewModel.recordingDuration))
                        .font(.title)
                        .monospacedDigit()
                }
            }
            
            // Audio Level Visualization
            if viewModel.isRecording {
                AudioLevelView(level: viewModel.audioLevel)
            }
            
            // Session Title Input
            if !viewModel.isRecording {
                TextField("Session Title (Optional)", text: $sessionTitle)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
            }
            if viewModel.hasLowStorage {
                VStack(spacing: 10) {
                    Text("⚠️ Low Storage")
                        .font(.headline)
                        .foregroundColor(.red)
                    Text("You need at least 100MB of free space to record.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }

            
            // Recording Controls
            VStack(spacing: 20) {
                if viewModel.isRecording {
                    Button("Stop Recording") {
                        viewModel.stopRecording()
                        sessionTitle = "" // Reset title
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.red)
                } else {
                    if !viewModel.isRecording {
                        Picker("Quality", selection: $selectedQuality) {
                            ForEach(AudioQuality.allCases, id: \.self) { quality in
                                Text(quality.rawValue.capitalized)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    }
                    Text("Segment Length")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Section(header: Text("Segment Duration")) {
                        Picker("Segment Duration", selection: $viewModel.segmentDuration) {
                            ForEach([15.0, 30.0, 60.0, 120.0], id: \.self) { duration in
                                Text("\(Int(duration)) seconds")
                            }
                        }
                        .pickerStyle(.segmented)
                    }



                    Button("Start Recording") {
                        let title = sessionTitle.isEmpty ? nil : sessionTitle
                        viewModel.startRecording(title: title, modelContext: modelContext, quality: selectedQuality)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!viewModel.hasPermission || viewModel.hasLowStorage)
                }
            }
            
            // Permission Status
            if !viewModel.hasPermission {
                Text("Microphone permission required")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Record")
    }
    
    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.slash.fill")
                .resizable()
                .frame(width: 60, height: 60)
                .foregroundColor(.red)

            Text("Microphone access is required to record audio.")
                .font(.headline)
                .multilineTextAlignment(.center)

            Button("Open Settings") {
                openAppSettings()
            }
            .buttonStyle(.borderedProminent)

            Text("Enable microphone access in Settings > Privacy > Microphone.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .navigationTitle("Permission Needed")
    }


    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    func openAppSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString),
           UIApplication.shared.canOpenURL(settingsURL) {
            UIApplication.shared.open(settingsURL)
        }
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
