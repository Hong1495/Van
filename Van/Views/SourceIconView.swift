//
//  SourceIconView.swift
//  Van
//
//  Created by Antigravity on 2026-01-20.
//

import SwiftUI

struct SourceIconView: View {
    let source: SkillSource
    let fallbackSystemImage: String
    
    @State private var iconImage: Image?
    
    var body: some View {
        Group {
            if let iconImage {
                iconImage
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: fallbackSystemImage)
                    .frame(width: 16, height: 16)
            }
        }
        .task { await fetchIcon() }
    }
    
    private func fetchIcon() async {
        // Local source: get file icon
        if source.typeRaw != SkillSource.SourceType.subscription.rawValue {
            let path = source.localPathString
            if !path.isEmpty {
                let nsImage = NSWorkspace.shared.icon(forFile: path)
                self.iconImage = Image(nsImage: nsImage)
            }
            return
        }
        
        // Remote source: parse GitHub avatar
        // Assume URL format: https://github.com/owner/repo
        if let url = URL(string: source.urlString),
           url.host() == "github.com" {
            let components = url.pathComponents
            if components.count >= 2 {
                let owner = components[1]
                let avatarUrl = URL(string: "https://github.com/\(owner).png?size=64")!
                
                // Simple cache policy: use URLCache
                let request = URLRequest(url: avatarUrl, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10)
                
                if let (data, _) = try? await URLSession.shared.data(for: request),
                   let nsImage = NSImage(data: data) {
                    await MainActor.run {
                        self.iconImage = Image(nsImage: nsImage)
                    }
                }
            }
        }
    }
}
