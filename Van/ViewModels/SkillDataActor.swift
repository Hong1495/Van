//
//  SkillDataActor.swift
//  Van
//
//  Created by Antigravity on 2026-01-20.
//

import SwiftData
import Foundation

struct SkillSortDTO: Sendable, Identifiable {
    let id: PersistentIdentifier
    let name: String
    let groupPath: String
}

@ModelActor
actor SkillDataActor {
    func loadDTOs(ids: [PersistentIdentifier]) -> [SkillSortDTO] {
        var dtos: [SkillSortDTO] = []
        
        // 使用 modelContext.model(for:) 在后台线程加载对象
        // 这会将 I/O 操作从主线程移开
        for id in ids {
            if let skill = modelContext.model(for: id) as? VanSkill {
                dtos.append(SkillSortDTO(
                    id: id,
                    name: skill.name,
                    groupPath: skill.groupPath
                ))
            }
        }
        return dtos
    }
}
