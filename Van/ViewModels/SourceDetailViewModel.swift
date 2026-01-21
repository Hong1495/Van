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
                self.installError = "Install failed: \(error.localizedDescription)"
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
                self.uninstallError = "Uninstall failed: File path not found"
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
                self.uninstallError = "Failed to delete file: \(error.localizedDescription)"
                self.showingUninstallError = true
            }
        }
    }
    
    // MARK: - Helpers
    
    var deleteConfirmationMessage: String {
        if let group = groupToUninstall {
            return "Are you sure you want to delete these \(group.count) skills? This action will permanently remove the files."
        } else if let skill = skillToUninstall {
            return "Are you sure you want to delete '\(skill.name)'? This action will permanently remove the files."
        }
        return "Are you sure you want to delete?"
    }
    
    var installPromptMessage: String {
        if let group = groupToInstall {
            return "Where would you like to install these \(group.count) skills?"
        } else {
            return "Select a location to install '\(skillToInstall?.name ?? "")'"
        }
    }
}
