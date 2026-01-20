//
//  VanApp.swift
//  Van
//
//  Created by Sakya Hong on 2026/1/20.
//

import SwiftUI
import SwiftData
import Combine // Required for ObservableObject

@main
struct VanApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SkillSource.self,
            VanSkill.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        
        Settings {
            SettingsView()
        }
    }
}

// MARK: - Settings & Theme

enum AppTheme: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    
    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    @Published var themeRaw: String {
        didSet { UserDefaults.standard.set(themeRaw, forKey: "appTheme") }
    }
    
    @Published var githubToken: String {
        didSet { UserDefaults.standard.set(githubToken, forKey: "githubToken") }
    }
    
    init() {
        self.themeRaw = UserDefaults.standard.string(forKey: "appTheme") ?? AppTheme.system.rawValue
        self.githubToken = UserDefaults.standard.string(forKey: "githubToken") ?? ""
    }
    
    var theme: AppTheme {
        get { AppTheme(rawValue: themeRaw) ?? .system }
        set { themeRaw = newValue.rawValue }
    }
}

#if canImport(Translation)
import Translation
#endif

// ... (AppTheme & AppSettings 保持不变)

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("通用", systemImage: "gear")
                }
            
            TranslationSettingsView()
                .tabItem {
                    Label("智能翻译", systemImage: "globe")
                }
        }
        .frame(width: 500, height: 350)
    }
}

struct GeneralSettingsView: View {
    @StateObject private var settings = AppSettings.shared
    
    var body: some View {
        Form {
            Section {
                Picker("外观主题", selection: $settings.themeRaw) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                        Text(theme.displayName).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .padding(.vertical, 4)
            }
            
            Section("GitHub 配置") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SecureField("Personal Access Token", text: $settings.githubToken)
                            .textFieldStyle(.roundedBorder)
                        
                        Link(destination: URL(string: "https://github.com/settings/tokens/new?description=Van+Skills+Sync&scopes=public_repo")!) {
                            Image(systemName: "questionmark.circle")
                        }
                        .help("点击打开 GitHub 创建 Token 页面")
                    }
                    
                    Text("如果遇到 Sync Error 403 限流错误，请输入 Token 以增加 API 额度。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 48, height: 48)
                        VStack(alignment: .leading) {
                            Text("Van")
                                .font(.title3.bold())
                            Text("版本 3.8.1")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    LabeledContent("开发者", value: "Van Team")
                    
                    Text("Copyright © 2026 Van Team. All rights reserved.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct TranslationSettingsView: View {
    // Translation States
    @State private var translationStatus: String = "正在检查..."
    @State private var isTranslationSupported = false
    @State private var translationConfig: TranslationSession.Configuration?
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: "globe.desk")
                            .font(.system(size: 40))
                            .foregroundStyle(.blue)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("macOS 智能翻译")
                                .font(.headline)
                            Text("Van 利用 macOS 本地神经网络模型将 Skill 描述翻译为中文，安全且高效。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    
                    Divider()
                    
                    LabeledContent("模型状态") {
                        HStack {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                            Text(translationStatus)
                        }
                    }
                    
                    if isTranslationSupported {
                        HStack {
                            Spacer()
                            Button(action: triggerModelDownload) {
                                Text(translationStatus == "已安装" ? "管理模型..." : "下载离线模型...")
                            }
                        }
                    } else {
                        Text("当前系统不支持 (需 macOS 15+)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await checkTranslationStatus() }
        #if canImport(Translation)
        .translationTask(translationConfig) { session in
            await checkTranslationStatus()
        }
        #endif
    }
    
    private var statusColor: Color {
        switch translationStatus {
        case "已安装": return .green
        case "未安装": return .orange
        case "不支持": return .red
        default: return .gray
        }
    }
    
    private func checkTranslationStatus() async {
        if #available(macOS 15.0, *) {
            #if canImport(Translation)
            isTranslationSupported = true
            let source = Locale.Language(identifier: "en")
            let target = Locale.Language(identifier: "zh-Hans")
            let availability = LanguageAvailability()
            
            let status = await availability.status(from: source, to: target)
            switch status {
            case .installed: translationStatus = "已安装"
            case .supported: translationStatus = "未安装"
            case .unsupported: translationStatus = "不支持"
            @unknown default: translationStatus = "未知"
            }
            #else
            translationStatus = "组件缺失"
            #endif
        } else {
            translationStatus = "系统版本过低"
            isTranslationSupported = false
        }
    }
    
    private func triggerModelDownload() {
        if #available(macOS 15.0, *) {
            #if canImport(Translation)
            translationConfig = .init(source: .init(identifier: "en"), target: .init(identifier: "zh-Hans"))
            #endif
        }
    }
}
