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
                Section("Information") {
                    TextField("Name", text: $name)
                    if source.typeRaw == SkillSource.SourceType.subscription.rawValue {
                        TextField("GitHub URL", text: $url)
                    } else {
                        HStack {
                            TextField("Local Path", text: $path)
                            Button("Select...") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                if panel.runModal() == .OK { path = panel.url?.path ?? path }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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
