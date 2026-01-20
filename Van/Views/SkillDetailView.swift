import SwiftUI

struct SkillDetailView: View {
    let skill: VanSkill
    @Environment(\.dismiss) private var dismiss
    
    @State private var content: String = ""
    @State private var isLoading = true
    @State private var isEditing = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView("加载中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    if isEditing {
                        TextEditor(text: $content)
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                    } else {
                        ScrollView {
                            Text(content)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                    }
                }
            }
            .navigationTitle(skill.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    if skill.isInstalled || !skill.isRemote {
                        // 本地文件可编辑
                        if isEditing {
                            Button("保存") { saveContent() }
                        } else {
                            Button("编辑") { isEditing = true }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .task { await loadContent() }
    }
    
    private func loadContent() async {
        isLoading = true
        defer { isLoading = false }
        
        // 优先本地路径
        if let localPath = skill.localPath, FileManager.default.fileExists(atPath: localPath.path) {
            do {
                content = try String(contentsOf: localPath, encoding: .utf8)
            } catch {
                errorMessage = "读取本地文件失败: \(error.localizedDescription)"
            }
            return
        }
        
        // 远程加载
        guard let remoteUrl = skill.remoteContentUrl else {
            errorMessage = "无可用内容地址"
            return
        }
        
        do {
            var request = URLRequest(url: remoteUrl)
            request.addValue("VanApp/1.0", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            content = String(data: data, encoding: .utf8) ?? "无法解码内容"
        } catch {
            errorMessage = "网络错误: \(error.localizedDescription)"
        }
    }
    
    private func saveContent() {
        guard let localPath = skill.localPath else { return }
        do {
            try content.write(to: localPath, atomically: true, encoding: .utf8)
            isEditing = false
        } catch {
            errorMessage = "保存失败: \(error.localizedDescription)"
        }
    }
}
