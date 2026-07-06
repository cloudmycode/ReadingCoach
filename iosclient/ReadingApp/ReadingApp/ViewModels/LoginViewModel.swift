//
//  LoginViewModel.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/26.
//

import Foundation
import Combine

@MainActor
final class LoginViewModel: ObservableObject {
    enum AgreementType: Identifiable {
        case user
        case privacy

        var id: String {
            switch self {
            case .user: return "user"
            case .privacy: return "privacy"
            }
        }

        var title: String {
            switch self {
            case .user:
                return "用户协议"
            case .privacy:
                return "隐私政策"
            }
        }

        var content: String {
            switch self {
            case .user:
                return "这里是用户协议的内容..."
            case .privacy:
                return "这里是隐私政策的内容..."
            }
        }
    }

    @Published var phoneNumber: String = ""
    @Published var verificationCode: String = ""
    @Published var agreedToTerms: Bool = false
    @Published var countdown: Int = 0
    @Published var isLoading: Bool = false
    @Published var toastMessage: String?
    @Published var showHistory: Bool = false
    @Published var phoneHistory: [String] = []
    @Published var agreementToShow: AgreementType?
    @Published var loginSuccess: Bool = false

    private var countdownTimer: AnyCancellable?
    private var toastDismissWorkItem: DispatchWorkItem?

    init() {
        loadPhoneHistory()
    }

    var canRequestCode: Bool {
        phoneNumber.count == 11 && countdown == 0
    }

    var canLogin: Bool {
        phoneNumber.count == 11 && verificationCode.count == 6 && agreedToTerms
    }

    var codeButtonText: String {
        countdown > 0 ? "\(countdown)s" : "获取验证码"
    }

    var filteredPhoneHistory: [String] {
        guard !phoneHistory.isEmpty else { return [] }
        let input = phoneNumber
        guard !input.isEmpty else { return phoneHistory }

        return phoneHistory.filter { phone in
            guard phone.count > input.count else { return false }
            return phone.hasPrefix(input)
        }
    }

    var shouldShowHistory: Bool {
        showHistory && !filteredPhoneHistory.isEmpty
    }

    func onPhoneChanged(_ value: String) {
        let digits = value.filter { $0.isNumber }
        if phoneNumber != digits {
            phoneNumber = String(digits.prefix(11))
        }
        updateHistoryVisibility()
    }

    func onCodeChanged(_ value: String) {
        let digits = value.filter { $0.isNumber }
        if verificationCode != digits {
            verificationCode = String(digits.prefix(6))
        }
    }

    func toggleAgreement() {
        agreedToTerms.toggle()
    }

    func loadPhoneHistory() {
        phoneHistory = UserManager.shared.phoneHistory()
    }

    func showHistoryList() {
        showHistory = !phoneHistory.isEmpty
    }

    func hideHistoryListWithDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.showHistory = false
        }
    }

    func selectPhone(_ phone: String) {
        phoneNumber = phone
        showHistory = false
    }

    func removePhoneFromHistory(_ phone: String) {
        UserManager.shared.removePhoneFromHistory(phone)
        loadPhoneHistory()
        updateHistoryVisibility()
    }

    func sendCode() {
        guard canRequestCode, !isLoading else { return }
        Task { await performSendCode() }
    }

    func login() {
        guard canLogin, !isLoading else { return }
        Task { await performLogin() }
    }

    private func performSendCode() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await AuthAPI.shared.sendCode(phone: phoneNumber)
            showToast("验证码已发送")
            startCountdown()
            if let debug = response.debugCode {
                verificationCode = debug
            }
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func performLogin() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await AuthAPI.shared.login(
                phone: phoneNumber,
                code: verificationCode,
                agreePolicy: agreedToTerms
            )
            try UserManager.shared.saveUser(info: result.userInfo, token: result.token, phone: phoneNumber)
            UserManager.shared.addPhoneToHistory(phoneNumber)
            loadPhoneHistory()
            toastMessage = nil
            // 延迟设置登录成功，让用户看到提示
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.loginSuccess = true
            }
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func startCountdown() {
        countdown = 60
        countdownTimer?.cancel()
        countdownTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if countdown > 0 {
                    countdown -= 1
                }
                if countdown <= 0 {
                    countdownTimer?.cancel()
                    countdownTimer = nil
                }
            }
    }

    private func updateHistoryVisibility() {
        if phoneNumber.isEmpty {
            showHistory = !phoneHistory.isEmpty
        } else {
            showHistory = filteredPhoneHistory.count > 0
        }
    }

    private func showToast(_ message: String, duration: TimeInterval = 2.0) {
        toastDismissWorkItem?.cancel()
        toastMessage = message

        let workItem = DispatchWorkItem { [weak self] in
            self?.toastMessage = nil
        }
        toastDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }
}

