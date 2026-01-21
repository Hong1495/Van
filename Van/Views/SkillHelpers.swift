//
//  SkillHelpers.swift
//  Van
//
//  Created by Antigravity on 2026-01-20.
//

import SwiftUI

func ecosystemIcon(for eco: SkillEcosystem) -> String {
    switch eco {
    case .openSkills: return "shippingbox"
    case .cursor: return "cursorarrow"
    case .aider: return "terminal"
    case .custom: return "pencil"
    }
}

func ecosystemColor(for eco: SkillEcosystem) -> Color {
    switch eco {
    case .openSkills: return .orange
    case .cursor: return .blue
    case .aider: return .green
    case .custom: return .purple
    }
}
