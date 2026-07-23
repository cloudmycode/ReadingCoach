import SwiftUI

private enum ReviewTaskTab: String, CaseIterable, Identifiable {
    case current
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .current:
            return "当前任务"
        case .completed:
            return "已完成"
        }
    }
}

struct ReviewTasksView: View {
    @ObservedObject var viewModel: ReviewTasksViewModel
    let onOpenArticle: (String, String) -> Void
    let onAddArticle: () -> Void

    @State private var selectedTab: ReviewTaskTab = .current

    var body: some View {
        VStack(spacing: 0) {
            tabHeader
            ScrollView {
                VStack(spacing: 14) {
                    if selectedTab == .current {
                        currentTaskContent
                    } else {
                        completedTaskContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 120)
            }
        }
        .task {
            await viewModel.loadTasks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .reviewTasksDidChange)) { _ in
            Task {
                await viewModel.loadTasks()
            }
        }
    }

    private var tabHeader: some View {
        HStack(spacing: 12) {
            ForEach(ReviewTaskTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(selectedTab == tab ? .white : Color(red: 0.4, green: 0.48, blue: 0.62))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selectedTab == tab ? Color(red: 0.0, green: 0.4, blue: 1.0) : Color(red: 0.95, green: 0.97, blue: 1.0))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.white)
    }

    @ViewBuilder
    private var currentTaskContent: some View {
        if viewModel.currentTasks.isEmpty && !viewModel.isLoading {
            ReviewTaskEmptyState(
                title: "今天没有新的复习任务",
                message: "前一天新增的文章会在第二天出现在这里。继续新增文章，明天就能开始复习。",
                buttonTitle: "新增文章",
                action: onAddArticle
            )
        } else {
            ForEach(viewModel.currentTasks) { task in
                ReviewTaskCard(
                    title: task.articleTitle,
                    statusText: "完整听完一遍全文后自动完成",
                    accentColor: Color(red: 0.0, green: 0.4, blue: 1.0),
                    metadataText: "计划复习于 \(task.scheduledForDisplay)",
                    wordCountText: "\(task.wordCount) words",
                    buttonTitle: "开始任务",
                    buttonColor: Color(red: 0.0, green: 0.4, blue: 1.0),
                    buttonAction: {
                        onOpenArticle(task.articleId, task.articleTitle)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var completedTaskContent: some View {
        if viewModel.completedTasks.isEmpty && !viewModel.isLoading {
            ReviewTaskEmptyState(
                title: "还没有完成的任务",
                message: "完成整篇文章的连续朗读后，这里会自动记录你的复习成果。",
                buttonTitle: "查看当前任务",
                action: {
                    selectedTab = .current
                }
            )
        } else {
            ForEach(viewModel.completedTasks) { task in
                ReviewTaskCard(
                    title: task.articleTitle,
                    statusText: "复习任务已完成",
                    accentColor: Color(red: 0.02, green: 0.7, blue: 0.44),
                    metadataText: task.completedDisplay,
                    wordCountText: "\(task.wordCount) words",
                    buttonTitle: "再次打开",
                    buttonColor: Color(red: 0.02, green: 0.7, blue: 0.44),
                    buttonAction: {
                        onOpenArticle(task.articleId, task.articleTitle)
                    }
                )
            }
        }
    }
}

private struct ReviewTaskCard: View {
    let title: String
    let statusText: String
    let accentColor: Color
    let metadataText: String
    let wordCountText: String
    let buttonTitle: String
    let buttonColor: Color
    let buttonAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accentColor)
                    .frame(width: 8, height: 48)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
                        .multilineTextAlignment(.leading)

                    Text(statusText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(red: 0.47, green: 0.55, blue: 0.68))
                }
            }

            HStack {
                Text(metadataText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.6, green: 0.67, blue: 0.78))
                Spacer()
                Text(wordCountText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.6, green: 0.67, blue: 0.78))
            }

            Button(action: buttonAction) {
                Text(buttonTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(buttonColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(red: 0.92, green: 0.95, blue: 0.98), lineWidth: 1)
        )
    }
}

private struct ReviewTaskEmptyState: View {
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 80)
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(red: 0.57, green: 0.64, blue: 0.75))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Button(buttonTitle, action: action)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Color(red: 0.0, green: 0.4, blue: 1.0))
                .clipShape(Capsule())
            Spacer(minLength: 80)
        }
        .frame(maxWidth: .infinity)
    }
}

private extension ReviewTaskItem {
    var scheduledForDisplay: String {
        Self.prettyDate(from: scheduledFor) ?? scheduledFor
    }

    var completedDisplay: String {
        if let completedAt, let pretty = Self.prettyDateTime(from: completedAt) {
            return "完成于 \(pretty)"
        }
        return "复习任务已完成"
    }

    static func prettyDate(from string: String) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: string) else { return nil }
        let output = DateFormatter()
        output.dateFormat = "MM/dd"
        return output.string(from: date)
    }

    static func prettyDateTime(from string: String) -> String? {
        let parsers: [ISO8601DateFormatter] = {
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            return [withFractional, plain]
        }()
        let date = parsers.compactMap { $0.date(from: string) }.first
        guard let date else { return nil }
        let output = DateFormatter()
        output.dateFormat = "MM/dd HH:mm"
        return output.string(from: date)
    }
}
