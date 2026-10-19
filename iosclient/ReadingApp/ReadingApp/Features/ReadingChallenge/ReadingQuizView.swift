import SwiftUI

struct ReadingQuizView: View {
    @ObservedObject var store: ReadingQuizStore
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var speech = SpeechInputManager()
    @State private var showArticle = false
    @State private var showMissing = false
    @State private var recordingIndex: Int?
    @State private var answerBeforeSpeech = ""
    @State private var currentTranscript = ""
    @State private var recordingTask: Task<Void, Never>?
    @FocusState private var focusedQuestion: Int?

    var body: some View {
        Group {
            if let result = store.attempt, result.isResult {
                QuizResultView(store: store, result: result)
            } else if let attempt = store.attempt {
                pendingPage(attempt)
            } else {
                questionPage
            }
        }
        .navigationTitle(store.attempt?.isResult != true ? "阅读小测试" : "本次阅读结果")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { quizHeader }
        .sheet(isPresented: $showArticle) {
            VStack(spacing: 0) {
                QuizWindowHeader(title: "英文原文", closeLabel: "关闭原文，继续答题") {
                    showArticle = false
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(store.title).font(.title.bold())
                        Text(store.articleText).font(.title3).lineSpacing(8)
                    }.padding(24)
                }
            }
            .background(Color(.systemBackground))
        }
        .task(id: "\(scenePhase == .active)-\(store.attempt?.id ?? 0)") { if scenePhase == .active { await store.watch() } }
        .onChange(of: speech.transcript) { _, text in
            guard let index = recordingIndex, !text.isEmpty else { return }
            currentTranscript = text
            store.answer([answerBeforeSpeech, text].filter { !$0.isEmpty }.joined(separator: " "), at: index)
        }
        .onChange(of: speech.errorMessage) { _, message in
            if let message { store.errorMessage = message }
        }
        .onChange(of: speech.autoSubmitTick) { _, _ in
            // Speech completion saves the transcript only; it must never submit the quiz.
            recordingIndex = nil
        }
        .onDisappear {
            stopSpeech()
        }
    }

    private func pendingPage(_ attempt: ReadingAttempt) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                if attempt.isPending { ProgressView().controlSize(.large) }
                else { Image(systemName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate").font(.largeTitle).foregroundStyle(.orange) }
                Text(attempt.isPending ? "正在认真批改你的答案" : "批改暂时未完成").font(.title2.bold())
                Text(store.statusText).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
                if attempt.status == "failed" {
                    Button("重试批改") { Task { await store.retrySystemTask() } }.buttonStyle(.borderedProminent).disabled(store.isSubmitting)
                } else {
                    Button("刷新结果") { Task { await store.pollAttempt() } }
                }
                Text("答案已经保存在服务器，可以放心退出，稍后回来查看。").font(.footnote).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: .infinity)
        }
    }

    private var quizHeader: some View {
        QuizWindowHeader(
            title: store.attempt?.isResult != true ? "阅读小测试" : "本次阅读结果",
            closeLabel: "关闭小测"
        ) {
            stopSpeech()
            focusedQuestion = nil
            if let onClose { onClose() } else { dismiss() }
        }
    }

    private var questionPage: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(store.title).font(.title2.bold())
                        HStack {
                            Text("已回答 \(store.answeredCount) / 5 题").font(.subheadline.bold())
                            Spacer()
                            Text("每题 20 分 · 80 分过关").font(.caption).foregroundStyle(.secondary)
                        }
                        ProgressView(value: Double(store.answeredCount), total: 5)
                        HStack {
                            Label("草稿已自动保存在本机", systemImage: "checkmark.icloud").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("查看原文") { stopSpeech(); focusedQuestion = nil; showArticle = true }.font(.subheadline)
                        }
                    }
                    ForEach(store.questions) { question in
                        questionCard(question).id(question.index)
                    }
                    if store.answersLocked { Text(store.statusText).font(.caption).foregroundStyle(.secondary) }
                    if let error = store.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.orange)
                    }
                    Button {
                        stopSpeech()
                        focusedQuestion = nil
                        if store.emptyIndices.isEmpty { submit() } else { showMissing = true }
                    } label: {
                        HStack {
                            if store.isGrading { ProgressView().tint(.white) }
                            Text(store.isSubmitting ? "提交中…" : (store.answersLocked ? "重试提交" : "提交全部答案")).font(.headline)
                        }.frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isGrading || speech.isStarting || !store.canOpen)
                    .accessibilityIdentifier("submitReadingQuiz")
                    Text("用自己的话表达即可。提交后统一查看结果与解析。")
                        .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .background(Color(.systemBackground))
            .scrollDismissesKeyboard(.interactively)
            .alert("还有题目未回答", isPresented: $showMissing) {
                Button("返回补充", role: .cancel) {
                    if let index = store.emptyIndices.first {
                        withAnimation { proxy.scrollTo(index, anchor: .center) }
                        focusedQuestion = index
                    }
                }
                Button("仍然提交") { submit() }
            } message: {
                Text("第 \(store.emptyIndices.map { String($0 + 1) }.joined(separator: "、")) 题为空。直接提交时，空答将计为 0 分。")
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { focusedQuestion = nil }
                }
            }
        }
    }

    private func questionCard(_ question: ReadingQuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(String(format: "%02d", question.id)).font(.title2.bold()).foregroundStyle(.primary)
                Text(question.kind).font(.subheadline.bold())
                Spacer()
                Text("20 分").font(.caption).foregroundStyle(.secondary)
            }
            Text(question.prompt).font(.headline).fixedSize(horizontal: false, vertical: true)
            if !question.quote.isEmpty {
                Text(question.quote).font(.body).foregroundStyle(.primary)
                    .padding(.leading, 12).frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color(.systemGray4)).frame(width: 2)
                    }
            }
            HStack {
                Label("你的回答", systemImage: "pencil")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if focusedQuestion == question.index {
                    Text("正在输入").font(.caption).foregroundStyle(.blue)
                }
            }
            TextField("点击输入答案…", text: Binding(
                get: { store.answers[question.index] },
                set: { store.answer($0, at: question.index) }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundStyle(.primary)
            .tint(.blue)
            .lineLimit(3...8)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        focusedQuestion == question.index ? Color.blue : Color(.systemGray3),
                        lineWidth: focusedQuestion == question.index ? 2 : 1
                    )
                    .allowsHitTesting(false)
            }
            .focused($focusedQuestion, equals: question.index)
            .disabled(store.answersLocked || speech.isStarting || recordingIndex != nil)
            .accessibilityLabel("第 \(question.id) 题答案")
            .accessibilityIdentifier("quizAnswer\(question.id)")
            Button {
                if recordingIndex == question.index { stopSpeech() }
                else { startSpeech(at: question.index) }
            } label: {
                Label(recordingIndex == question.index ? "完成录音" : "语音输入", systemImage: recordingIndex == question.index ? "stop.circle.fill" : "mic")
                    .font(.subheadline)
            }.disabled(store.answersLocked || speech.isStarting)
            if recordingIndex == question.index {
                Text("正在听…识别后可修改，不会自动提交。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func submit() {
        Task { await store.submit() }
    }

    private func startSpeech(at index: Int) {
        stopSpeech()
        focusedQuestion = nil
        answerBeforeSpeech = store.answers[index]
        currentTranscript = ""
        recordingIndex = index
        recordingTask = Task {
            do {
                try await speech.startRecording()
                if Task.isCancelled { speech.cancelRecording() }
            } catch {
                if !Task.isCancelled { store.errorMessage = error.localizedDescription }
                recordingIndex = nil
            }
        }
    }

    private func stopSpeech() {
        // Preserve the final visible transcript before cancellation and never route it to another answer.
        if let index = recordingIndex, !currentTranscript.isEmpty {
            store.answer([answerBeforeSpeech, currentTranscript].filter { !$0.isEmpty }.joined(separator: " "), at: index)
        }
        recordingTask?.cancel()
        recordingTask = nil
        speech.cancelRecording()
        recordingIndex = nil
    }
}

private struct QuizResultView: View {
    @ObservedObject var store: ReadingQuizStore
    @StateObject private var rewards = ReadingChallengeStore()
    let result: ReadingAttempt
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 12) {
                    Image(systemName: result.passed ? "checkmark.seal.fill" : "book.circle.fill")
                        .font(.system(size: 50)).foregroundStyle(result.passed ? .green : .orange)
                    if let score = result.score {
                        Text("\(score) 分").font(.system(size: 54, weight: .bold, design: .rounded))
                    } else {
                        Text("暂未评分").font(.largeTitle.bold())
                    }
                    Text(result.score == nil ? "部分答案仍无法可靠判断" : (result.passed ? "阅读过关，继续积累！" : "再读一读，你会理解得更好")).font(.title3.bold())
                    Text(result.score == nil ? "这次不会记为零分或达标，可以调整答案后重新提交。" : "\(result.results.filter { $0.verdict == "correct" }.count) / 5 题正确")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("提交日期：\(result.submittedOn)").font(.caption).foregroundStyle(.secondary)
                    if rewards.cycle != nil {
                        Text("本周期累计达标 \(rewards.completedDays) 天 · \(rewards.tier.title)").font(.subheadline).foregroundStyle(.blue)
                        Text("每天最多达标一次，同一篇文章不重复计入奖励。").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity).challengeCard()
                ReadingLoadStatus(store: rewards)
                ForEach(store.questions) { question in
                    let verdict = result.results.first { $0.questionID == question.id }
                    let answer = result.answers.first { $0.questionID == question.id }?.answer ?? ""
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("\(question.id). \(question.kind)").font(.headline)
                            Spacer()
                            Text(verdict?.verdict == "correct" ? "20 分" : (verdict?.verdict == "incorrect" ? "0 分" : "待确认"))
                                .foregroundStyle(verdict?.verdict == "correct" ? .green : .orange)
                        }
                        Text(question.prompt).font(.subheadline)
                        Text("你的回答").font(.caption.bold()).foregroundStyle(.secondary)
                        Text(answer.isEmpty ? "未作答" : answer)
                        Divider()
                        Text("批改反馈").font(.caption.bold()).foregroundStyle(.blue)
                        Text(verdict?.feedback ?? "暂无反馈").font(.subheadline)
                    }.challengeCard()
                }
                NavigationLink { ReadingRewardsView(store: rewards) } label: {
                    Text("查看七星奖励进度").frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent)
                Button(result.passed ? "再练一次" : "补学后重新挑战") { store.retry() }
                    .frame(maxWidth: .infinity).buttonStyle(.bordered)
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(Color(.systemGroupedBackground))
            .task { await rewards.refresh() }
    }
}

/// Matches the plain gray xmark in the article's sentence explanation panel.
private struct QuizWindowHeader: View {
    let title: String
    let closeLabel: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(red: 0.14, green: 0.18, blue: 0.27))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.57, green: 0.64, blue: 0.75))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(closeLabel)
            .accessibilityIdentifier(closeLabel == "关闭小测" ? "closeReadingQuiz" : "closeQuizArticle")
        }
        .padding(.leading, 24)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
    }
}
