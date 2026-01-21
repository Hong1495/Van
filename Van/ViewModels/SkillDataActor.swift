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
        
        // Use modelContext.model(for:) to load objects on background thread
        // This moves I/O operations away from the main thread
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
