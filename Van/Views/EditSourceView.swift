//
//  EditSourceView.swift
//  Van
//
//  Refactored by Antigravity on 2026-01-20.
//

import SwiftUI
import SwiftData

struct EditSourceView: View {
    let source: SkillSource
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var engine = FlowSyncEngine.shared
    
    @State private var name: String
    @State private var url: String
    @State private var path: String
    
    init(source: SkillSource) {
        self.source = source
        _name = State(initialValue: source.name)
        _url = State(initialValue: source.urlString)
        _path = State(initialValue: source.localPathString)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("信息") {
                    TextField("名称", text: $name)
                    if source.typeRaw == SkillSource.SourceType.subscription.rawValue {
                        TextField("GitHub 地址", text: $url)
                    } else {
                        HStack {
                            TextField("本地路径", text: $path)
                            Button("选择...") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                if panel.runModal() == .OK { path = panel.url?.path ?? path }
                            }
                        }
                    }
                }
            }
            .navigationTitle("编辑源")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        source.name = name
                        source.urlString = url
                        source.localPathString = path
                        Task { await engine.sync(source: source, modelContext: modelContext) }
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 400, height: 300)
    }
}
