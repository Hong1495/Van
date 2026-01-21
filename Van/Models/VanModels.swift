import Foundation
import SwiftData

@Model
final class SkillSource {
    var id: UUID = UUID()
    var name: String = ""
    var urlString: String = "" // For subscription types
    var typeRaw: String = "subscription"
    var localPathString: String = "" // For project and ide types
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
        case project = "project"       // Local project directory
        case ide = "ide"               // Global IDE environment (Antigravity, Cursor, Claude, etc.)
        case subscription = "subscription" // Network subscription source (GitHub, etc.)
    }
}


@Model
final class VanSkill {
    var id: UUID = UUID()
    var name: String = ""
    var desc: String = ""
    var groupPath: String = "" // Group path, e.g., "frontend/react"
    var version: String?
    var sourceId: UUID?
    var ecosystemRaw: String = "OpenSkills"
    var localPathString: String = ""
    var remoteContentUrlString: String = ""
    var remoteDirectoryApiUrlString: String = "" // For recursive download of directory-based Skills
    var isRemote: Bool = true
    var categoryRaw: String = "Global" // Global or Project
    var isDirectory: Bool = false
    var isInstalled: Bool = false
    var isActive: Bool = true
    
    var localPath: URL? { localPathString.isEmpty ? nil : URL(fileURLWithPath: localPathString) }
    var remoteContentUrl: URL? { URL(string: remoteContentUrlString) }
    var directoryApiUrl: URL? { URL(string: remoteDirectoryApiUrlString) }
    
    var ecosystem: SkillEcosystem {
        get { SkillEcosystem(rawValue: ecosystemRaw) ?? .openSkills }
        set { ecosystemRaw = newValue.rawValue }
    }
    
    init(name: String, description: String, ecosystem: SkillEcosystem, remoteUrl: String? = nil, directoryApiUrl: String? = nil, isDirectory: Bool = false) {
        self.name = name
        self.desc = description
        self.ecosystemRaw = ecosystem.rawValue
        self.remoteContentUrlString = remoteUrl ?? ""
        self.remoteDirectoryApiUrlString = directoryApiUrl ?? ""
        self.isRemote = (remoteUrl != nil || directoryApiUrl != nil)
        self.isDirectory = isDirectory || (directoryApiUrl != nil)
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
