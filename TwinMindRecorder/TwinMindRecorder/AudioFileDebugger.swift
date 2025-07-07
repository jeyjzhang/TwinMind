//
//  AudioFileDebugger.swift
//  TwinMindRecorder
//
//  Created by Jerry Zhang on 2025-07-05.
//

import Foundation
import AVFoundation

struct AudioFileDebugger {
/*
    /// Debug an audio file and print detailed information
    static func debugAudioFile(at url: URL) {
        print("🔍 DEBUGGING AUDIO FILE: \(url.lastPathComponent)")
        
        // Check if file exists
        let fileExists = FileManager.default.fileExists(atPath: url.path)
        print("📁 File exists: \(fileExists)")
        
        if fileExists {
            // Get file size
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                print("📏 File size: \(fileSize) bytes")
                
                if fileSize == 0 {
                    print("🚨 FILE IS EMPTY! This is why transcription fails.")
                    return
                }
                
            } catch {
                print("❌ Could not read file attributes: \(error)")
            }
            
            // Try to read as AVAsset
            let asset = AVAsset(url: url)
            
            Task {
                do {
                    // Get duration
                    let duration = try await asset.load(.duration)
                    let seconds = CMTimeGetSeconds(duration)
                    print("⏱️ Duration: \(seconds) seconds")
                    
                    if seconds == 0 {
                        print("🚨 DURATION IS ZERO! Audio was not properly recorded.")
                    }
                    
                    // Get tracks
                    let tracks = try await asset.loadTracks(withMediaType: .audio)
                    print("🎵 Audio tracks: \(tracks.count)")
                    
                    for (index, track) in tracks.enumerated() {
                        let timeRange = try await track.load(.timeRange)
                        let trackDuration = CMTimeGetSeconds(timeRange.duration)
                        print("   Track \(index): \(trackDuration) seconds")
                        
                        // Get format descriptions
                        let formatDescs = try await track.load(.formatDescriptions)
                        for desc in formatDescs {
                            if let audioDesc = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                                let sampleRate = audioDesc.pointee.mSampleRate
                                let channels = audioDesc.pointee.mChannelsPerFrame
                                let bitsPerChannel = audioDesc.pointee.mBitsPerChannel
                                print("   📊 Format: \(sampleRate)Hz, \(channels)ch, \(bitsPerChannel)bit")
                            }
                        }
                    }
                    
                    // Try to read raw data
                    do {
                        let data = try Data(contentsOf: url)
                        print("💾 Raw data size: \(data.count) bytes")
                        
                        if data.count < 100 {
                            print("🚨 FILE TOO SMALL! Likely not properly written.")
                            // Print first few bytes
                            let preview = data.prefix(50).map { String(format: "%02x", $0) }.joined(separator: " ")
                            print("🔍 First bytes: \(preview)")
                        }
                        
                    } catch {
                        print("❌ Could not read raw data: \(error)")
                    }
                    
                } catch {
                    print("❌ Asset loading failed: \(error)")
                }
            }
            
        } else {
            print("🚨 FILE DOES NOT EXIST!")
        }
    }
    
    /// Call this right after you think you've saved an audio file
    static func verifyRecordingSuccess(fileURL: URL, expectedDurationSeconds: Double) {
        print("\n" + "="*50)
        print("🧪 VERIFYING RECORDING SUCCESS")
        print("Expected duration: \(expectedDurationSeconds) seconds")
        debugAudioFile(at: fileURL)
        print("="*50 + "\n")
    }*/
}
