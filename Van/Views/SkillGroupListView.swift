
import SwiftUI
import SwiftData

struct SkillGroupListView: View {
    let source: SkillSource
    let skills: [VanSkill]
    let allSources: [SkillSource]
    @ObservedObject var engine: FlowSyncEngine
    
    // Actions passed from parent
    var onInstallRequest: (VanSkill) -> Void
    var onUninstallRequest: (VanSkill) -> Void
    var onInstallGroupRequest: ([VanSkill]) -> Void
    
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
                                    installedIn: findInstalledLocations(for: skill),
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
                            
                            // 仅订阅源显示整组安装按钮
                            if source.typeRaw == SkillSource.SourceType.subscription.rawValue {
                                Button("安装全部") {
                                    onInstallGroupRequest(groupSkills)
                                }
                                .buttonStyle(.borderedProminent)
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
    }
    
    private func findInstalledLocations(for skill: VanSkill) -> [String] {
        let localSources = allSources.filter {
            $0.typeRaw == SkillSource.SourceType.project.rawValue ||
            $0.typeRaw == SkillSource.SourceType.ide.rawValue
        }
        var locations: [String] = []
        for source in localSources {
            if engine.gallerySkills.contains(where: {
                $0.sourceId == source.id &&
                $0.name == skill.name &&
                $0.isInstalled
            }) {
                locations.append(source.name)
            }
        }
        return locations
    }
}
