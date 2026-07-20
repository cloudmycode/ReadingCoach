import AVFoundation
import Combine
import Speech

enum SpeechInputError: LocalizedError {
    case speechPermissionDenied
    case microphonePermissionDenied
    case recognizerUnavailable
    case audioInputUnavailable

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
        }
    }
}

@MainActor
final class SpeechInputManager: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var isStarting = false
    @Published private(set) var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInstalledAudioTap = false

    func startRecording() async throws {
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        cancelRecording()
        try await authorizeIfNeeded()
        guard speechRecognizer?.isAvailable == true else {
            throw SpeechInputError.recognizerUnavailable
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audioSession.setActive(true, options: [.notifyOthersOnDeactivation])

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            cleanUpAudioSession()
            throw SpeechInputError.audioInputUnavailable
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        hasInstalledAudioTap = true

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognition(result: result, error: error)
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

    func cancelRecording() {
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
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            throw SpeechInputError.speechPermissionDenied
        }

        let microphoneAllowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
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
                finishRecognition()
                return
            }
        }

        if error != nil {
            if isRecording {
                errorMessage = "语音识别失败，请重试"
            }
            finishRecognition()
        }
    }

    private func finishRecognition() {
        stopAudioCapture()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        cleanUpAudioSession()
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
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
