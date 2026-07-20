//
//  MainSelectionView.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/26.
//

import SwiftUI

enum MainViewType: Hashable {
    case article
}

// 统一的导航路由
enum AppNavigationRoute: Hashable {
    case articleRoute(ArticleRoute)
    case stats
}

// 环境值 key，用于传递主 NavigationPath
private struct AppNavigationPathKey: EnvironmentKey {
    static let defaultValue: Binding<NavigationPath>? = nil
}

extension EnvironmentValues {
    var appNavigationPath: Binding<NavigationPath>? {
        get { self[AppNavigationPathKey.self] }
        set { self[AppNavigationPathKey.self] = newValue }
    }
}

struct MainSelectionView: View {
    @State private var navigationPath = NavigationPath()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                ArticleSplitView()
            } else {
                NavigationStack(path: $navigationPath) {
                    ArticleListView()
                        .environment(\.appNavigationPath, $navigationPath)
                        .navigationBarHidden(true)
                        .navigationDestination(for: AppNavigationRoute.self) { route in
                            Group {
                                switch route {
                                case .articleRoute(let articleRoute):
                                    switch articleRoute {
                                    case .article(let article):
                                        ArticleDetailView(articleId: article.id, articleTitle: article.title)
                                            .environment(\.appNavigationPath, $navigationPath)
                                    case .cameraResult(let articleId):
                                        ArticleDetailView(articleId: articleId, articleTitle: "图片解析文章")
                                            .environment(\.appNavigationPath, $navigationPath)
                                    }
                                case .stats:
                                    StatsView()
                                        .environment(\.appNavigationPath, $navigationPath)
                                }
                            }
                        }
                }
            }
        }
    }
}


#Preview {
    MainSelectionView()
}
