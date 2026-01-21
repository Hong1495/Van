import Foundation
import Combine
import SwiftData

@MainActor
class FlowSyncEngine: ObservableObject {
    @Published var isSyncing = false // loading indicator
    static let shared = FlowSyncEngine()
    
    private var syncInProgress = Set<UUID>()
    
    // Serial queue to prevent excessive concurrency
    private let syncQueue = DispatchQueue(label: "com.van.sync", qos: .userInitiated)
    
    /// Unified sync entry point: handles both network and local sources
    func sync(source: SkillSource, modelContext: ModelContext) async {
        print("[Van Sync] ========== SYNC CALLED ==========")
        print("[Van Sync] Source: \(source.name)")
        print("[Van Sync] Type: \(source.typeRaw)")
        print("[Van Sync] ID: \(source.id)")
        
        guard !syncInProgress.contains(source.id) else {
            print("[Van Sync] [SKIP] Sync already in progress for \(source.name)")
            return
        }
        syncInProgress.insert(source.id)
        defer { syncInProgress.remove(source.id) }
        
        print("[Van Sync] Setting status to 'syncing'")
        await MainActor.run { source.statusRaw = "syncing" }
        print("[Van Sync] [BEGIN] \(source.name)")
        
        switch source.typeRaw {
        case SkillSource.SourceType.subscription.rawValue:
            print("[Van Sync] Calling syncGithub")
            await syncGithub(source: source, modelContext: modelContext)
        case SkillSource.SourceType.project.rawValue, SkillSource.SourceType.ide.rawValue:
            print("[Van Sync] Calling syncLocalProject")
            await syncLocalProject(source: source, modelContext: modelContext)
        default:
            print("[Van Sync] [SKIP] Unknown type: \(source.typeRaw)")
            break
        }
        
        print("[Van Sync] ========== SYNC COMPLETE ==========")
    }

    
    private func syncGithub(source: SkillSource, modelContext: ModelContext) async {
        var effectiveUrl = source.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !effectiveUrl.contains("github.com/") || effectiveUrl.split(separator: "/").count < 4 {
            if source.name.contains("github.com/") {
                effectiveUrl = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        print("[Van Sync] [GITHUB] Effective URL: \(effectiveUrl)")
        let cleaned = effectiveUrl.replacingOccurrences(of: ".git", with: "")
        
        guard let url = URL(string: cleaned) else {
            await updateStatus(source, "Error: Invalid URL")
            return
        }
        
        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard parts.count >= 2 else {
            await updateStatus(source, "Error: URL format error")
            return
        }
        
        let owner = parts[0]
        let repo = parts[1]
        let apiBase = "https://api.github.com/repos/\(owner)/\(repo)/contents"
        
        do {
            print("[Van Sync] [GITHUB] Starting recursive scan: \(owner)/\(repo)")
            let newSkills = try await scanGithubRecursive(url: apiBase, currentGroup: "", depth: 0, source: source)
            
            await MainActor.run {
                self.mergeSkills(newSkills, for: source, modelContext: modelContext)
            }
        } catch {
            await updateStatus(source, "Sync Error: \(error.localizedDescription)")
            print("[Van Sync] [ERROR] \(error)")
        }
    }
    
    private func scanGithubRecursive(url: String, currentGroup: String, depth: Int, source: SkillSource) async throws -> [VanSkill] {
        if depth > 8 { return [] }
        print("[Van Sync] [GITHUB] Scanning level \(depth): \(url)")
        let items = try await fetchGithubItems(url: url)
        var skills: [VanSkill] = []
        
        // 1. Check if this directory is a Directory Skill (contains SKILL.md/SKILL.mdc)
        if let skillFile = items.first(where: {
            let n = ($0["name"] as? String)?.uppercased() ?? ""
            return n == "SKILL.MD" || n == "SKILL.MDC"
        }) {
            let dirSkill = generateSkill(from: skillFile, source: source, directoryApiUrl: url)
            skills.append(dirSkill)
            print("[Van Sync] [GITHUB] Found directory skill at: \(url)")
            // Boundary found, stop recursing into this directory's files.
            return skills 
        }
        
        // 2. Scan for subdirectories to find more skills
        for item in items {
            guard let name = item["name"] as? String, let type = item["type"] as? String else { continue }
            
            if type == "dir" {
                // Avoid hidden dirs and known build/dependency dirs
                if !name.hasPrefix(".") && !["node_modules", "bin", "tests", "dist", "build", "docs"].contains(name.lowercased()) {
                    if let subUrl = item["url"] as? String {
                        let subSkills = try await scanGithubRecursive(url: subUrl, currentGroup: name, depth: depth + 1, source: source)
                        skills.append(contentsOf: subSkills)
                    }
                }
            }
        }
        return skills
    }
    
    func fetchGithubItems(url: String) async throws -> [[String: Any]] {
        guard let requestUrl = URL(string: url) else { return [] }
        var request = URLRequest(url: requestUrl)
        request.addValue("VanApp/1.0", forHTTPHeaderField: "User-Agent")
        
        // Add Authorization header if token exists
        if let token = UserDefaults.standard.string(forKey: "githubToken"), !token.isEmpty {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        request.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            print("[Van Sync] [HTTP] Code \(http.statusCode) for \(url)")
            throw NSError(domain: "Sync", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "GitHub API Error \(http.statusCode)"])
        }
        
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }
    
    private func generateSkill(from item: [String: Any], source: SkillSource, directoryApiUrl: String? = nil) -> VanSkill {
        let fileName = item["name"] as? String ?? ""
        let path = item["path"] as? String ?? ""
        let downloadUrl = item["download_url"] as? String ?? ""
        
        let pathComponents = path.components(separatedBy: "/")
        var displayName = fileName.replacingOccurrences(of: ".mdc", with: "").replacingOccurrences(of: ".md", with: "")
        
        // Core logic: if this is a directory-based Skill (SKILL.md found),
        // then the Skill name is the directory name.
        if ["SKILL", "README"].contains(displayName.uppercased()) {
            if pathComponents.count >= 2 {
                displayName = pathComponents[pathComponents.count - 2]
            }
        }
        
        let skill = VanSkill(name: displayName, description: "Remote Skill", ecosystem: fileName.lowercased().hasSuffix(".mdc") ? .cursor : .openSkills, remoteUrl: downloadUrl, directoryApiUrl: directoryApiUrl, isDirectory: directoryApiUrl != nil)
        skill.sourceId = source.id
        skill.categoryRaw = SkillCategory.global.rawValue
        
        // Group path logic: 1:1 replica of GitHub directory hierarchy
        // Rule: groupPath is the path preceding the file (or Skill directory).
        
        var components = pathComponents
        if !components.isEmpty { components.removeLast() } // Remove file name
        
        // For directory skills, we remove one more level (the skill's own directory name),
        // so it appears in the parent group instead of its own name group.
        if (fileName.uppercased() == "SKILL.MD" || fileName.uppercased() == "SKILL.MDC") && !components.isEmpty {
            components.removeLast()
        }
        
        // Maintain 1:1 structure without stripping "skills", "rules", etc.
        skill.groupPath = components.joined(separator: "/")
        
        print("[Van Sync] [SKILL] Generated: \(displayName), group: '\(skill.groupPath)', path: \(path)")
        return skill
    }
    
    private func updateStatus(_ source: SkillSource, _ status: String) async {
        await MainActor.run { source.statusRaw = status }
    }

    private func syncLocalProject(source: SkillSource, modelContext: ModelContext) async {
        print("[Van Sync] [LOCAL] Starting local sync for: \(source.name)")
        print("[Van Sync] [LOCAL] Path: \(source.localPathString)")
        
        guard let url = URL(string: source.localPathString) else {
            print("[Van Sync] [LOCAL] Invalid URL for path: \(source.localPathString)")
            await updateStatus(source, "Error: Invalid Path")
            return
        }
        
        let fileManager = FileManager.default
        let searchPaths = [
            url.appendingPathComponent(".agent/skills"),
            url.appendingPathComponent(".cursor/rules"),
            url.appendingPathComponent("skills")
        ]
        
        print("[Van Sync] [LOCAL] Search paths: \(searchPaths.map { $0.path })")
        
        var results: [VanSkill] = []
        
        // Recursive scan function
        func scanDirectory(at dir: URL, relativeTo root: URL) {
            let keys: [URLResourceKey] = [.isDirectoryKey]
            guard let items = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
                return
            }
            
            // 1. Check for SKILL.md or SKILL.mdc
            if let skillFile = items.first(where: {
                let name = $0.lastPathComponent.uppercased()
                return name == "SKILL.MD" || name == "SKILL.MDC"
            }) {
                let ext = skillFile.pathExtension.lowercased()
                let skillDir = dir
                let displayName = dir.lastPathComponent
                
                let content = (try? String(contentsOf: skillFile, encoding: .utf8)) ?? ""
                let (desc, _) = extractMetadata(from: content)
                
                let skill = VanSkill(name: displayName, description: desc.isEmpty ? "Local Directory Skill" : desc, ecosystem: ext == "mdc" ? .cursor : .openSkills)
                skill.localPathString = skillDir.path
                skill.sourceId = source.id
                skill.categoryRaw = SkillCategory.project.rawValue
                skill.isInstalled = true
                skill.isDirectory = true
                
                // Calculate groupPath
                let components = dir.pathComponents
                let rootComponents = root.pathComponents
                if components.count > rootComponents.count {
                    // For directory skills, remove the skill's own directory name
                    let relativeComponents = Array(components[rootComponents.count..<components.count-1])
                    skill.groupPath = relativeComponents.joined(separator: "/")
                }
                
                results.append(skill)
                print("[Van Sync] [LOCAL] Found directory skill: \(displayName) at \(dir.path)")
                return // Stop recursing here
            }
            
            // 2. Check for individual .md or .mdc files (File-based Skill)
            for itemURL in items {
                let name = itemURL.lastPathComponent
                let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                
                if !isDir {
                    let ext = itemURL.pathExtension.lowercased()
                    if (ext == "mdc" || ext == "md") && name.uppercased() != "SKILL.MD" && name.uppercased() != "SKILL.MDC" {
                        let displayName = itemURL.deletingPathExtension().lastPathComponent
                        let content = (try? String(contentsOf: itemURL, encoding: .utf8)) ?? ""
                        let (desc, _) = extractMetadata(from: content)
                        
                        let skill = VanSkill(name: displayName, description: desc.isEmpty ? "Local Skill" : desc, ecosystem: ext == "mdc" ? .cursor : .openSkills)
                        skill.localPathString = itemURL.path
                        skill.sourceId = source.id
                        skill.categoryRaw = SkillCategory.project.rawValue
                        skill.isInstalled = true
                        skill.isDirectory = false
                        
                        // Calculate groupPath
                        let components = itemURL.pathComponents
                        let rootComponents = root.pathComponents
                        if components.count > rootComponents.count {
                            // Path minus root and filename = relative group folders
                            let relativeComponents = Array(components[rootComponents.count..<components.count-1])
                            skill.groupPath = relativeComponents.joined(separator: "/")
                        }
                        
                        results.append(skill)
                        print("[Van Sync] [LOCAL] Found file skill: \(displayName) at \(itemURL.path)")
                    }
                }
            }
            
            // 3. Continue recursing into subdirectories
            for itemURL in items {
                let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir {
                    let name = itemURL.lastPathComponent.lowercased()
                    if !name.hasPrefix(".") && !["node_modules", "bin", "tests", "dist", "build", "docs"].contains(name) {
                        scanDirectory(at: itemURL, relativeTo: root)
                    }
                }
            }
        }
        
        for path in searchPaths {
            if fileManager.fileExists(atPath: path.path) {
                print("[Van Sync] [LOCAL] Scanning: \(path.path)")
                scanDirectory(at: path, relativeTo: path)
            } else {
                print("[Van Sync] [LOCAL] Path does not exist: \(path.path)")
            }
        }
        
        print("[Van Sync] [LOCAL] Total skills found: \(results.count)")
        
        await MainActor.run {
            self.mergeSkills(results, for: source, modelContext: modelContext)
        }
    }
    
    // Incremental update logic: write to SwiftData
    @MainActor
    private func mergeSkills(_ newSkills: [VanSkill], for source: SkillSource, modelContext: ModelContext) {
        print("[Van Sync] [MERGE] Starting merge for source: \(source.name), incoming skills: \(newSkills.count)")
        
        // 1. Get all skills for this source from the current database
        let sourceId = source.id
        var existingSkills: [VanSkill] = []
        do {
            let descriptor = FetchDescriptor<VanSkill>(predicate: #Predicate { $0.sourceId == sourceId })
            existingSkills = try modelContext.fetch(descriptor)
            print("[Van Sync] [MERGE] Found \(existingSkills.count) existing skills in DB")
        } catch {
            print("[Van Sync] [MERGE] Fetch failed: \(error)")
            source.statusRaw = "Error: DB Fetch Failed"
            return
        }
        
        var activeSkillIds = Set<UUID>()
    
        for newSkill in newSkills {
            if let existing = existingSkills.first(where: { $0.name == newSkill.name && $0.groupPath == newSkill.groupPath }) {
                // Update
                existing.remoteContentUrlString = newSkill.remoteContentUrlString
                existing.remoteDirectoryApiUrlString = newSkill.remoteDirectoryApiUrlString
                existing.localPathString = newSkill.localPathString
                existing.ecosystem = newSkill.ecosystem
                existing.isInstalled = newSkill.isInstalled
                existing.isDirectory = newSkill.isDirectory
                
                if (existing.desc == "Remote Skill" || existing.desc == "Local Skill") && newSkill.desc != "Remote Skill" && newSkill.desc != "Local Skill" {
                    existing.desc = newSkill.desc
                }
                
                activeSkillIds.insert(existing.id)
            } else {
                // Insert new
                modelContext.insert(newSkill)
                activeSkillIds.insert(newSkill.id)
                print("[Van Sync] [MERGE] Inserted new skill: \(newSkill.name)")
            }
        }
    
        // 2. Cleanup stale skills (not in current sync results)
        for existing in existingSkills {
            if !activeSkillIds.contains(existing.id) {
                print("[Van Sync] [MERGE] Deleting stale skill: \(existing.name)")
                modelContext.delete(existing)
            }
        }
        
        // Save to reflect in UI immediately
        do {
            try modelContext.save()
            print("[Van Sync] [MERGE] DB save successful")
        } catch {
            print("[Van Sync] [MERGE] DB save failed: \(error)")
            source.statusRaw = "Error: DB Save Failed"
            return
        }
        
        source.lastSynced = Date()
        source.statusRaw = activeSkillIds.isEmpty ? "No valid skills" : "active"
        print("[Van Sync] [MERGE] Complete. Status: \(source.statusRaw), Valid: \(activeSkillIds.count)")
    }

    
    private func extractMetadata(from content: String) -> (String, String) {
        var description = ""
        let version = ""
        
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match YAML frontmatter description:
            if trimmed.hasPrefix("description:") {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count > 1 {
                    description = String(parts[1])
                }
            }
            // Match @description marker
            else if line.contains("@description") {
                let parts = line.split(separator: " ", maxSplits: 1)
                if parts.count > 1 {
                    description = String(parts[1])
                }
            }
            
            if !description.isEmpty {
                // Deep clean
                description = description
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
                    .replacingOccurrences(of: "\\n", with: " ") // Remove escaped newlines
                
                // Remove Markdown markers
                if description.hasPrefix(">") { description.removeFirst() }
                
                break
            }
        }
        
        return (description.trimmingCharacters(in: .whitespacesAndNewlines), version)
    }

    func installSkill(_ skill: VanSkill, to targetSource: SkillSource, modelContext: ModelContext) async throws {
        print("[Van Install] ========== INSTALL START ==========")
        print("[Van Install] Skill: \(skill.name)")
        print("[Van Install] GroupPath: '\(skill.groupPath)'")
        print("[Van Install] Target: \(targetSource.name)")
        
        // Determine Target Folder
        let basePath = targetSource.localPathString
        guard !basePath.isEmpty else { return }
        let baseUrl = URL(fileURLWithPath: basePath)
        
        let subFolder: String
        if skill.ecosystem == .cursor {
            subFolder = targetSource.typeRaw == SkillSource.SourceType.ide.rawValue ? "rules" : ".cursor/rules"
        } else {
            subFolder = targetSource.typeRaw == SkillSource.SourceType.ide.rawValue ? "skills" : ".agent/skills"
        }
        
        var targetPathComponents = [subFolder]
        if !skill.groupPath.isEmpty {
            var relativeComponents = skill.groupPath.components(separatedBy: "/")
            
            // Path deduplication logic: check if groupPath starts with subFolder's suffix
            // Example: subFolder = ".agent/skills", groupPath = "skills/art" -> Remove "skills/"
            if let lastSub = subFolder.components(separatedBy: "/").last {
                if relativeComponents.first?.lowercased() == lastSub.lowercased() {
                    relativeComponents.removeFirst()
                }
            }
            
            if !relativeComponents.isEmpty {
                targetPathComponents.append(contentsOf: relativeComponents)
            }
        }
        
        // For directory-based Skills, create a directory named after the Skill
        if !skill.remoteDirectoryApiUrlString.isEmpty {
            targetPathComponents.append(skill.name)
        }
        
        let folder = targetPathComponents.reduce(baseUrl) { $0.appendingPathComponent($1) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        
        if !skill.remoteDirectoryApiUrlString.isEmpty {
            // Recursive directory download
            print("[Van Install] Directory Skill detected. Recursively downloading from: \(skill.remoteDirectoryApiUrlString)")
            try await downloadDirectoryRecursive(apiUrl: skill.remoteDirectoryApiUrlString, targetFolder: folder)
        } else if let remoteUrl = skill.remoteContentUrl {
            // Single file download
            var request = URLRequest(url: remoteUrl)
            request.addValue("VanApp/1.0", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let content = String(data: data, encoding: .utf8) else { return }
            
            let fileName = skill.name + (skill.ecosystem == .cursor ? ".mdc" : ".md")
            let fileUrl = folder.appendingPathComponent(fileName)
            try content.write(to: fileUrl, atomically: true, encoding: .utf8)
            print("[Van Install] File downloaded: \(fileUrl.path)")
        }
        
        print("[Van Install] ========== INSTALL COMPLETE ==========")
        await sync(source: targetSource, modelContext: modelContext)
    }
    
    private func downloadDirectoryRecursive(apiUrl: String, targetFolder: URL) async throws {
        let items = try await fetchGithubItems(url: apiUrl)
        for item in items {
            guard let name = item["name"] as? String, let type = item["type"] as? String else { continue }
            
            if type == "file" {
                if let downloadUrlStr = item["download_url"] as? String, let downloadUrl = URL(string: downloadUrlStr) {
                    var request = URLRequest(url: downloadUrl)
                    request.addValue("VanApp/1.0", forHTTPHeaderField: "User-Agent")
                    let (data, _) = try await URLSession.shared.data(for: request)
                    let fileUrl = targetFolder.appendingPathComponent(name)
                    try data.write(to: fileUrl)
                    print("[Van Install] [DIR] Downloaded file: \(name)")
                }
            } else if type == "dir" {
                if let subApiUrl = item["url"] as? String {
                    let subFolder = targetFolder.appendingPathComponent(name)
                    try FileManager.default.createDirectory(at: subFolder, withIntermediateDirectories: true)
                    try await downloadDirectoryRecursive(apiUrl: subApiUrl, targetFolder: subFolder)
                }
            }
        }
    }


    
    /// Batch fetch remote Skills metadata (descriptions)
    func fetchMetadataForSkills(_ skills: [VanSkill], modelContext: ModelContext) async {
        print("[Van Metadata] Starting batch fetch for \(skills.count) skills")
        
        await withTaskGroup(of: Void.self) { group in
            // Max 5 concurrent requests
            let maxConcurrent = 5
            var active = 0
            
            for skill in skills {
                if !skill.isRemote || (skill.desc != "Remote Skill" && !skill.desc.isEmpty) { continue }
                if skill.remoteContentUrl == nil { continue }
                
                if active >= maxConcurrent {
                    await group.next()
                    active -= 1
                }
                
                group.addTask {
                    await self.fetchSingleMetadata(skill)
                }
                active += 1
            }
        }
        
        // Save changes
        await MainActor.run {
            try? modelContext.save()
        }
        print("[Van Metadata] Batch fetch complete")
    }
    
    private func fetchSingleMetadata(_ skill: VanSkill) async {
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
            print("[Van Metadata] Failed for \(skill.name): \(error)")
        }
    }

}
