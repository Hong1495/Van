//
//  DetailSheetView.swift
//  Van
//
//  Created by Antigravity on 2026-01-20.
//

import SwiftUI
#if canImport(Translation)
import Translation
#endif

struct DetailSheetView: View {
    let skill: VanSkill
    
    let fetchRemoteMetadata: () async -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
             HStack {
                 Image(systemName: ecosystemIcon(for: skill.ecosystem))
                     .font(.title)
                     .foregroundStyle(ecosystemColor(for: skill.ecosystem))
                 Text(skill.name).font(.title)
                 
                 Spacer()
                 
                 Button { dismiss() } label: {
                     Image(systemName: "xmark.circle.fill")
                         .font(.title2)
                         .foregroundStyle(.secondary)
                 }
                 .buttonStyle(.plain)
             }
             
             ScrollView {
                 Text(skill.desc)
                     .font(.title3)
                     .lineSpacing(6)
                     .textSelection(.enabled)
             }
             
             Spacer()
         }
         .padding(30)
         .frame(width: 500, height: 400)
         .task {
             // Fetch remote metadata if missing
             if skill.isRemote && (skill.desc == "Remote Skill" || skill.desc.isEmpty) {
                 await fetchRemoteMetadata()
             }
         }
    }
}
