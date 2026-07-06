//
//  MainSelectionView.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/26.
//

import SwiftUI

enum MainViewType: Hashable {
    case article
    case word
}

// 统一的导航路由
enum AppNavigationRoute: Hashable {
    case mainView(MainViewType)
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
    @State private var showWordComingSoon = false
    private let logoutNotification = Notification.Name("ReadingAppLogoutRequested")
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.93, green: 0.97, blue: 1.0),
                        Color.white
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                    .ignoresSafeArea()
                
                VStack(spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ReadingCoach")
                            .font(.largeTitle.bold())
                            .foregroundColor(.primary)
                        Text("拍照导入英语阅读文章，逐句理解、跟读和复习。")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 40)
                    
                    VStack(spacing: 20) {
                        selectionButton(
                            title: "开始阅读学习",
                            subtitle: "查看历史文章、拍照上传新内容并进行语音学习",
                            icon: "doc.text.fill",
                            action: {
                                withAnimation {
                                    navigationPath.append(AppNavigationRoute.mainView(.article))
                                }
                            }
                        )
                        
                        selectionCard(
                            title: "学习统计",
                            subtitle: "查看今日新读篇数、连续天数和最近 7 天进展",
                            icon: "chart.bar.fill",
                            iconColor: Color(red: 0.23, green: 0.54, blue: 0.95),
                            action: {
                                withAnimation {
                                    navigationPath.append(AppNavigationRoute.stats)
                                }
                            }
                        )
                        
                        selectionCard(
                            title: "单词功能",
                            subtitle: "单词单元入口保留，后续再与阅读主线整合",
                            icon: "book.fill",
                            iconColor: Color(red: 0.91, green: 0.59, blue: 0.14),
                            action: {
                                showWordComingSoon = true
                            }
                        )
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    Button {
                        NotificationCenter.default.post(name: logoutNotification, object: nil)
                    } label: {
                        Text("退出登录")
                            .font(.headline)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.9))
                            .cornerRadius(16)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarHidden(true)
            .alert("功能建设中", isPresented: $showWordComingSoon) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("当前原型已经优先完成阅读学习主链路，单词模块会在下一阶段继续完善。")
            }
            .navigationDestination(for: AppNavigationRoute.self) { route in
                Group {
                    switch route {
                    case .mainView(let viewType):
                        switch viewType {
                        case .article:
                            ArticleListView()
                                .environment(\.appNavigationPath, $navigationPath)
                        case .word:
                            WordListView()
                                .environment(\.appNavigationPath, $navigationPath)
                        }
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
        .onChange(of: navigationPath.count) { oldValue, newValue in
            print("🟡 [MainSelectionView] NavigationPath count changed: \(oldValue) -> \(newValue)")
        }
    }
    
    private func selectionButton(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        selectionCard(
            title: title,
            subtitle: subtitle,
            icon: icon,
            iconColor: Color(red: 0.03, green: 0.76, blue: 0.38),
            action: action
        )
        .buttonStyle(PlainButtonStyle())
    }

    private func selectionCard(
        title: String,
        subtitle: String,
        icon: String,
        iconColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(iconColor)
                    .cornerRadius(14)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding(20)
            .background(Color.white.opacity(0.96))
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}


#Preview {
    MainSelectionView()
}
