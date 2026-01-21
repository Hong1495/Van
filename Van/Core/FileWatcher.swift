//
//  FileWatcher.swift
//  Van
//
//  Created by Antigravity on 2026-01-20.
//  监控本地 Skill 目录变化，自动触发同步
//

import Foundation
import Combine

/// 文件系统监控器：监听目录变化并发送通知
class FileWatcher: ObservableObject {
    static let shared = FileWatcher()
    
    // 当监控的目录发生变化时发送源 ID
    let changedSourcePublisher = PassthroughSubject<UUID, Never>()
    
    private var watchers: [UUID: WatcherInfo] = [:]
    private let queue = DispatchQueue(label: "com.van.filewatcher", qos: .utility)
    
    private struct WatcherInfo {
        let sources: [DispatchSourceFileSystemObject]
        let paths: [String]
    }
    
    /// 开始监控指定源的所有 Skill 目录
    func startWatching(source: SkillSource) {
        // 仅监控本地源
        guard source.typeRaw != SkillSource.SourceType.subscription.rawValue else { return }
        guard !source.localPathString.isEmpty else { return }
        
        // 先停止旧的监控
        stopWatching(sourceId: source.id)
        
        let baseUrl = URL(fileURLWithPath: source.localPathString)
        
        // 需要监控的目录列表
        let watchPaths = [
            baseUrl.appendingPathComponent(".agent/skills"),
            baseUrl.appendingPathComponent(".cursor/rules"),
            baseUrl.appendingPathComponent("skills")
        ]
        
        var activeSources: [DispatchSourceFileSystemObject] = []
        var activePaths: [String] = []
        
        for path in watchPaths {
            // 确保目录存在
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            
            // 创建文件描述符
            let fd = open(path.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            
            // 创建 DispatchSource
            let dispatchSource = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .extend],
                queue: queue
            )
            
            let sourceId = source.id
            
            dispatchSource.setEventHandler { [weak self] in
                print("[FileWatcher] Change detected in: \(path.path)")
                // 防抖：延迟 500ms 发送，避免频繁触发
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
    
    /// 停止监控指定源
    func stopWatching(sourceId: UUID) {
        if let info = watchers.removeValue(forKey: sourceId) {
            for source in info.sources {
                source.cancel()
            }
            print("[FileWatcher] Stopped watching source: \(sourceId)")
        }
    }
    
    /// 停止所有监控
    func stopAll() {
        for (id, _) in watchers {
            stopWatching(sourceId: id)
        }
    }
}
