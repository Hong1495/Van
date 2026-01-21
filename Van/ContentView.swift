//
//  ContentView.swift
//  Van
//

import SwiftUI
import SwiftData
import Combine

enum SidebarItem: Hashable {
    case source(UUID)
}



struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SkillSource.name) private var sources: [SkillSource]
    @StateObject private var engine = FlowSyncEngine.shared
    @StateObject private var fileWatcher = FileWatcher.shared
    @ObservedObject private var settings = AppSettings.shared // 监听主题设置
    
    @State private var selection: SidebarItem?
    @State private var isShowingAddSource = false
    @State private var hasInitialized = false
    
    // 分类过滤
    private var projects: [SkillSource] { sources.filter { $0.typeRaw == SkillSource.SourceType.project.rawValue } }
    private var ides: [SkillSource] { sources.filter { $0.typeRaw == SkillSource.SourceType.ide.rawValue } }
    private var subscriptions: [SkillSource] { sources.filter { $0.typeRaw == SkillSource.SourceType.subscription.rawValue } }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                // 项目分类
                Section("项目") {
                    ForEach(projects) { source in
                        NavigationLink(value: SidebarItem.source(source.id)) {
                            Label {
                                Text(source.name)
                            } icon: {
                                SourceIconView(source: source, fallbackSystemImage: "folder")
                            }
                        }
                        .contextMenu {
                            Button("同步") {
                                Task { await engine.sync(source: source, modelContext: modelContext) }
                            }
                            Button("编辑源...") {
                                sourceToEdit = source
                            }
                            Divider()
                            Button("删除", role: .destructive) {
                                deleteSource(source)
                            }
                        }
                    }
                    .onDelete { offsets in delete(from: projects, at: offsets) }
                }
                
                // IDE 全局环境分类
                Section("开发环境") {
                    ForEach(ides) { source in
                        NavigationLink(value: SidebarItem.source(source.id)) {
                            Label {
                                Text(source.name)
                            } icon: {
                                SourceIconView(source: source, fallbackSystemImage: ideIcon(for: source.name))
                            }
                        }
                        .contextMenu {
                            Button("同步") {
                                Task { await engine.sync(source: source, modelContext: modelContext) }
                            }
                            Button("编辑源...") {
                                sourceToEdit = source
                            }
                            Divider()
                            Button("删除", role: .destructive) {
                                deleteSource(source)
                            }
                        }
                    }
                    .onDelete { offsets in delete(from: ides, at: offsets) }
                }
                
                // 订阅分类
                Section("订阅") {
                    ForEach(subscriptions) { source in
                        NavigationLink(value: SidebarItem.source(source.id)) {
                            Label {
                                Text(source.name)
                            } icon: {
                                SourceIconView(source: source, fallbackSystemImage: "antenna.radiowaves.left.and.right")
                            }
                        }
                        .contextMenu {
                            Button("同步") {
                                Task { await engine.sync(source: source, modelContext: modelContext) }
                            }
                            Button("编辑源...") {
                                sourceToEdit = source
                            }
                            Divider()
                            Button("删除", role: .destructive) {
                                deleteSource(source)
                            }
                        }
                    }
                    .onDelete { offsets in delete(from: subscriptions, at: offsets) }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Van Skill 库")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("添加项目...") { addProject() }
                        Divider()
                        Menu("添加开发环境(IDE)") {
                            Button("Antigravity") { addIDE(name: "Antigravity", path: "\(NSHomeDirectory())/.gemini") }
                            Button("Cursor") { addIDE(name: "Cursor", path: "\(NSHomeDirectory())/.cursor") }
                            Button("Claude") { addIDE(name: "Claude", path: "\(NSHomeDirectory())/.claude") }
                            Divider()
                            Button("自定义路径...") { addCustomIDE() }
                        }
                        Divider()
                        Button("添加订阅...") { isShowingAddSource = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingAddSource) {
                AddSourceView()
                    .environmentObject(settings)
            }
            .sheet(item: $sourceToEdit) { source in
                EditSourceView(source: source)
            }
        } detail: {
            if let selection = selection, case .source(let id) = selection, let source = sources.first(where: { $0.id == id }) {
                SourceDetailView(source: source)
            } else {
                ContentUnavailableView("选择 Skill 源", systemImage: "sidebar.left", description: Text("请从侧边栏选择项目、IDE 或订阅。"))
            }
        }
        .task {
            guard !hasInitialized else { return }
            hasInitialized = true
            for source in sources {
                // 仅自动同步从未同步过的源，避免每次启动重载
                if source.lastSynced == nil {
                    Task { await engine.sync(source: source, modelContext: modelContext) }
                }
                // 启动本地源的文件监控
                fileWatcher.startWatching(source: source)
            }
        }
        .onReceive(fileWatcher.changedSourcePublisher) { sourceId in
            // 文件变化时自动同步
            if let source = sources.first(where: { $0.id == sourceId }) {
                print("[ContentView] Auto-syncing due to file change: \(source.name)")
                Task { await engine.sync(source: source, modelContext: modelContext) }
            }
        }
        .onChange(of: sources.count) { _, _ in
            // 源列表变化时更新监控
            for source in sources {
                fileWatcher.startWatching(source: source)
            }
        }
        .preferredColorScheme(settings.theme.colorScheme)
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
        panel.message = "选择包含 .cursor/rules 或 .agent/skills 的项目目录"
        if panel.runModal() == .OK, let url = panel.url {
            let source = SkillSource(name: url.lastPathComponent, localPath: url.path, type: .project)
            modelContext.insert(source)
            selection = .source(source.id)
            Task { await engine.sync(source: source, modelContext: modelContext) }
        }
    }
    
    private func addIDE(name: String, path: String) {
        // 如果已存在则不重复添加
        guard !ides.contains(where: { $0.localPathString == path }) else { return }
        let source = SkillSource(name: name, localPath: path, type: .ide)
        modelContext.insert(source)
        selection = .source(source.id)
        Task { await engine.sync(source: source, modelContext: modelContext) }
    }
    
    private func addCustomIDE() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "选择 IDE 配置目录 (例如 ~/.cursor)"
        if panel.runModal() == .OK, let url = panel.url {
            addIDE(name: url.lastPathComponent, path: url.path)
        }
    }
    
    private func delete(from list: [SkillSource], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(list[index])
        }
    }
    
    private func deleteSource(_ source: SkillSource) {
        modelContext.delete(source)
    }
    
    // 新增状态以支持 EditSourceView Sheet
    @State private var sourceToEdit: SkillSource?
}



#Preview {
    ContentView()
        .modelContainer(for: [SkillSource.self, VanSkill.self], inMemory: true)
}
