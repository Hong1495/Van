import SwiftUI
#if canImport(Translation)
import Translation
#endif

struct SkillCardView: View {
    @Bindable var skill: VanSkill
    let installedIn: [String] // 显示安装到的位置
    var onInstall: (() -> Void)? = nil
    var onUninstall: (() -> Void)? = nil
    
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
    @State private var translationConfig: TranslationSession.Configuration?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 图标
            Image(systemName: ecosystemIcon(for: skill.ecosystem))
                .font(.title2)
                .foregroundStyle(ecosystemColor(for: skill.ecosystem))
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
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        // 删除确认弹窗
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
            Button("删除", role: .destructive) {
                onUninstall?()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要删除 \(skill.name) 吗？此操作不可撤销。")
        }
        // 统一处理 Sheet
        .sheet(item: $activeSheet) { item in
            switch item {
            case .editor:
                VanSkillEditorView(skill: skill)
            case .detail:
                DetailSheetView(skill: skill,
                              translatedDesc: $translatedDesc,
                              translationConfig: $translationConfig,
                              fetchRemoteMetadata: fetchRemoteMetadata,
                              triggerTranslation: triggerTranslation)
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
    
    // 移除 openDocument 方法，因为被 sheet 替代了
    
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
    
    // 复用 FlowSyncEngine 的提取逻辑（简化版）
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
    
    // ... methods ...
}

// Helpers moved to file scope
private func ecosystemIcon(for eco: SkillEcosystem) -> String {
    switch eco {
    case .openSkills: return "shippingbox"
    case .cursor: return "cursorarrow"
    case .aider: return "terminal"
    case .custom: return "pencil"
    }
}

private func ecosystemColor(for eco: SkillEcosystem) -> Color {
    switch eco {
    case .openSkills: return .orange
    case .cursor: return .blue
    case .aider: return .green
    case .custom: return .purple
    }
}

struct DetailSheetView: View {
    let skill: VanSkill
    @Binding var translatedDesc: String?
    @Binding var translationConfig: TranslationSession.Configuration?
    let fetchRemoteMetadata: () async -> Void
    let triggerTranslation: () async -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
             HStack {
                 Image(systemName: ecosystemIcon(for: skill.ecosystem))
                     .font(.title)
                     .foregroundStyle(ecosystemColor(for: skill.ecosystem))
                 Text(skill.name).font(.title)
                 
                 Spacer()
                 
                 Button { dismiss() } label: {
                     Image(systemName: "xmark.circle.fill")
                         .font(.title2)
                         .foregroundStyle(.secondary)
                 }
                 .buttonStyle(.plain)
             }
             
             ScrollView {
                 // 详情页优先显示翻译结果，如果没有系统翻译，则显示原文
                 Text(skill.translatedDesc ?? skill.desc)
                     .font(.title3)
                     .lineSpacing(6)
                     .textSelection(.enabled)
                 
                 if skill.translatedDesc != nil {
                     Divider()
                     Text("原文：")
                         .font(.caption)
                         .foregroundStyle(.secondary)
                     Text(skill.desc)
                         .font(.body)
                         .foregroundStyle(.secondary)
                         .textSelection(.enabled)
                 }
             }
             
             Spacer()
         }
         .padding(30)
         .frame(width: 500, height: 400)
         .task {
             // 打开详情页时触发抓取和翻译
             if skill.isRemote && (skill.desc == "Remote Skill" || skill.desc.isEmpty) {
                 await fetchRemoteMetadata()
             }
             if skill.translatedDesc == nil {
                 await triggerTranslation()
             }
         }
    }
}
    



// 别名，确保兼容旧引用
typealias SkillRowView = SkillCardView

struct VanSkillEditorView: View {
    let skill: VanSkill
    @State private var content: String = ""
    @State private var originalContent: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    
    // 是否是本地文件且可编辑
    var isEditable: Bool {
        skill.localPath != nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Text(skill.name)
                    .font(.headline)
                
                if isEditable {
                    Text("(本地)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("(远程只读)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if isEditable {
                    Button("保存") {
                        saveContent()
                    }
                    .disabled(content == originalContent)
                }
                
                Button("关闭") {
                    dismiss()
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView("无法加载内容", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                // 编辑器区域
                TextEditor(text: $content)
                    .font(.monospaced(.body)())
                    .padding(8)
                    // 如果不可编辑，禁用输入（但允许复制）
                    .disabled(!isEditable)
                    .scrollContentBackground(.hidden) // 适配暗色模式
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .task {
            await loadContent()
        }
    }
    
    private func loadContent() async {
        isLoading = true
        defer { isLoading = false }
        
        // 1. 尝试读取本地文件
        if let localUrl = skill.localPath {
            do {
                content = try String(contentsOf: localUrl, encoding: .utf8)
                originalContent = content
            } catch {
                errorMessage = "无法读取本地文件: \(error.localizedDescription)"
            }
            return
        }
        
        // 2. 尝试读取远程内容
        if let remoteUrl = skill.remoteContentUrl {
            do {
                let (data, _) = try await URLSession.shared.data(from: remoteUrl)
                if let str = String(data: data, encoding: .utf8) {
                    content = str
                    originalContent = str // 远程内容不可编辑，但仍记录
                } else {
                    errorMessage = "无法解码远程内容"
                }
            } catch {
                errorMessage = "网络请求失败: \(error.localizedDescription)"
            }
            return
        }
        
        errorMessage = "无有效的内容路径"
    }
    
    private func saveContent() {
        guard let localUrl = skill.localPath else { return }
        
        do {
            try content.write(to: localUrl, atomically: true, encoding: .utf8)
            originalContent = content // 更新原始值，禁用保存按钮
        } catch {
            errorMessage = "保存失败: \(error.localizedDescription)"
        }
    }
}
