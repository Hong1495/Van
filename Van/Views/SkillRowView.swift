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
    let installedIn: [String] // Display installation locations
    var onInstall: (() -> Void)? = nil
    var onUninstall: (() -> Void)? = nil
    
    // UI Status
    @State private var contents: [SkillFileItem] = []
    @State private var isLoadingContents = false
    
    // Sheet Status
    enum ActiveSheet: Identifiable {
        case editor
        case detail
        var id: Int { hashValue }
    }
    
    @State private var activeSheet: ActiveSheet?
    @State private var showDeleteConfirmation = false

    struct SkillFileItem: Identifiable {
        let id = UUID()
        let name: String
        let isDir: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Icon
                Image(systemName: skill.remoteDirectoryApiUrlString.isEmpty ? ecosystemIcon(for: skill.ecosystem) : "folder.fill")
                    .font(.title2)
                    .foregroundStyle(skill.remoteDirectoryApiUrlString.isEmpty ? ecosystemColor(for: skill.ecosystem) : .blue)
                    .frame(width: 32, height: 32)
                
                // Content Area: Click to open editor
                VStack(alignment: .leading, spacing: 4) {
                    Text(skill.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text(skill.desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Tags
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
                .contentShape(Rectangle())
                .onTapGesture {
                    activeSheet = .editor
                }
                
                Spacer()
                
                // Actions
                VStack {
                    if onInstall != nil && installedIn.isEmpty {
                        Button(action: { onInstall?() }) {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderless)
                        .help("Install this Skill")
                    }
                    
                    if onUninstall != nil {
                        Button(action: { showDeleteConfirmation = true }) {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Uninstall this Skill")
                    }
                    
                    Button(action: { activeSheet = .detail }) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                    .help("View Details")
                }
            }
            .padding(12)
            
            // Directory Contents Preview
            if skill.isDirectory {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                        .padding(.vertical, 4)
                    
                    if isLoadingContents {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.vertical, 4)
                    } else if contents.isEmpty {
                        Text("No contents")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 2)
                    } else {
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
        .alert("Confirm Uninstall", isPresented: $showDeleteConfirmation) {
            Button("Uninstall", role: .destructive) {
                onUninstall?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove \(skill.name)? This action cannot be undone.")
        }
        .sheet(item: $activeSheet) { item in
            switch item {
            case .editor:
                VanSkillEditorView(skill: skill)
                    .frame(minWidth: 1000, minHeight: 700) 
            case .detail:
                DetailSheetView(skill: skill,
                                fetchRemoteMetadata: fetchRemoteMetadata)
            }
        }
    }
    
    private func fetchRemoteMetadata() async {
        guard let url = skill.remoteContentUrl else { return }
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
    
    // Logic to load directory contents
    private func loadSkillContents() async {
        guard skill.isDirectory, contents.isEmpty else { return }
        isLoadingContents = true
        defer { isLoadingContents = false }
        
        // 1. If installed locally, read local directory
        if let localPath = skill.localPath, FileManager.default.fileExists(atPath: localPath.path) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: localPath.path, isDirectory: &isDir), isDir.boolValue {
                let fileUrls = (try? FileManager.default.contentsOfDirectory(at: localPath, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
                self.contents = fileUrls.map { url in
                    let isSubDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    return SkillFileItem(name: url.lastPathComponent, isDir: isSubDir)
                }.sorted(by: { $0.isDir && !$1.isDir || ($0.name < $1.name) })
                return
            }
        }
        
        // 2. If it's a remote directory-based Skill
        if let apiUrl = skill.directoryApiUrl {
            do {
                let items = try await FlowSyncEngine.shared.fetchGithubItems(url: apiUrl.absoluteString)
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

// Simple flow layout
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
