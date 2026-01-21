//
//  SkillRowView.swift
//  Van
//
//  Refactored by Antigravity on 2026-01-20.
//

import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Skill List Row
struct SkillRowView: View {
    @Bindable var skill: VanSkill
    let installedIn: [String] // 显示安装到的位置
    var onInstall: (() -> Void)? = nil
    var onUninstall: (() -> Void)? = nil
    
    // UI 状态
    @State private var contents: [SkillFileItem] = []
    @State private var isLoadingContents = false
    
    // 合并 Sheet 状态以防止冲突
    enum ActiveSheet: Identifiable {
        case editor
        case detail
        var id: Int { hashValue }
    }
    
    @State private var activeSheet: ActiveSheet?
    @State private var showDeleteConfirmation = false
    
    // Translation API State
    @State private var translatedDesc: String?
    #if canImport(Translation)
    @State private var translationConfig: TranslationSession.Configuration?
    #endif

    struct SkillFileItem: Identifiable {
        let id = UUID()
        let name: String
        let isDir: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // 图标
                Image(systemName: skill.remoteDirectoryApiUrlString.isEmpty ? ecosystemIcon(for: skill.ecosystem) : "folder.fill")
                    .font(.title2)
                    .foregroundStyle(skill.remoteDirectoryApiUrlString.isEmpty ? ecosystemColor(for: skill.ecosystem) : .blue)
                    .frame(width: 32, height: 32)
                
                // 内容区域：点击打开内置编辑器
                VStack(alignment: .leading, spacing: 4) {
                    Text(skill.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    // 列表页只显示原生描述
                    Text(skill.desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // 标签区域
                    HStack {
                        if !installedIn.isEmpty {
                            ForEach(installedIn, id: \.self) { sourceName in
                                Text(sourceName)
                                    .font(.system(size: 10))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.1))
                                    .foregroundStyle(.green)
                                    .cornerRadius(4)
                            }
                        }
                        Spacer()
                    }
                }
                .contentShape(Rectangle()) // 扩大点击区域
                .onTapGesture {
                    activeSheet = .editor
                }
                
                Spacer()
                
                // 操作按钮
                VStack {
                    if onInstall != nil && installedIn.isEmpty {
                        Button(action: { onInstall?() }) {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderless)
                        .help("安装此 Skill")
                    }
                    
                    if onUninstall != nil {
                        Button(action: { showDeleteConfirmation = true }) {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("卸载此 Skill")
                    }
                    
                    // 恢复显式的详情按钮
                    Button(action: { activeSheet = .detail }) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                    .help("查看详情与翻译")
                }
            }
            .padding(12)
            
            // 目录内容展示区域
            if !skill.remoteDirectoryApiUrlString.isEmpty || skill.isInstalled {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                        .padding(.vertical, 4)
                    
                    if isLoadingContents {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.vertical, 4)
                    } else if contents.isEmpty {
                        Text("无内容或正在同步")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 2)
                    } else {
                        // 简单的文件列表展示
                        FlowLayout(spacing: 8) {
                            ForEach(contents) { item in
                                HStack(spacing: 4) {
                                    Image(systemName: item.isDir ? "folder" : "doc")
                                        .font(.system(size: 10))
                                    Text(item.name)
                                        .font(.system(size: 10))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .task {
                    await loadSkillContents()
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        // 删除确认弹窗
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
            Button("删除", role: .destructive) {
                onUninstall?()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要删除 \(skill.name) 吗？此操作不可撤销。")
        }
        // 统一处理为大尺寸 Sheet，提供沉浸式编辑体验 (macOS 不支持 fullScreenCover)
        .sheet(item: $activeSheet) { item in
            switch item {
            case .editor:
                VanSkillEditorView(skill: skill)
                    .frame(minWidth: 1000, minHeight: 700) 
            case .detail:
                #if canImport(Translation)
                DetailSheetView(skill: skill,
                               translatedDesc: $translatedDesc,
                               translationConfig: $translationConfig,
                               fetchRemoteMetadata: fetchRemoteMetadata,
                               triggerTranslation: triggerTranslation)
                #else
                DetailSheetView(skill: skill,
                               translatedDesc: $translatedDesc,
                               fetchRemoteMetadata: fetchRemoteMetadata,
                               triggerTranslation: triggerTranslation)
                #endif
            }
        }
        
        #if canImport(Translation)
        .translationTask(translationConfig) { session in
            do {
                if !skill.desc.isEmpty {
                    let response = try await session.translate(skill.desc)
                    let result = response.targetText
                    await MainActor.run {
                        translatedDesc = result
                        skill.translatedDesc = result
                    }
                }
            } catch {
                print("Translation failed: \(error)")
            }
        }
        #endif
    }
    
    private func triggerTranslation() async {
        if #available(macOS 15.0, *) {
            #if canImport(Translation)
            // 仅当描述包含非中文且非空时才尝试翻译
            // 且仅当没有缓存翻译时
            if skill.translatedDesc == nil && !skill.desc.isEmpty && !skill.desc.hasPrefix("Remote Skill") {
                // 检查语言模型状态，避免频繁弹窗
                let source = Locale.Language(identifier: "en")
                let target = Locale.Language(identifier: "zh-Hans")
                let availability = LanguageAvailability()
                
                // 异步检查状态
                if await availability.status(from: source, to: target) == .installed {
                    translationConfig = .init(source: source, target: target)
                }
            }
            #endif
        }
    }
    
    // 复用 FlowSyncEngine 的提取逻辑（简化版）
    private func fetchRemoteMetadata() async {
        guard let url = skill.remoteContentUrl else { return }
        // 简单请求，依赖系统缓存
        var request = URLRequest(url: url)
        request.addValue("VanApp/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let content = String(data: data, encoding: .utf8) {
                let (desc, _) = extractMetadata(from: content)
                if !desc.isEmpty {
                    await MainActor.run {
                        skill.desc = desc
                    }
                    // 更新描述后触发翻译
                    await triggerTranslation()
                }
            }
        } catch {
            print("Failed to fetch metadata for \(skill.name)")
        }
    }
    
    private func extractMetadata(from content: String) -> (String, String) {
        var description = ""
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("description:") {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count > 1 {
                    description = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
            } else if line.contains("@description") {
                let parts = line.split(separator: " ", maxSplits: 1)
                if parts.count > 1 {
                    description = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            if !description.isEmpty { break }
        }
        return (description, "")
    }
    
    // 加载目录内容逻辑
    private func loadSkillContents() async {
        guard contents.isEmpty else { return }
        isLoadingContents = true
        defer { isLoadingContents = false }
        
        // 1. 如果是本地已安装的，读取本地目录
        if let localPath = skill.localPath, FileManager.default.fileExists(atPath: localPath.path) {
            let isDir = (try? localPath.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                let fileUrls = (try? FileManager.default.contentsOfDirectory(at: localPath, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
                self.contents = fileUrls.map { url in
                    let isSubDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    return SkillFileItem(name: url.lastPathComponent, isDir: isSubDir)
                }.sorted(by: { $0.isDir && !$1.isDir || ($0.name < $1.name) })
                return
            }
        }
        
        // 2. 如果是远程目录型 Skill
        if !skill.remoteDirectoryApiUrlString.isEmpty {
            do {
                let items = try await FlowSyncEngine.shared.fetchGithubItems(url: skill.remoteDirectoryApiUrlString)
                self.contents = items.compactMap { item in
                    guard let name = item["name"] as? String, let type = item["type"] as? String else { return nil }
                    return SkillFileItem(name: name, isDir: type == "dir")
                }.sorted(by: { $0.isDir && !$1.isDir || ($0.name < $1.name) })
            } catch {
                print("Failed to fetch remote contents: \(error)")
            }
        }
    }
}

// 简单的流式布局
struct FlowLayout: Layout {
    var spacing: CGFloat
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var width: CGFloat = 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity
        
        for size in sizes {
            if x + size.width > maxWidth {
                x = 0
                y += height + spacing
                height = 0
            }
            x += size.width + spacing
            height = max(height, size.height)
            width = max(width, x)
        }
        return CGSize(width: width, height: y + height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        
        for (index, size) in sizes.enumerated() {
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
