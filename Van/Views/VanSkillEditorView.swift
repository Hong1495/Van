//
//  VanSkillEditorView.swift
//  Van
//
//  Created by Antigravity on 2026-01-20.
//

import SwiftUI

struct VanSkillEditorView: View {
    let skill: VanSkill
    @State private var content: String = ""
    @State private var originalContent: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    
    // 目录型 Skill 支持
    @State private var skillFiles: [URL] = []
    @State private var selectedFile: URL?
    @State private var showFileBrowser = false
    
    // 是否是本地文件且可编辑
    var isEditable: Bool {
        selectedFile != nil && selectedFile?.path.contains("/.agent/skills/") == true
    }
    
    var body: some View {
        NavigationSplitView {
            // 左侧文件列表（仅当是目录型 Skill 时显示）
            if showFileBrowser {
                List(skillFiles, id: \.self, selection: $selectedFile) { url in
                    HStack {
                        Image(systemName: url.hasDirectoryPath ? "folder" : "doc.text")
                            .foregroundStyle(url.hasDirectoryPath ? .blue : .secondary)
                        Text(url.lastPathComponent)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .tag(url)
                }
                .navigationTitle("文件清单")
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 150, ideal: 200, max: 300)
                #endif
            } else {
                Text("单文件模式")
                    .foregroundStyle(.secondary)
            }
        } detail: {
            VStack(spacing: 0) {
                // 工具栏
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(skill.name)
                            .font(.headline)
                        if let selected = selectedFile {
                            Text(selected.lastPathComponent)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if isEditable {
                        Text("(本地)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
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
                        .keyboardShortcut("s", modifiers: .command)
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
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .disabled(!isEditable)
                        .scrollContentBackground(.hidden)
                }
            }
        }
        .onChange(of: selectedFile) { oldFile, newFile in
            if let file = newFile, !file.hasDirectoryPath {
                Task { await readFile(url: file) }
            }
        }
        .task {
            await setupEditor()
        }
    }
    
    private func setupEditor() async {
        isLoading = true
        defer { isLoading = false }
        
        // 1. 检查是否是目录型 Skill
        if let directoryApiUrl = skill.directoryApiUrl {
            showFileBrowser = true
            
            // 如果已安装，读取本地目录
            if let localBase = skill.localPath?.deletingLastPathComponent() {
                do {
                    let files = try FileManager.default.contentsOfDirectory(at: localBase, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                    self.skillFiles = files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                    
                    if let skillMd = files.first(where: { $0.lastPathComponent.uppercased() == "SKILL.MD" }) {
                        selectedFile = skillMd
                        await readFile(url: skillMd)
                    } else if let first = files.first(where: { !$0.hasDirectoryPath }) {
                        selectedFile = first
                        await readFile(url: first)
                    }
                    return
                } catch {
                    print("Failed to list local directory: \(error)")
                }
            }
            
            // 如果未安装或本地读取失败，尝试读取远程列表
            do {
                let items = try await FlowSyncEngine.shared.fetchGithubItems(url: directoryApiUrl.absoluteString)
                // 转换为虚拟 URL 以便在 List 中显示
                self.skillFiles = items.compactMap { item -> URL? in
                    guard let _ = item["name"] as? String,
                          let downloadUrl = item["download_url"] as? String else { return nil }
                    return URL(string: downloadUrl) // 注意：这里我们将下载地址作为标识
                }
                
                if let skillMd = skillFiles.first(where: { $0.lastPathComponent.uppercased() == "SKILL.MD" || $0.lastPathComponent.uppercased() == "SKILL.MDC" }) {
                    selectedFile = skillMd
                    await readFile(url: skillMd)
                } else if let first = skillFiles.first(where: { !$0.hasDirectoryPath }) {
                    selectedFile = first
                    await readFile(url: first)
                }
            } catch {
                errorMessage = "无法获取远程文件列表: \(error.localizedDescription)"
            }
        } else {
            // 单文件模式
            showFileBrowser = false
            await loadSingleFile()
        }
    }
    
    private func loadSingleFile() async {
        if let localUrl = skill.localPath {
            selectedFile = localUrl
            await readFile(url: localUrl)
        } else if let remoteUrl = skill.remoteContentUrl {
            // 远程文件读取逻辑
            await readRemoteFile(url: remoteUrl)
        } else {
            errorMessage = "无有效内容"
        }
    }
    
    private func readFile(url: URL) async {
        if url.isFileURL {
            do {
                content = try String(contentsOf: url, encoding: .utf8)
                originalContent = content
                errorMessage = nil
            } catch {
                errorMessage = "无法读取文件: \(error.localizedDescription)"
            }
        } else {
            // 远程文件读取
            await readRemoteFile(url: url)
        }
    }
    
    private func readRemoteFile(url: URL) async {
        do {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
            let (data, _) = try await URLSession.shared.data(for: request)
            if let str = String(data: data, encoding: .utf8) {
                content = str
                originalContent = str
            } else {
                errorMessage = "无法解码远程内容"
            }
        } catch {
            errorMessage = "网络请求失败: \(error.localizedDescription)"
        }
    }
    
    private func saveContent() {
        guard let url = selectedFile else { return }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            originalContent = content
        } catch {
            errorMessage = "保存失败: \(error.localizedDescription)"
        }
    }
}
