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
    
    // Directory-based Skill support
    @State private var skillFiles: [URL] = []
    @State private var selectedFile: URL?
    @State private var showFileBrowser = false
    
    // Whether the file is local and editable
    var isEditable: Bool {
        selectedFile != nil && selectedFile?.path.contains("/.agent/skills/") == true
    }
    
    var body: some View {
        NavigationSplitView {
            // Left File List (Only for directory-based Skills)
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
                .navigationTitle("Files")
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 150, ideal: 200, max: 300)
                #endif
            } else {
                Text("Single File Mode")
                    .foregroundStyle(.secondary)
            }
        } detail: {
            VStack(spacing: 0) {
                // Toolbar
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
                        Text("(Local)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                    } else {
                        Text("(Remote Read-only)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if isEditable {
                        Button("Save") {
                            saveContent()
                        }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(content == originalContent)
                    }
                    
                    Button("Close") {
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
                    ContentUnavailableView("Unable to load content", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    // Editor Area
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
        
        // 1. Check if it's a directory-based Skill
        if skill.isDirectory {
            showFileBrowser = true
            
            // If installed, read local directory
            if let localPath = skill.localPath {
                do {
                    let files = try FileManager.default.contentsOfDirectory(at: localPath, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                    self.skillFiles = files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                    
                    if let skillMd = files.first(where: { $0.lastPathComponent.uppercased() == "SKILL.MD" || $0.lastPathComponent.uppercased() == "SKILL.MDC" }) {
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
            
            // If not installed or local read failed, try remote listing
            if let directoryApiUrl = skill.directoryApiUrl {
                do {
                    let items = try await FlowSyncEngine.shared.fetchGithubItems(url: directoryApiUrl.absoluteString)
                    // Convert to virtual URLs for list display
                    self.skillFiles = items.compactMap { item -> URL? in
                        guard let _ = item["name"] as? String,
                              let downloadUrl = item["download_url"] as? String else { return nil }
                        return URL(string: downloadUrl)
                    }
                    
                    if let skillMd = skillFiles.first(where: { $0.lastPathComponent.uppercased() == "SKILL.MD" || $0.lastPathComponent.uppercased() == "SKILL.MDC" }) {
                        selectedFile = skillMd
                        await readFile(url: skillMd)
                    } else if let first = skillFiles.first(where: { !$0.hasDirectoryPath }) {
                        selectedFile = first
                        await readFile(url: first)
                    }
                } catch {
                    errorMessage = "Failed to fetch remote file list: \(error.localizedDescription)"
                }
            }
        } else {
            // Single file mode
            showFileBrowser = false
            await loadSingleFile()
        }
    }
    
    private func loadSingleFile() async {
        if let localUrl = skill.localPath {
            selectedFile = localUrl
            await readFile(url: localUrl)
        } else if let remoteUrl = skill.remoteContentUrl {
            // Remote file read logic
            await readRemoteFile(url: remoteUrl)
        } else {
            errorMessage = "No valid content"
        }
    }
    
    private func readFile(url: URL) async {
        if url.isFileURL {
            do {
                content = try String(contentsOf: url, encoding: .utf8)
                originalContent = content
                errorMessage = nil
            } catch {
                errorMessage = "Failed to read file: \(error.localizedDescription)"
            }
        } else {
            // Remote file read
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
                errorMessage = "Failed to decode remote content"
            }
        } catch {
            errorMessage = "Network request failed: \(error.localizedDescription)"
        }
    }
    
    private func saveContent() {
        guard let url = selectedFile else { return }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            originalContent = content
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}
