//
//  ContentView.swift
//  Van
//

import SwiftUI
import SwiftData
import Combine

enum AppTab: String, Hashable, CaseIterable {
    case skills = "Skills"
}

enum SidebarItem: Hashable {
    case source(UUID)
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SkillSource.name) private var sources: [SkillSource]
    @StateObject private var engine = FlowSyncEngine.shared
    @StateObject private var fileWatcher = FileWatcher.shared
    @ObservedObject private var settings = AppSettings.shared // Listen for theme changes
    
    @State private var activeTab: AppTab = .skills
    @State private var selection: SidebarItem?
    @State private var isShowingAddSource = false
    @State private var hasInitialized = false
    
    // Category filtering
    private var projects: [SkillSource] { sources.filter { $0.typeRaw == SkillSource.SourceType.project.rawValue } }
    private var ides: [SkillSource] { sources.filter { $0.typeRaw == SkillSource.SourceType.ide.rawValue } }
    private var subscriptions: [SkillSource] { sources.filter { $0.typeRaw == SkillSource.SourceType.subscription.rawValue } }
    
    var body: some View {
        NavigationSplitView {
            // Primary Column: Tab Switcher
            List(selection: $activeTab) {
                NavigationLink(value: AppTab.skills) {
                    Label("Skills", systemImage: "square.grid.2x2")
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Van")
        } content: {
            if activeTab == .skills {
                skillsSecondaryColumn
            } else {
                ContentUnavailableView("Other Section", systemImage: "app.badge")
            }
        } detail: {
            if activeTab == .skills {
                skillsDetailColumn
            } else {
                Text("Select an option")
            }
        }
        .sheet(isPresented: $isShowingAddSource) {
            AddSourceView()
                .environmentObject(settings)
        }
        .sheet(item: $sourceToEdit) { source in
            EditSourceView(source: source)
        }
        .task {
            guard !hasInitialized else { return }
            hasInitialized = true
            for source in sources {
                if source.lastSynced == nil {
                    Task { await engine.sync(source: source, modelContext: modelContext) }
                }
                fileWatcher.startWatching(source: source)
            }
            
            // Auto-select first source on launch if skills tab is active
            if activeTab == .skills && selection == nil {
                autoSelectFirstSource()
            }
        }
        .onChange(of: activeTab) { _, newValue in
            if newValue == .skills {
                autoSelectFirstSource()
            }
        }
        .onReceive(fileWatcher.changedSourcePublisher) { sourceId in
            if let source = sources.first(where: { $0.id == sourceId }) {
                Task { await engine.sync(source: source, modelContext: modelContext) }
            }
        }
        .onChange(of: sources.count) { _, _ in
            for source in sources {
                fileWatcher.startWatching(source: source)
            }
        }
        .preferredColorScheme(settings.theme.colorScheme)
    }
    
    @ViewBuilder
    private var skillsSecondaryColumn: some View {
        List(selection: $selection) {
            if !projects.isEmpty {
                Section("Projects") {
                    ForEach(projects) { source in
                        sourceRow(source)
                    }
                }
            }
            
            if !ides.isEmpty {
                Section("IDEs") {
                    ForEach(ides) { source in
                        sourceRow(source)
                    }
                }
            }
            
            if !subscriptions.isEmpty {
                Section("Subscriptions") {
                    ForEach(subscriptions) { source in
                        sourceRow(source)
                    }
                }
            }
            
            if sources.isEmpty {
                ContentUnavailableView("No Sources", systemImage: "folder.badge.plus")
            }
        }
        .navigationTitle("Skills")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add Project...") { addProject() }
                    Divider()
                    Menu("Add IDE Environment") {
                        Button("Antigravity") { addIDE(name: "Antigravity", path: "\(NSHomeDirectory())/.gemini") }
                        Button("Cursor") { addIDE(name: "Cursor", path: "\(NSHomeDirectory())/.cursor") }
                        Button("Claude") { addIDE(name: "Claude", path: "\(NSHomeDirectory())/.claude") }
                        Divider()
                        Button("Custom Path...") { addCustomIDE() }
                    }
                    Divider()
                    Button("Add Subscription...") { isShowingAddSource = true }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
    
    @ViewBuilder
    private var skillsDetailColumn: some View {
        if let selection = selection, case .source(let id) = selection, let source = sources.first(where: { $0.id == id }) {
            SourceDetailView(source: source)
        } else {
            ContentUnavailableView("Select Skill Source", systemImage: "sidebar.left", description: Text("Please select a Project, IDE, or Subscription from the sidebar."))
        }
    }
    
    private func autoSelectFirstSource() {
        // Priority: Projects > IDEs > Subscriptions
        if let first = projects.first ?? ides.first ?? subscriptions.first {
            selection = .source(first.id)
        }
    }
    
    // ... (ideIcon, addProject, addIDE, addCustomIDE omitted, keeping existing logic) ...
    private func ideIcon(for name: String) -> String {
        switch name.lowercased() {
        case "antigravity": return "wand.and.stars"
        case "cursor": return "cursorarrow.rays"
        case "claude": return "brain.head.profile"
        default: return "terminal"
        }
    }
    
    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "Select project directory containing .cursor/rules or .agent/skills"
        if panel.runModal() == .OK, let url = panel.url {
            let source = SkillSource(name: url.lastPathComponent, localPath: url.path, type: .project)
            modelContext.insert(source)
            selection = .source(source.id)
            Task { await engine.sync(source: source, modelContext: modelContext) }
        }
    }
    
    private func addIDE(name: String, path: String) {
        // ... (remaining addIDE logic keeps existing English/Logic)
        guard !sources.filter({ $0.typeRaw == SkillSource.SourceType.ide.rawValue }).contains(where: { $0.localPathString == path }) else { return }
        let source = SkillSource(name: name, localPath: path, type: .ide)
        modelContext.insert(source)
        selection = .source(source.id)
        Task { await engine.sync(source: source, modelContext: modelContext) }
    }
    
    private func addCustomIDE() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "Select IDE configuration directory (e.g., ~/.cursor)"
        if panel.runModal() == .OK, let url = panel.url {
            addIDE(name: url.lastPathComponent, path: url.path)
        }
    }
    
    private func deleteSource(_ source: SkillSource) {
        modelContext.delete(source)
    }
    
    @ViewBuilder
    private func sourceRow(_ source: SkillSource) -> some View {
        NavigationLink(value: SidebarItem.source(source.id)) {
            Label {
                Text(source.name)
            } icon: {
                let fallback = source.typeRaw == SkillSource.SourceType.subscription.rawValue ? "antenna.radiowaves.left.and.right" : "folder"
                SourceIconView(source: source, fallbackSystemImage: fallback)
            }
        }
        .contextMenu {
            Button("Sync") {
                Task { await engine.sync(source: source, modelContext: modelContext) }
            }
            Button("Edit Source...") {
                sourceToEdit = source
            }
            Divider()
            Button("Delete", role: .destructive) {
                deleteSource(source)
            }
        }
    }

    // State to support EditSourceView sheet
    @State private var sourceToEdit: SkillSource?
}



#Preview {
    ContentView()
        .modelContainer(for: [SkillSource.self, VanSkill.self], inMemory: true)
}
