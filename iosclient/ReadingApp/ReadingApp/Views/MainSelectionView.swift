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
                                    case .article(let article, let focusSentenceId):
                                        ArticleDetailView(
                                            articleId: article.id,
                                            articleTitle: article.title,
                                            focusSentenceId: focusSentenceId,
                                            onContinuousReadingFinished: {
                                                openNextArticle(after: article.id)
                                            }
                                        )
                                            .id("article-\(article.id)-\(focusSentenceId.map(String.init) ?? "none")")
                                            .environment(\.appNavigationPath, $navigationPath)
                                    case .autoPlayArticle(let article):
                                        ArticleDetailView(
                                            articleId: article.id,
                                            articleTitle: article.title,
                                            startsContinuousReading: true,
                                            onContinuousReadingFinished: {
                                                openNextArticle(after: article.id)
                                            }
                                        )
                                            .id("auto-play-article-\(article.id)")
                                            .environment(\.appNavigationPath, $navigationPath)
                                    case .cameraResult(let articleId):
                                        ArticleDetailView(
                                            articleId: articleId,
                                            articleTitle: "图片解析文章",
                                            onContinuousReadingFinished: {
                                                openNextArticle(after: articleId)
                                            }
                                        )
                                            .id("camera-article-\(articleId)")
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

    private func openNextArticle(after articleId: String) {
        guard let nextArticle = ArticleCacheStore.shared.cachedArticles().nextArticle(after: articleId) else { return }

        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        }
        navigationPath.append(
            AppNavigationRoute.articleRoute(.autoPlayArticle(nextArticle))
        )
    }
}


#Preview {
    MainSelectionView()
}
