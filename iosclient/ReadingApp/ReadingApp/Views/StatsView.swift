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
                    StatsTrendChartCard(
                        title: "文章趋势",
                        subtitle: "近 14 天每日新读篇数",
                        unit: "篇",
                        accent: Color(red: 0.20, green: 0.49, blue: 0.93),
                        values: viewModel.stats.recentDays.map {
                            StatsTrendPoint(date: $0.date, count: $0.newArticles)
                        },
                        isLoading: viewModel.isLoading
                    )
                    StatsTrendChartCard(
                        title: "单词趋势",
                        subtitle: "近 14 天每日复习词数",
                        unit: "词",
                        accent: Color(red: 0.64, green: 0.42, blue: 0.90),
                        values: viewModel.stats.recentDays.map {
                            StatsTrendPoint(date: $0.date, count: $0.reviewCount)
                        },
                        isLoading: viewModel.isLoading
                    )
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
}

private struct StatsTrendPoint: Identifiable {
    let date: String
    let count: Int
    var id: String { date }

    var parsedDate: Date {
        Self.dateFormatter.date(from: date) ?? Date()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct StatsTrendChartCard: View {
    let title: String
    let subtitle: String
    let unit: String
    let accent: Color
    let values: [StatsTrendPoint]
    let isLoading: Bool

    @State private var selectedDate: Date?

    private var total: Int {
        values.reduce(0) { $0 + $1.count }
    }

    private var maxValue: Int {
        max(values.map(\.count).max() ?? 0, 1)
    }

    private var selectedPoint: StatsTrendPoint? {
        guard let selectedDate else { return nil }
        return values.min { lhs, rhs in
            abs(lhs.parsedDate.timeIntervalSince(selectedDate)) < abs(rhs.parsedDate.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let selectedPoint {
                    Text("\(shortDate(selectedPoint.date)) · \(selectedPoint.count) \(unit)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(accent)
                } else {
                    Text("合计 \(total) \(unit)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(accent)
                }
            }

            if values.isEmpty && !isLoading {
                Text("还没有学习记录，先去拍一篇阅读文章吧。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
            } else {
                Chart {
                    ForEach(values) { item in
                        LineMark(
                            x: .value("日期", item.parsedDate, unit: .day),
                            y: .value(unit, item.count)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                        AreaMark(
                            x: .value("日期", item.parsedDate, unit: .day),
                            y: .value(unit, item.count)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [accent.opacity(0.28), accent.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        PointMark(
                            x: .value("日期", item.parsedDate, unit: .day),
                            y: .value(unit, item.count)
                        )
                        .symbolSize(selectedPoint?.id == item.id ? 64 : 36)
                        .foregroundStyle(accent)
                    }

                    if let selectedPoint {
                        RuleMark(x: .value("选中", selectedPoint.parsedDate, unit: .day))
                            .foregroundStyle(accent.opacity(0.25))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .top, spacing: 6) {
                                Text("\(selectedPoint.count)")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(accent)
                                    .clipShape(Capsule())
                            }
                    }
                }
                .chartYScale(domain: 0...(Double(maxValue) * 1.25))
                .chartXSelection(value: $selectedDate)
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
                .frame(height: 180)
                .sensoryFeedback(.selection, trigger: selectedPoint?.id)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.95))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 5)
    }

    private func shortDate(_ raw: String) -> String {
        let parts = raw.split(separator: "-")
        guard parts.count == 3 else { return raw }
        return "\(parts[1])/\(parts[2])"
    }
}

#Preview {
    StatsView()
}
