//
//  SourceDetailViewModel.swift
//  Van
//
//  Created by Antigravity on 2026-01-20.
//

import SwiftUI
import SwiftData

@Observable
class SourceDetailViewModel {
    let source: SkillSource
    private let engine = FlowSyncEngine.shared
    
    // MARK: - UI State
    
    // Installation State
    var skillToInstall: VanSkill?
    var groupToInstall: [VanSkill]?
    var showingInstallTargetPicker = false
    
    var installError: String?
    var showingInstallError = false
    
    // Uninstallation State
    var skillToUninstall: VanSkill?
    var groupToUninstall: [VanSkill]?
    var showingUninstallConfirm = false
    
    var uninstallError: String?
    var showingUninstallError = false
    
    // General
    var isSyncing = false
    
    init(source: SkillSource) {
        self.source = source
    }
    
    // MARK: - Intentions
    
    func sync(modelContext: ModelContext) async {
        isSyncing = true
        await engine.sync(source: source, modelContext: modelContext)
        isSyncing = false
    }
    
    // MARK: Install Actions
    
    func requestInstall(_ skill: VanSkill) {
        self.skillToInstall = skill
        self.groupToInstall = nil
        self.showingInstallTargetPicker = true
    }
    
    func requestInstallGroup(_ group: [VanSkill]) {
        self.groupToInstall = group
        self.skillToInstall = nil
        self.showingInstallTargetPicker = true
    }
    
    func confirmInstall(to target: SkillSource, modelContext: ModelContext) async {
        do {
            if let group = groupToInstall {
                for skill in group {
                    try await engine.installSkill(skill, to: target, modelContext: modelContext)
                }
            } else if let skill = skillToInstall {
                try await engine.installSkill(skill, to: target, modelContext: modelContext)
            }
        } catch {
            await MainActor.run {
                self.installError = "安装失败: \(error.localizedDescription)"
                self.showingInstallError = true
            }
        }
    }
    
    // MARK: Uninstall Actions
    
    func requestUninstall(_ skill: VanSkill) {
        self.skillToUninstall = skill
        self.groupToUninstall = nil
        self.showingUninstallConfirm = true
    }
    
    func requestUninstallGroup(_ group: [VanSkill]) {
        self.groupToUninstall = group
        self.skillToUninstall = nil
        self.showingUninstallConfirm = true
    }
    
    func confirmUninstall(modelContext: ModelContext) async {
        if let group = groupToUninstall {
            for skill in group {
                await performUninstall(skill, modelContext: modelContext)
            }
        } else if let skill = skillToUninstall {
            await performUninstall(skill, modelContext: modelContext)
        }
    }
    
    private func performUninstall(_ skill: VanSkill, modelContext: ModelContext) async {
        // Ensure we are deleting from the current source context
        guard skill.sourceId == source.id else { return }
        
        guard let localPath = skill.localPath else {
            await MainActor.run {
                self.uninstallError = "删除失败: 文件路径不存在"
                self.showingUninstallError = true
            }
            return
        }
        
        do {
            // Delete file from disk
            try FileManager.default.removeItem(at: localPath)
            print("[Van] Deleted file: \(localPath.path)")
            
            // Sync to update database state
            await engine.sync(source: source, modelContext: modelContext)
            
        } catch {
            print("[Van] Uninstall failed: \(error)")
            await MainActor.run {
                self.uninstallError = "删除文件失败: \(error.localizedDescription)"
                self.showingUninstallError = true
            }
        }
    }
    
    // MARK: - Helpers
    
    var deleteConfirmationMessage: String {
        if let group = groupToUninstall {
            return "确定要删除该组下的 \(group.count) 个 Skill 吗？此操作将永久删除文件。"
        } else if let skill = skillToUninstall {
            return "确定要删除 '\(skill.name)' 吗？此操作将永久删除文件。"
        }
        return "确定要删除吗？"
    }
    
    var installPromptMessage: String {
        if let group = groupToInstall {
            return "将该组内的 \(group.count) 个 Skill 安装到哪里？"
        } else {
            return "选择要将 '\(skillToInstall?.name ?? "")' 安装到的位置"
        }
    }
}
