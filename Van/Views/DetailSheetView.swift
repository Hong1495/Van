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
    @Binding var translatedDesc: String?
    
    #if canImport(Translation)
    @Binding var translationConfig: TranslationSession.Configuration?
    #endif
    
    let fetchRemoteMetadata: () async -> Void
    let triggerTranslation: () async -> Void
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
                 // 详情页优先显示翻译结果，如果没有系统翻译，则显示原文
                 Text(skill.translatedDesc ?? skill.desc)
                     .font(.title3)
                     .lineSpacing(6)
                     .textSelection(.enabled)
                 
                 if skill.translatedDesc != nil {
                     Divider()
                     Text("原文：")
                         .font(.caption)
                         .foregroundStyle(.secondary)
                     Text(skill.desc)
                         .font(.body)
                         .foregroundStyle(.secondary)
                         .textSelection(.enabled)
                 }
             }
             
             Spacer()
         }
         .padding(30)
         .frame(width: 500, height: 400)
         .task {
             // 打开详情页时触发抓取和翻译
             if skill.isRemote && (skill.desc == "Remote Skill" || skill.desc.isEmpty) {
                 await fetchRemoteMetadata()
             }
             if skill.translatedDesc == nil {
                 await triggerTranslation()
             }
         }
    }
}
