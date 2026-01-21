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
        
        // Splitting complex expressions to resolve compilation performance issues
        let predicate = #Predicate<VanSkill> { skill in
            skill.sourceId == sid
        }
        self._skills = Query(filter: predicate, sort: \VanSkill.name)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            contentSection
        }
        .searchable(text: $searchText, prompt: "Search \(source.name)...")
        .navigationTitle(source.name)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingEditSheet) {
             EditSourceView(source: source)
        }
        .confirmationDialog("Install to...", isPresented: $viewModel.showingInstallTargetPicker, titleVisibility: .visible) {
            installTargetButtons
        } message: {
            Text(viewModel.installPromptMessage)
        }
        .confirmationDialog("Confirm Uninstall", isPresented: $viewModel.showingUninstallConfirm, titleVisibility: .visible) {
            uninstallConfirmButtons
        } message: {
            Text(viewModel.deleteConfirmationMessage)
        }
        .alert("Install Failed", isPresented: $viewModel.showingInstallError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.installError ?? "Unknown Error")
        }
        .alert("Uninstall Failed", isPresented: $viewModel.showingUninstallError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.uninstallError ?? "Unknown Error")
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
             ContentUnavailableView { ProgressView() } description: { Text("Syncing...") }
        } else if isErrorState {
            ContentUnavailableView {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
            } description: { Text(source.statusRaw) } actions: {
                Button("Retry") { 
                    Task { await viewModel.sync(modelContext: modelContext) } 
                }
            }
        } else {
            if skills.isEmpty {
                ContentUnavailableView("No Skills", systemImage: "magnifyingglass", description: Text("Click the refresh button in the toolbar or right-click to sync."))
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
                Label("Sync", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isSyncing)
            .keyboardShortcut("r", modifiers: .command)
        }
        
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Edit Source...") { showingEditSheet = true }
                Button("Reveal in Finder") { revealInFinder() }
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
        Button("Cancel", role: .cancel) {}
    }

    @ViewBuilder
    private var uninstallConfirmButtons: some View {
        Button("Uninstall", role: .destructive) {
            Task { await viewModel.confirmUninstall(modelContext: modelContext) }
        }
        Button("Cancel", role: .cancel) {}
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
