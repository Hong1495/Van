import Foundation
import Combine
import SwiftData

@MainActor
class FlowSyncEngine: ObservableObject {
    @Published var isSyncing = false // 替代 gallerySkills 作为加载状态指示(可选，或直接由 source.statusRaw 驱动)
    static let shared = FlowSyncEngine()
    
    private var syncInProgress = Set<UUID>()
    
    // 串行队列信号量，防止并发过量
    private let syncQueue = DispatchQueue(label: "com.van.sync", qos: .userInitiated)
    
    /// 统一同步入口：可同步网络源或本地源
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
        // ... (URL parsing logic remains same, condensed for brevity in replacement) ...
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
        print("[Van Sync] [GITHUB] target: \(owner)/\(repo)")
        
        do {
            var newSkills: [VanSkill] = []
            // 第一步：抓取根目录
            let rootItems = try await fetchGithubItems(url: apiBase)
            print("[Van Sync] [GITHUB] Root found \(rootItems.count) items")
            
            for item in rootItems {
                if let name = item["name"] as? String, let type = item["type"] as? String {
                    if (name.hasSuffix(".md") || name.hasSuffix(".mdc")) && type == "file" {
                        newSkills.append(generateSkill(from: item, source: source))
                    } else if type == "dir" && (name == "skills" || name == "rules" || name == "gallery") {
                        // 发现核心子目录，进行一级深入（串行）
                        print("[Van Sync] [GITHUB] Deep scanning: \(name)")
                        if let subApi = item["url"] as? String {
                            let subItems = try await fetchGithubItems(url: subApi)
                            for subItem in subItems {
                                if let subName = subItem["name"] as? String, subItem["type"] as? String == "file" {
                                    if subName.hasSuffix(".md") || subName.hasSuffix(".mdc") {
                                        newSkills.append(generateSkill(from: subItem, source: source))
                                    }
                                } else if subItem["type"] as? String == "dir" {
                                    // 再入一级（Anthropic 风格：skills/pdf/SKILL.md）
                                    if let subSubApi = subItem["url"] as? String {
                                        let leafItems = try await fetchGithubItems(url: subSubApi)
                                        for leaf in leafItems {
                                            if let leafName = leaf["name"] as? String, leafName.hasSuffix(".md") || leafName.hasSuffix(".mdc") {
                                                newSkills.append(generateSkill(from: leaf, source: source))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            await MainActor.run {
                self.mergeSkills(newSkills, for: source, modelContext: modelContext)
            }
        } catch {
            await updateStatus(source, "Sync Error: \(error.localizedDescription)")
            print("[Van Sync] [ERROR] \(error)")
        }
    }
    
    private func fetchGithubItems(url: String) async throws -> [[String: Any]] {
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
    
    private func generateSkill(from item: [String: Any], source: SkillSource) -> VanSkill {
        let name = item["name"] as? String ?? ""
        let path = item["path"] as? String ?? ""
        let downloadUrl = item["download_url"] as? String ?? ""
        
        var displayName = name.replacingOccurrences(of: ".mdc", with: "").replacingOccurrences(of: ".md", with: "")
        if ["SKILL", "README"].contains(displayName.uppercased()) {
            let layers = path.components(separatedBy: "/")
            if layers.count >= 2 { displayName = layers[layers.count - 2] }
        }
        
        let skill = VanSkill(name: displayName, description: "Remote Skill", ecosystem: name.hasSuffix(".mdc") ? .cursor : .openSkills, remoteUrl: downloadUrl)
        skill.sourceId = source.id
        skill.categoryRaw = SkillCategory.global.rawValue
        
        // 解析 Group Path (取父目录)
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent().path
        skill.groupPath = parent == "." ? "" : parent
        
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
        
        // 递归遍历函数
        func scanDirectory(at dir: URL, relativeTo root: URL) {
            let keys: [URLResourceKey] = [.isDirectoryKey]
            guard let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: keys) else {
                print("[Van Sync] [LOCAL] Cannot enumerate: \(dir.path)")
                return
            }
            
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent.hasPrefix(".") && !fileURL.lastPathComponent.hasPrefix(".cursor") { continue }
                
                let resourceValues = try? fileURL.resourceValues(forKeys: Set(keys))
                if resourceValues?.isDirectory == true { continue }
                
                let ext = fileURL.pathExtension.lowercased()
                let name = fileURL.lastPathComponent
                let isMarkdown = ext == "md" && name.uppercased() != "README.MD"
                
                if ext == "mdc" || isMarkdown {
                    let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
                    let (desc, _) = extractMetadata(from: content)
                    let displayName = name.replacingOccurrences(of: ".\(ext)", with: "")
                    
                    let skill = VanSkill(name: displayName, description: desc.isEmpty ? "本地 Skill" : desc, ecosystem: ext == "mdc" ? .cursor : .openSkills)
                    skill.localPathString = fileURL.path
                    skill.sourceId = source.id
                    skill.categoryRaw = SkillCategory.project.rawValue
                    skill.isInstalled = true
                    
                    let components = fileURL.pathComponents
                    let rootComponents = root.pathComponents
                    if components.count > rootComponents.count {
                        let relativeComponents = Array(components[rootComponents.count..<components.count-1])
                        skill.groupPath = relativeComponents.joined(separator: "/")
                    }
                    
                    results.append(skill)
                    print("[Van Sync] [LOCAL] Found skill: \(displayName) at \(fileURL.path)")
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
    
    // 增量更新逻辑：写入 SwiftData
    @MainActor
    private func mergeSkills(_ newSkills: [VanSkill], for source: SkillSource, modelContext: ModelContext) {
        print("[Van Sync] [MERGE] Starting merge for source: \(source.name), incoming skills: \(newSkills.count)")
        
        // 1. 获取当前数据库中该源的所有 Skill
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
                // 更新
                existing.remoteContentUrlString = newSkill.remoteContentUrlString
                existing.localPathString = newSkill.localPathString
                existing.ecosystem = newSkill.ecosystem
                existing.isInstalled = newSkill.isInstalled
                
                if (existing.desc == "Remote Skill" || existing.desc == "本地 Skill") && newSkill.desc != "Remote Skill" && newSkill.desc != "本地 Skill" {
                    existing.desc = newSkill.desc
                }
                
                activeSkillIds.insert(existing.id)
            } else {
                // 新增
                modelContext.insert(newSkill)
                activeSkillIds.insert(newSkill.id)
                print("[Van Sync] [MERGE] Inserted new skill: \(newSkill.name)")
            }
        }
        
        // 2. 清理过期的 Skills (不在本次 Sync 结果中的)
        for existing in existingSkills {
            if !activeSkillIds.contains(existing.id) {
                print("[Van Sync] [MERGE] Deleting stale skill: \(existing.name)")
                modelContext.delete(existing)
            }
        }
        
        // 保存以便 UI 立即反映
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
            // 匹配 YAML frontmatter description:
            if trimmed.hasPrefix("description:") {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count > 1 {
                    description = String(parts[1])
                }
            }
            // 匹配 @description 标记
            else if line.contains("@description") {
                let parts = line.split(separator: " ", maxSplits: 1)
                if parts.count > 1 {
                    description = String(parts[1])
                }
            }
            
            if !description.isEmpty {
                // 深度清洗
                description = description
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
                    .replacingOccurrences(of: "\\n", with: " ") // 移除转义换行
                
                // 移除 Markdown 符号
                if description.hasPrefix(">") { description.removeFirst() }
                
                break
            }
        }
        
        return (description.trimmingCharacters(in: .whitespacesAndNewlines), version)
    }
    
    func installSkill(_ skill: VanSkill, to targetSource: SkillSource, modelContext: ModelContext) async throws {
        guard let remoteUrl = skill.remoteContentUrl else {
            print("[Van Install] No remote URL for skill: \(skill.name)")
            return
        }
        
        // 1. 下载内容
        var request = URLRequest(url: remoteUrl)
        request.addValue("VanApp/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let content = String(data: data, encoding: .utf8) else {
            print("[Van Install] Failed to decode content")
            return
        }
        
        // 2. 确定目标目录
        let basePath = targetSource.localPathString
        guard !basePath.isEmpty else {
            print("[Van Install] Empty local path for target: \(targetSource.name)")
            return
        }
        
        let baseUrl = URL(fileURLWithPath: basePath)
        
        // 根据目标类型和 skill 生态选择子目录
        let subFolder: String
        if skill.ecosystem == .cursor {
            subFolder = targetSource.typeRaw == SkillSource.SourceType.ide.rawValue ? "rules" : ".cursor/rules"
        } else {
            subFolder = targetSource.typeRaw == SkillSource.SourceType.ide.rawValue ? "skills" : ".agent/skills"
        }
        
        // 拼接 Group Path，保持目录结构
        var targetPathComponents = [subFolder]
        if !skill.groupPath.isEmpty {
            targetPathComponents.append(skill.groupPath)
        }
        let folder = targetPathComponents.reduce(baseUrl) { $0.appendingPathComponent($1) }
        
        // 3. 创建目录并写入文件
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileName = skill.name + (skill.ecosystem == .cursor ? ".mdc" : ".md")
        let fileUrl = folder.appendingPathComponent(fileName)
        try content.write(to: fileUrl, atomically: true, encoding: .utf8)
        
        print("[Van Install] Success: \(fileUrl.path)")
        
        // 4. 刷新目标源
        await sync(source: targetSource, modelContext: modelContext)
    }

}
