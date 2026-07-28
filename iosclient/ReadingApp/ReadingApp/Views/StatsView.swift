//
//  StatsView.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2026/7/6.
//

import Charts
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
                    articleTrendCard
                    wordTrendCard
                    summaryCard
                    accountCard
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
                Text("最近 14 天的阅读进展")
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
                statCard(title: "今日复习", value: "\(viewModel.stats.todayReviewCount)", subtitle: "个生词", accent: Color(red: 0.64, green: 0.42, blue: 0.90))
            }
        }
    }

    private var articleTrendCard: some View {
        trendCard(
            title: "文章趋势",
            subtitle: "近 14 天每日新读篇数",
            accent: Color(red: 0.20, green: 0.49, blue: 0.93),
            unit: "篇",
            values: viewModel.stats.recentDays.map { ($0.date, $0.newArticles) }
        )
    }

    private var wordTrendCard: some View {
        trendCard(
            title: "单词趋势",
            subtitle: "近 14 天每日复习词数",
            accent: Color(red: 0.64, green: 0.42, blue: 0.90),
            unit: "词",
            values: viewModel.stats.recentDays.map { ($0.date, $0.reviewCount) }
        )
    }

    private func trendCard(
        title: String,
        subtitle: String,
        accent: Color,
        unit: String,
        values: [(date: String, count: Int)]
    ) -> some View {
        let total = values.reduce(0) { $0 + $1.count }
        let maxValue = max(values.map(\.count).max() ?? 0, 1)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("合计 \(total) \(unit)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(accent)
            }

            if values.isEmpty && !viewModel.isLoading {
                Text("还没有学习记录，先去拍一篇阅读文章吧。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
            } else {
                Chart {
                    ForEach(values, id: \.date) { item in
                        let day = parseDate(item.date)

                        LineMark(
                            x: .value("日期", day, unit: .day),
                            y: .value(unit, item.count)
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                        AreaMark(
                            x: .value("日期", day, unit: .day),
                            y: .value(unit, item.count)
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [accent.opacity(0.28), accent.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        PointMark(
                            x: .value("日期", day, unit: .day),
                            y: .value(unit, item.count)
                        )
                        .symbolSize(28)
                        .foregroundStyle(accent)
                    }
                }
                .chartYScale(domain: 0...Double(maxValue))
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(Color.gray.opacity(0.25))
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text("\(intValue)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: true)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 160)
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

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("账号")
                .font(.headline)

            if let user = UserManager.shared.currentUser() {
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.nickname?.isEmpty == false ? (user.nickname ?? "") : "已登录")
                        .font(.body.weight(.semibold))
                    if let phone = user.phone, !phone.isEmpty {
                        Text(phone)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Button(role: .destructive) {
                NotificationCenter.default.post(name: .readingAppLogoutRequested, object: nil)
            } label: {
                Text("退出登录")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.86, green: 0.24, blue: 0.24))
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
    
    private func parseDate(_ raw: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw) ?? Date()
    }
}

#Preview {
    StatsView()
}
