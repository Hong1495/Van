import Foundation
import SwiftData

@Model
final class SkillSource {
    var id: UUID = UUID()
    var name: String = ""
    var urlString: String = "" // 用于 subscription 类型
    var typeRaw: String = "subscription"
    var localPathString: String = "" // 用于 project 和 ide 类型
    var lastSynced: Date?
    var statusRaw: String = "active"
    
    var url: URL? { URL(string: urlString) }
    var localPath: URL? { URL(fileURLWithPath: localPathString) }
    
    init(name: String, url: String = "", localPath: String = "", type: SourceType = .subscription) {
        self.name = name
        self.urlString = url
        self.localPathString = localPath
        self.typeRaw = type.rawValue
        self.id = UUID()
    }
    
    enum SourceType: String, CaseIterable {
        case project = "project"       // 本地项目目录
        case ide = "ide"               // 全局 IDE 环境 (Antigravity, Cursor, Claude 等)
        case subscription = "subscription" // 网络订阅源 (GitHub 等)
    }
}


@Model
final class VanSkill {
    var id: UUID = UUID()
    var name: String = ""
    var desc: String = ""
    var translatedDesc: String? // 持久化翻译结果
    var groupPath: String = "" // 分组路径，如 "frontend/react"
    var version: String?
    var sourceId: UUID?
    var ecosystemRaw: String = "OpenSkills"
    var localPathString: String = ""
    var remoteContentUrlString: String = ""
    var isRemote: Bool = true
    var categoryRaw: String = "Global" // Global or Project
    var isInstalled: Bool = false
    var isActive: Bool = true
    
    var localPath: URL? { localPathString.isEmpty ? nil : URL(fileURLWithPath: localPathString) }
    var remoteContentUrl: URL? { URL(string: remoteContentUrlString) }
    
    var ecosystem: SkillEcosystem {
        get { SkillEcosystem(rawValue: ecosystemRaw) ?? .openSkills }
        set { ecosystemRaw = newValue.rawValue }
    }
    
    init(name: String, description: String, ecosystem: SkillEcosystem, remoteUrl: String? = nil) {
        self.name = name
        self.desc = description
        self.ecosystemRaw = ecosystem.rawValue
        self.remoteContentUrlString = remoteUrl ?? ""
        self.isRemote = remoteUrl != nil
        self.id = UUID()
    }
}

enum SkillCategory: String, CaseIterable {
    case global = "Global"
    case project = "Project"
}

enum SkillEcosystem: String, Codable, CaseIterable {
    case openSkills = "OpenSkills"
    case cursor = "Cursor Rules"
    case aider = "Aider"
    case custom = "Custom"
}
