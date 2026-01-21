//
//  FileWatcher.swift
//  Van
//
//  Created by Antigravity on 2026-01-20.
//  Monitor local Skill directory changes and trigger sync
//

import Foundation
import Combine

/// File system monitor: listens for directory changes
class FileWatcher: ObservableObject {
    static let shared = FileWatcher()
    
    // Publishes source ID when monitored directory changes
    let changedSourcePublisher = PassthroughSubject<UUID, Never>()
    
    private var watchers: [UUID: WatcherInfo] = [:]
    private let queue = DispatchQueue(label: "com.van.filewatcher", qos: .utility)
    
    private struct WatcherInfo {
        let sources: [DispatchSourceFileSystemObject]
        let paths: [String]
    }
    
    /// Start monitoring for a specific source's skill directories
    func startWatching(source: SkillSource) {
        // Only monitor local sources
        guard source.typeRaw != SkillSource.SourceType.subscription.rawValue else { return }
        guard !source.localPathString.isEmpty else { return }
        
        // Stop previous monitoring
        stopWatching(sourceId: source.id)
        
        let baseUrl = URL(fileURLWithPath: source.localPathString)
        
        // Directories to monitor
        let watchPaths = [
            baseUrl.appendingPathComponent(".agent/skills"),
            baseUrl.appendingPathComponent(".cursor/rules"),
            baseUrl.appendingPathComponent("skills")
        ]
        
        var activeSources: [DispatchSourceFileSystemObject] = []
        var activePaths: [String] = []
        
        for path in watchPaths {
            // Ensure directory exists
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            
            // Create file descriptor
            let fd = open(path.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            
            // Create DispatchSource
            let dispatchSource = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .extend],
                queue: queue
            )
            
            let sourceId = source.id
            
            dispatchSource.setEventHandler { [weak self] in
                print("[FileWatcher] Change detected in: \(path.path)")
                // Debounce: wait for 500ms before triggering sync
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.changedSourcePublisher.send(sourceId)
                }
            }
            
            dispatchSource.setCancelHandler {
                close(fd)
            }
            
            dispatchSource.resume()
            activeSources.append(dispatchSource)
            activePaths.append(path.path)
            
            print("[FileWatcher] Started watching: \(path.path)")
        }
        
        if !activeSources.isEmpty {
            watchers[source.id] = WatcherInfo(sources: activeSources, paths: activePaths)
        }
    }
    
    /// Stop monitoring a specific source
    func stopWatching(sourceId: UUID) {
        if let info = watchers.removeValue(forKey: sourceId) {
            for source in info.sources {
                source.cancel()
            }
            print("[FileWatcher] Stopped watching source: \(sourceId)")
        }
    }
    
    /// Stop all monitoring
    func stopAll() {
        for (id, _) in watchers {
            stopWatching(sourceId: id)
        }
    }
}
