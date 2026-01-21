import SwiftUI
import SwiftData
import Foundation


struct SkillGroupListView: View {
    let source: SkillSource
    let skills: [VanSkill]
    let allSources: [SkillSource]
    @ObservedObject var engine: FlowSyncEngine
    
    @Environment(\.modelContext) private var modelContext
    
    // Actions
    var onInstallRequest: (VanSkill) -> Void
    var onUninstallRequest: (VanSkill) -> Void
    var onInstallGroupRequest: ([VanSkill]) -> Void
    var onUninstallGroupRequest: ([VanSkill]) -> Void
    
    @Binding var searchText: String
    @State private var installedMap: [String: [String]] = [:]
    @State private var isCalculating = false
    
    var body: some View {
        ScrollView {
            if filteredSkills.isEmpty {
                ContentUnavailableView("无 Skill", systemImage: "folder.badge.minus", description: Text("搜索结果下没有发现 Skill。"))
                    .padding(.top, 100)
            } else {
                let grouped = Dictionary(grouping: filteredSkills, by: { $0.groupPath })
                let sortedGroups = grouped.keys.sorted()
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 400), spacing: 16)], spacing: 16, pinnedViews: [.sectionHeaders]) {
                    ForEach(sortedGroups, id: \.self) { group in
                        Section {
                            ForEach(grouped[group] ?? []) { skill in
                                SkillRowView(
                                    skill: skill,
                                    installedIn: installedMap[skill.name] ?? [],
                                    onInstall: { onInstallRequest(skill) },
                                    onUninstall: { onUninstallRequest(skill) }
                                )
                            }
                        } header: {
                            if !group.isEmpty {
                                HStack {
                                    Image(systemName: "folder")
                                    Text(group)
                                        .font(.subheadline.bold())
                                    Spacer()
                                    
                                    if source.typeRaw == SkillSource.SourceType.subscription.rawValue {
                                        Button("安装此组") { onInstallGroupRequest(grouped[group] ?? []) }
                                            .buttonStyle(.bordered).controlSize(.small)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.thinMaterial)
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .task {
            await updateData()
        }
        .onChange(of: skills.count) { _, _ in Task { await updateData() } }
    }
    
    // 过滤逻辑
    private var filteredSkills: [VanSkill] {
        var result = skills
        
        // 搜索过滤
        if !searchText.isEmpty {
            let lower = searchText.lowercased()
            result = result.filter { $0.name.lowercased().contains(lower) || $0.desc.lowercased().contains(lower) }
        }
        
        return result.sorted(by: { $0.name < $1.name })
    }
    
    private func updateData() async {
        isCalculating = true
        defer { isCalculating = false }
        
        await calculateInstalledMapAsync()
    }
    
    private func calculateInstalledMapAsync() async {
        var map: [String: Set<String>] = [:]
        let localSources = allSources.filter {
            $0.typeRaw == SkillSource.SourceType.project.rawValue ||
            $0.typeRaw == SkillSource.SourceType.ide.rawValue
        }
        
        let descriptor = FetchDescriptor<VanSkill>(predicate: #Predicate { $0.isInstalled })
        if let installedSkills = try? modelContext.fetch(descriptor) {
            for skill in installedSkills {
                if let sourceName = localSources.first(where: { $0.id == skill.sourceId })?.name {
                    map[skill.name, default: []].insert(sourceName)
                }
            }
        }
        
        await MainActor.run {
            self.installedMap = map.mapValues { Array($0).sorted() }
        }
    }
}


