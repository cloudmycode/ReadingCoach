//
//  StatsView.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2026/7/6.
//

import SwiftUI

struct StatsView: View {
    @StateObject private var viewModel = StatsViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.98, blue: 0.96),
                    Color(red: 0.99, green: 0.99, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    topBar
                    overviewCards
                    recentTrendCard
                    summaryCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationBarBackButtonHidden(true)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.load()
        }
        .alert(viewModel.toastMessage ?? "", isPresented: Binding(
            get: { viewModel.toastMessage != nil },
            set: { _ in viewModel.toastMessage = nil }
        )) {
            Button("确定", role: .cancel) { viewModel.toastMessage = nil }
        }
    }
    
    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.85))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            VStack(spacing: 4) {
                Text("学习统计")
                    .font(.headline)
                Text("最近 7 天的阅读进展")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Color.clear
                .frame(width: 40, height: 40)
        }
        .padding(.top, 8)
    }
    
    private var overviewCards: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                statCard(title: "今日新读", value: "\(viewModel.stats.todayNewArticles)", subtitle: "篇文章", accent: Color(red: 0.04, green: 0.65, blue: 0.35))
                statCard(title: "连续坚持", value: "\(viewModel.stats.currentStreakDays)", subtitle: "天", accent: Color(red: 0.96, green: 0.52, blue: 0.18))
            }
            
            HStack(spacing: 12) {
                statCard(title: "累计文章", value: "\(viewModel.stats.totalArticles)", subtitle: "篇", accent: Color(red: 0.20, green: 0.49, blue: 0.93))
                statCard(title: "今日复习", value: "\(viewModel.stats.todayReviewCount)", subtitle: "次播放/查看", accent: Color(red: 0.64, green: 0.42, blue: 0.90))
            }
        }
    }
    
    private var recentTrendCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("最近 7 天")
                .font(.headline)
            
            if viewModel.stats.recentDays.isEmpty && !viewModel.isLoading {
                Text("还没有学习记录，先去拍一篇阅读文章吧。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.stats.recentDays) { day in
                    HStack(spacing: 12) {
                        Text(shortDate(day.date))
                            .font(.subheadline.weight(.medium))
                            .frame(width: 64, alignment: .leading)
                        
                        Capsule()
                            .fill(day.active ? Color(red: 0.04, green: 0.65, blue: 0.35) : Color.gray.opacity(0.25))
                            .frame(width: 10, height: 10)
                        
                        Text("新读 \(day.newArticles) 篇")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        Text("复习 \(day.reviewCount) 次")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.95))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 5)
    }
    
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("累计学习")
                .font(.headline)
            
            HStack {
                summaryPill(title: "总阅读次数", value: "\(viewModel.stats.totalReadCount)")
                summaryPill(title: "总句子数", value: "\(viewModel.stats.totalSentenceCount)")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.95))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 5)
    }
    
    private func statCard(title: String, value: String, subtitle: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.95))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 5)
    }
    
    private func summaryPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundColor(.primary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.96, green: 0.97, blue: 0.96))
        .cornerRadius(14)
    }
    
    private func shortDate(_ raw: String) -> String {
        let parts = raw.split(separator: "-")
        guard parts.count == 3 else { return raw }
        return "\(parts[1]).\(parts[2])"
    }
}

#Preview {
    StatsView()
}
