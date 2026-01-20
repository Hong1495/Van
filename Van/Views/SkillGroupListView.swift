
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
    
    // 性能优化：将计算结果作为 State
    @State private var groupedSkills: [String: [VanSkill]] = [:]
    @State private var sortedGroups: [String] = []
    @State private var isCalculating = false
    
    // 丢失的状态需要加回来
    @State private var installedMap: [String: [String]] = [:]
    @State private var searchText = ""
    @State private var showDeleteGroupConfirmation = false
    @State private var groupSkillsToDelete: [VanSkill] = []
    
    var body: some View {
        ScrollView {
            if isCalculating {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(50)
            } else {
                LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                    ForEach(sortedGroups, id: \.self) { group in
                        let groupSkills = groupedSkills[group] ?? []
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
                                        groupSkillsToDelete = groupSkills
                                        showDeleteGroupConfirmation = true
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
                    
                    // 搜索无结果提示
                    if !searchText.isEmpty && sortedGroups.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .padding(.top, 100)
                    }
                }
                .padding()
            }
        }
        .searchable(text: $searchText, prompt: "搜索 Skill 名称或描述...")
        .alert("确认删除分组", isPresented: $showDeleteGroupConfirmation) {
            Button("删除 \(groupSkillsToDelete.count) 项", role: .destructive) {
                onUninstallGroupRequest(groupSkillsToDelete)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要删除此分组下的所有技能吗？此操作不可撤销。")
        }
        // 监听数据变化，触发异步计算
        .onChange(of: skills.count) { _, _ in Task { await updateData() } }
        .onChange(of: searchText) { _, _ in Task { await updateData() } }
        .task {
            // 初始加载
            await updateData()
        }
    }
    
    // 异步更新数据：分组、排序和安装状态
    private func updateData() async {
        // 避免重复计算（可选，视情况而定）
        // isCalculating = true // 会导致闪烁，暂时不用
        
        let currentSearch = searchText
        let currentSkills = skills // 捕获当前快照
        
        await calculateInstalledMapAsync()
        
        // 放到后台线程计算
        let (newGrouped, newSorted) = await Task.detached(priority: .userInitiated) {
            // 1. 过滤
            var filtered = currentSkills
            if !currentSearch.isEmpty {
                let lowercasedSearch = currentSearch.lowercased()
                filtered = filtered.filter { $0.name.lowercased().contains(lowercasedSearch) }
            }
            
            // 2. 分组
            let grouped = Dictionary(grouping: filtered, by: { $0.groupPath })
            
            // 3. 排序 Keys
            let sorted = grouped.keys.sorted {
                if $0.isEmpty { return true }
                if $1.isEmpty { return false }
                return $0 < $1
            }
            
            return (grouped, sorted)
        }.value
        
        // 回到主线程更新 UI
        self.groupedSkills = newGrouped
        self.sortedGroups = newSorted
        // isCalculating = false
    }
    
    private func calculateInstalledMapAsync() async {
        // ... (保持不变，但确保在 updateData 中被调用)
        var map: [String: Set<String>] = [:]
        let localSources = allSources.filter {
            $0.typeRaw == SkillSource.SourceType.project.rawValue ||
            $0.typeRaw == SkillSource.SourceType.ide.rawValue
        }
        
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
        
        await MainActor.run {
            self.installedMap = map.mapValues { Array($0).sorted() }
        }
    }
}
