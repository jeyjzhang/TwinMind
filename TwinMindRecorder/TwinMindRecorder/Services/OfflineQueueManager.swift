//
//  OfflineQueueManager.swift
//  TwinMindRecorder
//
//  Created by Jerry Zhang on 2025-07-06.
//

import Foundation

actor OfflineQueueManager {
    static let shared = OfflineQueueManager()

    private let storageURL: URL = {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("offlineQueue.json")
    }()

    private var segmentIDs: Set<String> = []

    init() {
        load()
    }

    private func load() {
        if let data = try? Data(contentsOf: storageURL),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            self.segmentIDs = Set(ids)
        }
    }

    private func save() {
        let array = Array(segmentIDs)
        try? JSONEncoder().encode(array).write(to: storageURL)
    }

    func add(_ segmentID: String) {
        segmentIDs.insert(segmentID)
        save()
    }

    func remove(_ segmentID: String) {
        segmentIDs.remove(segmentID)
        save()
    }

    func all() -> [String] {
        Array(segmentIDs)
    }

    func clear() {
        segmentIDs.removeAll()
        save()
    }
}
