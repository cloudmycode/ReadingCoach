import AVFoundation
import Combine
import Speech

enum SpeechInputError: LocalizedError {
    case speechPermissionDenied
    case microphonePermissionDenied
    case recognizerUnavailable
    case audioInputUnavailable
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .speechPermissionDenied:
            return "请在系统设置中允许语音识别权限"
        case .microphonePermissionDenied:
            return "请在系统设置中允许麦克风权限"
        case .recognizerUnavailable:
            return "语音识别暂时不可用，请稍后重试"
        case .audioInputUnavailable:
            return "无法启动麦克风，请检查设备音频输入"
        case .recognitionFailed:
            return "跟读语音识别未完成，请检查网络后重试当前句"
        }
    }
}

@MainActor
final class SpeechInputManager: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var isStarting = false
    @Published private(set) var errorMessage: String?
    /// 识别正常结束后递增；取消录音不会触发。订阅方可用于自动发送。
    @Published private(set) var autoSubmitTick = 0

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInstalledAudioTap = false
    private var ownsAudioSession = false
    private var recognitionSessionID = UUID()
    private var recognitionFailed = false

    init(localeIdentifier: String = "zh-CN") {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
    }

    /// Ask before the demonstration, so permission dialogs don't consume repetition time.
    func prepareRecording() async throws {
        try await authorizeIfNeeded()
        try Task.checkCancellation()
        guard speechRecognizer?.isAvailable == true else {
            throw SpeechInputError.recognizerUnavailable
        }
    }

    func startRecording(allowsPlayback: Bool = false) async throws {
        guard !isStarting else { throw CancellationError() }
        isStarting = true
        defer { isStarting = false }
        cancelRecording()
        let sessionID = recognitionSessionID
        try await prepareRecording()
        guard recognitionSessionID == sessionID else { throw CancellationError() }
        transcript = ""
        errorMessage = nil
        recognitionFailed = false

        let audioSession = AVAudioSession.sharedInstance()
        if allowsPlayback {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
        } else {
            try audioSession.setCategory(.record, mode: .measurement)
        }
        try audioSession.setActive(true, options: [.notifyOthersOnDeactivation])
        ownsAudioSession = true

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            cancelRecording()
            throw SpeechInputError.audioInputUnavailable
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        hasInstalledAudioTap = true

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.recognitionSessionID == sessionID else { return }
                self.handleRecognition(result: result, error: error)
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            transcript = ""
            errorMessage = nil
            isRecording = true
        } catch {
            cancelRecording()
            throw SpeechInputError.audioInputUnavailable
        }
    }

    func stopRecording() {
        guard recognitionRequest != nil else { return }
        stopAudioCapture()
        recognitionRequest?.endAudio()
        isRecording = false
    }

    /// Stop the microphone now; allow at most two seconds for the final transcript.
    /// A late callback from this session must never affect the next sentence.
    func finishRecording() async throws -> String {
        let sessionID = recognitionSessionID
        defer {
            if recognitionSessionID == sessionID { cancelRecording() }
        }
        stopRecording()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while recognitionRequest != nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
            guard recognitionSessionID == sessionID else { throw CancellationError() }
        }
        try Task.checkCancellation()
        guard !recognitionFailed else { throw SpeechInputError.recognitionFailed }
        // Partial text is usable as an approximate matching score if finalization times out.
        // No response at all is an error, not a fabricated low score.
        if recognitionRequest != nil && transcript.isEmpty { throw SpeechInputError.recognitionFailed }
        return transcript
    }

    func cancelRecording() {
        recognitionSessionID = UUID()
        stopAudioCapture()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        cleanUpAudioSession()
    }

    func clearError() {
        errorMessage = nil
    }

    private func authorizeIfNeeded() async throws {
        var speechStatus = SFSpeechRecognizer.authorizationStatus()
        if speechStatus == .notDetermined {
            speechStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        }
        guard speechStatus == .authorized else {
            throw SpeechInputError.speechPermissionDenied
        }

        try Task.checkCancellation()
        // Once granted, don't cross two asynchronous permission callbacks between sentences.
        var microphoneAllowed = AVAudioApplication.shared.recordPermission == .granted
        if AVAudioApplication.shared.recordPermission == .undetermined {
            microphoneAllowed = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
        }
        guard microphoneAllowed else {
            throw SpeechInputError.microphonePermissionDenied
        }
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        guard recognitionRequest != nil else { return }
        if let result {
            transcript = result.bestTranscription.formattedString
            if result.isFinal {
                finishRecognition(autoSubmit: true)
                return
            }
        }

        if error != nil {
            recognitionFailed = true
            // 仍在录时出错：提示重试，不自动发送。
            // 用户已点停止后收尾出错：用已有文稿自动发送。
            let wasActivelyRecording = isRecording
            if wasActivelyRecording {
                errorMessage = "语音识别失败，请重试"
            }
            finishRecognition(autoSubmit: !wasActivelyRecording)
        }
    }

    private func finishRecognition(autoSubmit: Bool) {
        stopAudioCapture()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        cleanUpAudioSession()
        let hasText = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if autoSubmit, hasText {
            autoSubmitTick += 1
        }
    }

    private func stopAudioCapture() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInstalledAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledAudioTap = false
        }
    }

    private func cleanUpAudioSession() {
        // AVAudioSession is process-wide. Sentence changes also call
        // cancelRecording() to reset the panel, so only deactivate the session
        // when this manager actually activated it for microphone capture.
        guard ownsAudioSession else { return }
        ownsAudioSession = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
