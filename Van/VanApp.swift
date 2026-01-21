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
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
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

struct SettingsView: View {
    private enum Tab: Hashable {
        case appearance, github, about
    }
    
    var body: some View {
        TabView {
            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintpalette")
                }
                .tag(Tab.appearance)
            
            GitHubSettingsView()
                .tabItem {
                    Label("GitHub", systemImage: "personalhotspot")
                }
                .tag(Tab.github)
                
            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(Tab.about)
        }
        .frame(width: 480, height: 320)
    }
}

struct AppearanceSettingsView: View {
    @StateObject private var settings = AppSettings.shared
    
    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $settings.themeRaw) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                        Text(theme.displayName).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
                .padding(.vertical, 8)
            } footer: {
                Text("Select how Van appears in your system.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct GitHubSettingsView: View {
    @StateObject private var settings = AppSettings.shared
    
    var body: some View {
        Form {
            Section("API Configuration") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SecureField("Personal Access Token", text: $settings.githubToken)
                            .textFieldStyle(.roundedBorder)
                        
                        Link(destination: URL(string: "https://github.com/settings/tokens/new?description=Van+Skills+Sync&scopes=public_repo")!) {
                            Image(systemName: "questionmark.circle")
                        }
                        .help("Click to open GitHub Token creation page")
                    }
                    
                    Text("Enter a Token to increase API quota and avoid Sync Error 403 (Rate Limit).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            
            VStack(spacing: 4) {
                Text("Van")
                    .font(.title2.bold())
                Text("Version 3.8.1")
                    .foregroundStyle(.secondary)
            }
            
            Divider()
                .frame(width: 200)
            
            VStack(spacing: 8) {
                Text("Copyright © 2026 Van Team.")
                Text("All rights reserved.")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            
            Spacer()
        }
        .padding(.top, 30)
    }
}
