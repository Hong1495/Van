import SwiftUI
#if canImport(Translation)
import Translation
#endif

struct SkillCardView: View {
    @Bindable var skill: VanSkill
    let installedIn: [String] // 显示安装到的位置
    var onInstall: (() -> Void)? = nil
    var onUninstall: (() -> Void)? = nil
    
    @State private var showingLargeDetail = false
    @State private var translatedDesc: String?
    
    // Translation API State
    @State private var translationConfig: TranslationSession.Configuration?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 头部
            HStack(alignment: .top) {
                Image(systemName: ecosystemIcon(for: skill.ecosystem))
                    .font(.title2)
                    .foregroundStyle(ecosystemColor(for: skill.ecosystem))
                    .frame(width: 32, height: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(skill.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    // 显示描述：优先显示翻译后的，否则显示原文
                    Text(translatedDesc ?? simpleTranslate(skill.desc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                // 操作按钮
                if skill.isRemote && !skill.isInstalled {
                    Button(action: { onInstall?() }) {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("安装此 Skill")
                } else if skill.isInstalled {
                    Button(action: { onUninstall?() }) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("卸载")
                }
                
                // 详情按钮
                Button(action: { showingLargeDetail = true }) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("查看中文简介")
            }
            
            Spacer(minLength: 0)
            
            // 安装位置标签
            if !installedIn.isEmpty {
                HStack(spacing: 4) {
                    ForEach(installedIn, id: \.self) { location in
                        Text(location)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(12)
        .frame(height: 110, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .contentShape(Rectangle())
        .onTapGesture { showingLargeDetail = true } // 点击卡片任意位置查看详情
        .sheet(isPresented: $showingLargeDetail) {
             VStack(alignment: .leading, spacing: 20) {
                 HStack {
                     Image(systemName: ecosystemIcon(for: skill.ecosystem))
                         .font(.largeTitle)
                         .foregroundStyle(ecosystemColor(for: skill.ecosystem))
                     Text(skill.name)
                         .font(.largeTitle.bold())
                     Spacer()
                     Button { showingLargeDetail = false } label: {
                         Image(systemName: "xmark.circle.fill")
                             .font(.title2)
                             .foregroundStyle(.secondary)
                     }
                     .buttonStyle(.plain)
                 }
                 
                 ScrollView {
                     Text(translatedDesc ?? simpleTranslate(skill.desc))
                         .font(.title3) // 大字展示
                         .lineSpacing(6)
                         .textSelection(.enabled)
                 }
                 
                 Spacer()
             }
             .padding(30)
             .frame(width: 500, height: 400)
        }
        .task {
            // 1. 如果是远程 Skill 且描述是默认值，尝试抓取真实描述
            if skill.isRemote && (skill.desc == "Remote Skill" || skill.desc.isEmpty) {
                await fetchRemoteMetadata()
            }
            // 2. 触发翻译 (需等待检查)
            await triggerTranslation()
        }
        #if canImport(Translation)
        .translationTask(translationConfig) { session in
            do {
                if !skill.desc.isEmpty {
                    let response = try await session.translate(skill.desc)
                    translatedDesc = response.targetText
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
            if !skill.desc.isEmpty && !skill.desc.hasPrefix("Remote Skill") {
                // 检查语言模型状态，避免频繁弹窗
                let source = Locale.Language(identifier: "en")
                let target = Locale.Language(identifier: "zh-Hans")
                let availability = LanguageAvailability()
                
                let status = await availability.status(from: source, to: target)
                
                if status == .installed {
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
                    description = parts[1].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
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
    
    private func simpleTranslate(_ desc: String) -> String {
        // 兜底翻译
        let translations: [String: String] = [
            "Remote Skill": "远程技能",
            "Remote rule from": "来自订阅",
            "Local": "本地技能",
            "From": "来自"
        ]
        var result = desc
        for (en, zh) in translations {
            result = result.replacingOccurrences(of: en, with: zh)
        }
        return result
    }
}

// 别名，确保兼容旧引用
typealias SkillRowView = SkillCardView
