//
//  ArticleDetailView.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/26.
//

import SwiftUI

struct ArticleDetailView: View {
    @StateObject private var viewModel: ArticleDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appNavigationPath) private var appNavigationPath
    @State private var isNavigatingBack = false
    
    init(articleId: String, articleTitle: String) {
        _viewModel = StateObject(wrappedValue: ArticleDetailViewModel(articleId: articleId, initialTitle: articleTitle))
    }
    
    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                topNavBar
                sentenceList
                bottomToolbar
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            print("🟢 [ArticleDetailView] onAppear - articleId: \(viewModel.title)")
            if let path = appNavigationPath {
                print("🟢 [ArticleDetailView] AppNavigationPath available, count: \(path.wrappedValue.count)")
            } else {
                print("🟢 [ArticleDetailView] AppNavigationPath NOT available")
            }
        }
        .task {
            await viewModel.loadArticleIfNeeded()
        }
        .onDisappear {
            print("🟢 [ArticleDetailView] onDisappear - articleId: \(viewModel.title)")
            print("🟢 [ArticleDetailView] onDisappear - appNavigationPath count: \(appNavigationPath?.wrappedValue.count ?? -1)")
            isNavigatingBack = false // 重置状态
            viewModel.stopVoiceReading()
        }
        .alert(viewModel.toastMessage ?? "", isPresented: Binding(
            get: { viewModel.toastMessage != nil },
            set: { _ in viewModel.toastMessage = nil }
        )) {
            Button("确定", role: .cancel) { viewModel.toastMessage = nil }
        }
    }
    
    private var topNavBar: some View {
        HStack {
            Button {
                // 防止重复点击
                guard !isNavigatingBack else {
                    print("🔴 [ArticleDetailView] Already navigating back, ignoring tap")
                    return
                }
                
                print("🔴 [ArticleDetailView] Back button tapped")
                if let path = appNavigationPath {
                    print("🔴 [ArticleDetailView] Using appNavigationPath to go back, current count: \(path.wrappedValue.count)")
                    if path.wrappedValue.count > 0 {
                        isNavigatingBack = true
                        withAnimation {
                            path.wrappedValue.removeLast()
                        }
                        print("🔴 [ArticleDetailView] After removeLast, count: \(path.wrappedValue.count)")
                        // 重置状态，允许下次返回（如果视图还在）
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isNavigatingBack = false
                        }
                    } else {
                        print("🔴 [ArticleDetailView] AppNavigationPath is empty, should already be back")
                        // navigationPath 为空时，说明已经在上一级了，不应该再调用 dismiss()
                    }
                } else {
                    print("🔴 [ArticleDetailView] AppNavigationPath not available, using dismiss()")
                    // 只有在 navigationPath 不可用时才使用 dismiss()
                    isNavigatingBack = true
                    dismiss()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.primary)
            }
            .disabled(isNavigatingBack)
            
            Spacer()
            
            Text(viewModel.title)
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer()
            
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 0.97, green: 0.97, blue: 0.97))
    }
    
    private var sentenceList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if viewModel.sentences.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    ForEach(Array(viewModel.sentences.enumerated()), id: \.element.id) { index, sentence in
                        SentenceCardView(
                            sentence: sentence,
                            isOriginalActive: viewModel.currentSentenceIndex == index && viewModel.currentPlayingType == .original,
                            isTranslationActive: viewModel.currentSentenceIndex == index && viewModel.currentPlayingType == .translation,
                            toggleFavorite: { viewModel.toggleFavorite(sentence: sentence) },
                            onTap: {
                                viewModel.playSentence(at: index)
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 80)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("📄")
                .font(.system(size: 60))
            Text("暂无内容")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
    
    private var bottomToolbar: some View {
        HStack {
            Button {
                viewModel.toggleVoiceReading()
            } label: {
                VStack {
                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 24))
                    Text(viewModel.isPlaying ? "暂停" : "语音阅读")
                        .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity)
            }
            
            Button {
                // TODO: 阅读设置功能稍后实现
            } label: {
                VStack {
                    Image(systemName: "gearshape")
                        .font(.system(size: 24))
                    Text("阅读设置")
                        .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .background(Color.white)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(red: 0.9, green: 0.9, blue: 0.9)),
            alignment: .top
        )
    }
}

private struct SentenceCardView: View {
    let sentence: ArticleSentence
    let isOriginalActive: Bool
    let isTranslationActive: Bool
    let toggleFavorite: () -> Void
    let onTap: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                originalBlock
                translationBlock
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onTapGesture {
                onTap()
            }
            
            Button(action: toggleFavorite) {
                Image(systemName: sentence.isFavorite ? "star.fill" : "star")
                    .foregroundColor(sentence.isFavorite ? Color.yellow : Color.gray.opacity(0.5))
                    .font(.system(size: 16))
                    .padding(4)
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
    
    private var originalBlock: some View {
        Text(sentence.original)
            .font(.body)
            .foregroundColor(.primary)
            .lineSpacing(4)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isOriginalActive ? Color(red: 0.86, green: 0.96, blue: 0.90) : Color(red: 0.97, green: 0.97, blue: 0.97))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isOriginalActive ? Color(red: 0.02, green: 0.63, blue: 0.30) : Color.clear, lineWidth: 0.8)
            )
            .cornerRadius(10)
    }
    
    private var translationBlock: some View {
        Text(sentence.translation)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .lineSpacing(4)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isTranslationActive ? Color(red: 0.92, green: 0.97, blue: 0.95) : Color(red: 0.98, green: 0.98, blue: 0.98))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isTranslationActive ? Color(red: 0.02, green: 0.63, blue: 0.30) : Color.clear, lineWidth: 0.7)
            )
            .cornerRadius(10)
    }
}

#Preview {
    ArticleDetailView(articleId: "demo", articleTitle: "Chapter Fourteen")
}

