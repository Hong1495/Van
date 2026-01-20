import Foundation

@MainActor
protocol SkillAdapter {
    func parse(at url: URL) async throws -> [VanSkill]
    func write(_ skills: [VanSkill], to url: URL) async throws
    func match(url: URL) -> Bool
}

@MainActor
class OpenSkillsAdapter: SkillAdapter {
    func match(url: URL) -> Bool {
        return url.lastPathComponent == "SKILL.md" || url.path.contains(".claude/skills")
    }
    
    func parse(at url: URL) async throws -> [VanSkill] {
        let content = try String(contentsOf: url, encoding: .utf8)
        
        // 解析 YAML Frontmatter (简单版正则)
        let name = match(pattern: "name:\\s*(.*)", in: content) ?? url.deletingPathExtension().lastPathComponent
        let desc = match(pattern: "description:\\s*(.*)", in: content) ?? "No description"
        
        let skill = VanSkill(name: name, description: desc, ecosystem: .openSkills)
        skill.localPathString = url.path
        return [skill]
    }
    
    private func match(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        if let range = Range(match.range(at: 1), in: text) {
            return String(text[range]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
    
    func write(_ skills: [VanSkill], to url: URL) async throws {
        // TODO: 实现逻辑
    }
}

@MainActor
class CursorAdapter: SkillAdapter {
    func match(url: URL) -> Bool {
        return url.pathExtension == "mdc" || url.path.contains(".cursor/rules")
    }
    
    func parse(at url: URL) async throws -> [VanSkill] {
        // TODO: 实现 .mdc 解析
        return []
    }
    
    func write(_ skills: [VanSkill], to url: URL) async throws {
        // TODO: 实现逻辑
    }
}
