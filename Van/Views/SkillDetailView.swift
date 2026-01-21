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
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    ContentUnavailableView("Load Failed", systemImage: "exclamationmark.triangle", description: Text(error))
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
                    Button("Close") { dismiss() }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    if skill.isInstalled || !skill.isRemote {
                        // Local file is editable
                        if isEditing {
                            Button("Save") { saveContent() }
                        } else {
                            Button("Edit") { isEditing = true }
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
        
        // Prefer local path
        if let localPath = skill.localPath, FileManager.default.fileExists(atPath: localPath.path) {
            do {
                content = try String(contentsOf: localPath, encoding: .utf8)
            } catch {
                errorMessage = "Failed to read local file: \(error.localizedDescription)"
            }
            return
        }
        
        // Remote load
        guard let remoteUrl = skill.remoteContentUrl else {
            errorMessage = "No content URL available"
            return
        }
        
        do {
            var request = URLRequest(url: remoteUrl)
            request.addValue("VanApp/1.0", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            content = String(data: data, encoding: .utf8) ?? "Unable to decode content"
        } catch {
            errorMessage = "Network error: \(error.localizedDescription)"
        }
    }
    
    private func saveContent() {
        guard let localPath = skill.localPath else { return }
        do {
            try content.write(to: localPath, atomically: true, encoding: .utf8)
            isEditing = false
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}
