
import SwiftUI
import SwiftData

struct SkillGroupListView: View {
    let source: SkillSource
    let skills: [VanSkill]
    let allSources: [SkillSource]
    @ObservedObject var engine: FlowSyncEngine
    
    @Environment(\.modelContext) private var modelContext
    
    // Actions passed from parent
    var onInstallRequest: (VanSkill) -> Void
    var onUninstallRequest: (VanSkill) -> Void
    var onInstallGroupRequest: ([VanSkill]) -> Void
    var onUninstallGroupRequest: ([VanSkill]) -> Void
    
    // 性能优化：将 installedMap 作为 State，避免每次渲染都重新计算
    @State private var installedMap: [String: [String]] = [:]
    
    var body: some View {
        // 按 GroupPath 分组
        let grouped = Dictionary(grouping: skills, by: { $0.groupPath })
        let sortedKeys = grouped.keys.sorted {
            if $0.isEmpty { return true } // Root first
            if $1.isEmpty { return false }
            return $0 < $1
        }
        
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                ForEach(sortedKeys, id: \.self) { group in
                    let groupSkills = grouped[group] ?? []
                    Section {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                            ForEach(groupSkills) { skill in
                                SkillCardView(
                                    skill: skill,
                                    installedIn: installedMap[skill.name] ?? [],
                                    onInstall: { onInstallRequest(skill) },
                                    onUninstall: { onUninstallRequest(skill) }
                                )
                            }
                        }
                    } header: {
                        HStack {
                            Image(systemName: group.isEmpty ? "folder.fill" : "folder")
                            Text(group.isEmpty ? "根目录" : group)
                                .font(.headline)
                            
                            Spacer()
                            
                            if source.typeRaw == SkillSource.SourceType.subscription.rawValue {
                                // 订阅源：安装全部
                                Button("安装全部") {
                                    onInstallGroupRequest(groupSkills)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(groupSkills.isEmpty)
                            } else {
                                // 本地/IDE 源：删除全部
                                Button("删除全部") {
                                    onUninstallGroupRequest(groupSkills)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(groupSkills.isEmpty)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.regularMaterial)
                    }
                }
            }
            .padding()
        }
        .task(id: skills.count) {
            // 异步计算 installedMap，避免阻塞主线程
            await calculateInstalledMapAsync()
        }
    }
    
    private func calculateInstalledMapAsync() async {
        var map: [String: Set<String>] = [:]
        let localSources = allSources.filter {
            $0.typeRaw == SkillSource.SourceType.project.rawValue ||
            $0.typeRaw == SkillSource.SourceType.ide.rawValue
        }
        
        // 从 SwiftData 查询所有已安装的 Skills
        var installedSkills: [VanSkill] = []
        do {
            let descriptor = FetchDescriptor<VanSkill>(predicate: #Predicate { $0.isInstalled })
            installedSkills = try modelContext.fetch(descriptor)
        } catch {
            print("Failed to fetch installed skills: \(error)")
        }
        
        for skill in installedSkills {
            if let sourceName = localSources.first(where: { $0.id == skill.sourceId })?.name {
                map[skill.name, default: []].insert(sourceName)
            }
        }
        
        // 在主线程更新 State
        await MainActor.run {
            self.installedMap = map.mapValues { Array($0).sorted() }
        }
    }
}
