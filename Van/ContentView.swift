//
//  ContentView.swift
//  Van
//

import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case source(UUID)
}

struct SourceIconView: View {
    let source: SkillSource
    let fallbackSystemImage: String
    
    @State private var iconImage: Image?
    
    var body: some View {
        Group {
            if let iconImage {
                iconImage
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: fallbackSystemImage)
                    .frame(width: 16, height: 16)
            }
        }
        .task { await fetchIcon() }
    }
    
    private func fetchIcon() async {
        // 本地源：获取文件图标
        if source.typeRaw != SkillSource.SourceType.subscription.rawValue {
            let path = source.localPathString
            if !path.isEmpty {
                let nsImage = NSWorkspace.shared.icon(forFile: path)
                self.iconImage = Image(nsImage: nsImage)
            }
            return
        }
        
        // 远程源：尝试解析 GitHub Avatar
        // 假设 URL 格式为 https://github.com/owner/repo
        if let url = URL(string: source.urlString),
           url.host() == "github.com" {
            let components = url.pathComponents
            if components.count >= 2 {
                let owner = components[1]
                let avatarUrl = URL(string: "https://github.com/\(owner).png?size=64")!
                
                // 简单缓存策略：使用 URLCache
                let request = URLRequest(url: avatarUrl, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10)
                
                if let (data, _) = try? await URLSession.shared.data(for: request),
                   let nsImage = NSImage(data: data) {
                    await MainActor.run {
                        self.iconImage = Image(nsImage: nsImage)
                    }
                }
            }
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SkillSource.name) private var sources: [SkillSource]
    @StateObject private var engine = FlowSyncEngine.shared
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

struct SourceDetailView: View {
    let source: SkillSource
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SkillSource.name) private var allSources: [SkillSource]
    @StateObject private var engine = FlowSyncEngine.shared
    
    @State private var skillToInstall: VanSkill?
    @State private var groupToInstall: [VanSkill]? // 批量安装状态
    @State private var showingInstallTargetPicker = false
    @State private var installError: String?
    @State private var showingErrorAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            if source.statusRaw == "syncing" {
                ContentUnavailableView { ProgressView() } description: { Text("正在同步...") }
            } else if source.statusRaw.starts(with: "Error") || source.statusRaw.starts(with: "Sync Error") {
                ContentUnavailableView {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
                } description: { Text(source.statusRaw) } actions: {
                    Button("重试") { Task { await engine.sync(source: source, modelContext: modelContext) } }
                }
            } else {
                let skills = engine.gallerySkills.filter { $0.sourceId == source.id }
                if skills.isEmpty {
                    ContentUnavailableView("无 Skill", systemImage: "magnifyingglass", description: Text("在侧边栏右键点击该源并选择“同步”来刷新。"))
                } else {
                    SkillGroupListView(
                        source: source,
                        skills: skills,
                        allSources: allSources,
                        engine: engine,
                        onInstallRequest: { skill in
                            skillToInstall = skill
                            groupToInstall = nil
                            showingInstallTargetPicker = true
                        },
                        onUninstallRequest: { skill in
                            uninstall(skill)
                        },
                        onInstallGroupRequest: { group in
                            groupToInstall = group
                            skillToInstall = nil
                            showingInstallTargetPicker = true
                        }
                    )
                }
            }
        }
        .onAppear {
            if source.lastSynced == nil {
                Task { await engine.sync(source: source, modelContext: modelContext) }
            }
        }
        .confirmationDialog("安装到...", isPresented: $showingInstallTargetPicker, titleVisibility: .visible) {
            let targets = allSources.filter { $0.typeRaw == SkillSource.SourceType.project.rawValue || $0.typeRaw == SkillSource.SourceType.ide.rawValue }
            ForEach(targets) { target in
                Button(target.name) {
                    Task {
                        // 批量安装或单体安装
                        if let group = groupToInstall {
                            for skill in group {
                                await install(skill, to: target)
                            }
                        } else if let skill = skillToInstall {
                            await install(skill, to: target)
                        }
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let group = groupToInstall {
                Text("将该组内的 \(group.count) 个 Skill 安装到哪里？")
            } else {
                Text("选择要将 '\(skillToInstall?.name ?? "")' 安装到的位置")
            }
        }
        .alert("安装失败", isPresented: $showingErrorAlert, actions: {
            Button("确定", role: .cancel) {}
        }, message: {
            Text(installError ?? "未知错误")
        })
    }
    
    private func install(_ skill: VanSkill?, to target: SkillSource) async {
        guard let skill = skill else { return }
        do {
            try await engine.installSkill(skill, to: target, modelContext: modelContext)
        } catch {
            installError = "无法安装到 \(target.name): \(error.localizedDescription)"
            showingErrorAlert = true
        }
    }
    
    private func uninstall(_ skill: VanSkill) {
        // 直接使用当前的 source (SourceDetailView 持有的)
        // 只有当 skill 属于当前 source 时才处理 (通常是的)
        if skill.sourceId == source.id {
             if let localPath = skill.localPath {
                 Task {
                     do {
                         try FileManager.default.removeItem(at: localPath)
                         print("[Van Uninstall] Deleted: \(localPath.path)")
                         await engine.sync(source: source, modelContext: modelContext)
                     } catch {
                         print("[Van Uninstall] Delete failed: \(error)")
                         // 这里可以增加弹窗提示，暂时先打印日志
                     }
                 }
             } else {
                 print("[Van Uninstall] Error: localPath is nil")
             }
        } else {
             // 如果在 All Skills 视图 (目前没有)，则需要查找 source
             // 但当前 UI 结构是 SourceDetailView，所以 source 是明确的
             print("[Van Uninstall] Context mismatch: skill source \(skill.sourceId ?? UUID()) != current \(source.id)")
        }
    }
}

struct EditSourceView: View {
    let source: SkillSource
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var engine = FlowSyncEngine.shared
    
    @State private var name: String
    @State private var url: String
    @State private var path: String
    
    init(source: SkillSource) {
        self.source = source
        _name = State(initialValue: source.name)
        _url = State(initialValue: source.urlString)
        _path = State(initialValue: source.localPathString)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("信息") {
                    TextField("名称", text: $name)
                    if source.typeRaw == SkillSource.SourceType.subscription.rawValue {
                        TextField("GitHub 地址", text: $url)
                    } else {
                        HStack {
                            TextField("本地路径", text: $path)
                            Button("选择...") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                if panel.runModal() == .OK { path = panel.url?.path ?? path }
                            }
                        }
                    }
                }
            }
            .navigationTitle("编辑源")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        source.name = name
                        source.urlString = url
                        source.localPathString = path
                        Task { await engine.sync(source: source, modelContext: modelContext) }
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 400, height: 300)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [SkillSource.self, VanSkill.self], inMemory: true)
}
