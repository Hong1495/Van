//
//  SourceDetailView.swift
//  Van
//
//  Created by Antigravity on 2026-01-20.
//

import SwiftUI
import SwiftData

struct SourceDetailView: View {
    let source: SkillSource
    @State private var viewModel: SourceDetailViewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SkillSource.name) private var allSources: [SkillSource]
    
    // Skills Query needs to filter by source.id
    @Query private var skills: [VanSkill]
    
    @State private var showingEditSheet = false
    @State private var searchText = ""
    
    @StateObject private var engine = FlowSyncEngine.shared
    
    init(source: SkillSource) {
        self.source = source
        let sid = source.id
        self._viewModel = State(initialValue: SourceDetailViewModel(source: source))
        
        // 拆分复杂表达式以解决编译性能问题
        let predicate = #Predicate<VanSkill> { skill in
            skill.sourceId == sid
        }
        self._skills = Query(filter: predicate, sort: \VanSkill.name)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            contentSection
        }
        .searchable(text: $searchText, prompt: "搜索 \(source.name)...")
        .navigationTitle(source.name)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingEditSheet) {
             EditSourceView(source: source)
        }
        .confirmationDialog("安装到...", isPresented: $viewModel.showingInstallTargetPicker, titleVisibility: .visible) {
            installTargetButtons
        } message: {
            Text(viewModel.installPromptMessage)
        }
        .confirmationDialog("确认删除", isPresented: $viewModel.showingUninstallConfirm, titleVisibility: .visible) {
            uninstallConfirmButtons
        } message: {
            Text(viewModel.deleteConfirmationMessage)
        }
        .alert("安装失败", isPresented: $viewModel.showingInstallError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(viewModel.installError ?? "未知错误")
        }
        .alert("删除失败", isPresented: $viewModel.showingUninstallError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(viewModel.uninstallError ?? "未知错误")
        }
        .task {
            // Initial sync check
            if skills.isEmpty || source.statusRaw == "syncing" {
               await viewModel.sync(modelContext: modelContext)
            }
        }
    }
    
    @ViewBuilder
    private var contentSection: some View {
        if isLoadingState {
             ContentUnavailableView { ProgressView() } description: { Text("正在同步...") }
        } else if isErrorState {
            ContentUnavailableView {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
            } description: { Text(source.statusRaw) } actions: {
                Button("重试") { 
                    Task { await viewModel.sync(modelContext: modelContext) } 
                }
            }
        } else {
            if skills.isEmpty {
                ContentUnavailableView("无 Skill", systemImage: "magnifyingglass", description: Text("点击工具栏刷新按钮或右键同步。"))
            } else {
                SkillGroupListView(
                    source: source,
                    skills: skills,
                    allSources: allSources,
                    engine: engine,
                    onInstallRequest: { viewModel.requestInstall($0) },
                    onUninstallRequest: { viewModel.requestUninstall($0) },
                    onInstallGroupRequest: { viewModel.requestInstallGroup($0) },
                    onUninstallGroupRequest: { viewModel.requestUninstallGroup($0) },
                    searchText: $searchText
                )
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { 
                    await viewModel.sync(modelContext: modelContext)
                    await engine.sync(source: source, modelContext: modelContext)
                }
            } label: {
                Label("同步", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isSyncing)
            .keyboardShortcut("r", modifiers: .command)
        }
        
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("编辑源...") { showingEditSheet = true }
                Button("在 Finder 中显示") { revealInFinder() }
                    .disabled(source.localPathString.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private var installTargetButtons: some View {
        let targets = allSources.filter { 
            $0.typeRaw == SkillSource.SourceType.project.rawValue || 
            $0.typeRaw == SkillSource.SourceType.ide.rawValue 
        }
        ForEach(targets) { target in
            Button(target.name) {
                Task { await viewModel.confirmInstall(to: target, modelContext: modelContext) }
            }
        }
        Button("取消", role: .cancel) {}
    }

    @ViewBuilder
    private var uninstallConfirmButtons: some View {
        Button("删除", role: .destructive) {
            Task { await viewModel.confirmUninstall(modelContext: modelContext) }
        }
        Button("取消", role: .cancel) {}
    }
    
    var isLoadingState: Bool {
        source.statusRaw == "syncing" || viewModel.isSyncing
    }
    
    var isErrorState: Bool {
        source.statusRaw.starts(with: "Error") || source.statusRaw.starts(with: "Sync Error")
    }
    
    private func revealInFinder() {
        if !source.localPathString.isEmpty {
             NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: source.localPathString)
        }
    }
}
