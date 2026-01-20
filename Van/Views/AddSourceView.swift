import SwiftUI
import SwiftData

struct AddSourceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var engine = FlowSyncEngine.shared
    
    @State private var name = ""
    @State private var url = ""
    @State private var type = SkillSource.SourceType.subscription
    
    var body: some View {
        VStack(spacing: 20) {
            Text("添加订阅")
                .font(.headline)
            
            Form {
                TextField("名称:", text: $name)
                    .textFieldStyle(.roundedBorder)
                
                TextField("URL:", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 300)
                    .onChange(of: url, initial: false) { oldValue, newValue in
                        if name.isEmpty, let last = newValue.split(separator: "/").last {
                            name = String(last).capitalized
                        }
                    }
                
                Text("输入 GitHub 仓库地址，例如:\nhttps://github.com/owner/repo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal)
            
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                
                Button("添加") {
                    let newSource = SkillSource(name: name, url: url, type: type)
                    modelContext.insert(newSource)
                    Task { await engine.sync(source: newSource, modelContext: modelContext) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || !url.contains("github.com/"))
            }
            .padding(.top, 10)
        }
        .padding()
        .frame(width: 450)
    }
}
