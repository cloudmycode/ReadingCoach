//
//  LoginView.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/26.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var viewModel: LoginViewModel
    @FocusState private var focusedField: Field?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private enum Field {
        case phone
        case code
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.94, green: 0.96, blue: 1), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            GeometryReader { geometry in
                ScrollView {
                    VStack {
                        VStack(spacing: 24) {
                            header
                            form
                        }
                        .padding(24)
                        .frame(maxWidth: loginCardWidth(for: geometry.size.width))
                        .background(
                            RoundedRectangle(cornerRadius: isPadLayout ? 28 : 0, style: .continuous)
                                .fill(Color.white.opacity(isPadLayout ? 0.94 : 0.001))
                        )
                        .overlay {
                            if isPadLayout {
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .stroke(Color(red: 0.9, green: 0.93, blue: 0.98), lineWidth: 1)
                            }
                        }
                        .shadow(color: Color.black.opacity(isPadLayout ? 0.06 : 0), radius: 24, x: 0, y: 16)
                        .padding(.horizontal, isPadLayout ? 32 : 0)
                        .padding(.top, isPadLayout ? max((geometry.size.height - 520) * 0.32, 40) : 0)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if viewModel.isLoading {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                ProgressView("处理中...")
                    .padding()
                    .background(Color.white)
                    .cornerRadius(10)
            }
        }
        .animation(.easeInOut, value: viewModel.countdown)
        .overlay(alignment: .top) {
            Group {
                toastOverlay
            }
            .animation(.easeInOut, value: viewModel.toastMessage)
        }
        .sheet(item: $viewModel.agreementToShow) { type in
            agreementSheet(type: type)
        }
    }

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func loginCardWidth(for availableWidth: CGFloat) -> CGFloat {
        guard isPadLayout else { return .infinity }
        return min(availableWidth - 64, 440)
    }

    private var header: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Text("ReadingCoach")
                    .font(.largeTitle.bold())
                Text("拍照导入英语阅读，逐句理解并反复跟读。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    private var form: some View {
        VStack(spacing: 32) {
            phoneInput
            codeInput
            agreementSection
            loginButton
        }
        .padding(.vertical, 16)
    }

    private var phoneInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("手机号码")
                .font(.headline)
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    HStack {
                        TextField("请输入手机号码", text: $viewModel.phoneNumber)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .phone)
                            .onChange(of: viewModel.phoneNumber) { _, newValue in
                                viewModel.onPhoneChanged(newValue)
                            }
                            .onTapGesture {
                                viewModel.showHistoryList()
                            }
                            .padding()
                        Image(systemName: "phone")
                            .foregroundColor(.gray)
                            .padding(.trailing, 12)
                    }
                    .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1.5))
                    .background(Color.white.cornerRadius(12))
                }

                if viewModel.shouldShowHistory && focusedField == .phone {
                    VStack(spacing: 0) {
                        ForEach(viewModel.filteredPhoneHistory, id: \.self) { phone in
                            HStack {
                                Button {
                                    viewModel.selectPhone(phone)
                                    focusedField = .code
                                } label: {
                                    Text(phone)
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Button {
                                    viewModel.removePhoneFromHistory(phone)
                                } label: {
                                    Image(systemName: "xmark")
                                        .foregroundColor(.gray)
                                }
                                .padding(.leading, 8)
                            }
                            .padding()
                            .background(Color.white)
                            .overlay(Divider(), alignment: .bottom)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            .background(Color.white.cornerRadius(12))
                    )
                    .padding(.top, 60)
                }
            }
            .onChange(of: focusedField) { _, newValue in
                if newValue != .phone {
                    viewModel.hideHistoryListWithDelay()
                }
            }
        }
    }

    private var codeInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("验证码")
                .font(.headline)
            HStack {
                TextField("请输入验证码", text: $viewModel.verificationCode)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .code)
                    .onChange(of: viewModel.verificationCode) { _, newValue in
                        viewModel.onCodeChanged(newValue)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1.5))

                Button(action: viewModel.sendCode) {
                    Text(viewModel.codeButtonText)
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(viewModel.canRequestCode ? Color(red: 0.9, green: 0.95, blue: 1) : Color.gray.opacity(0.1))
                        .foregroundColor(viewModel.canRequestCode ? Color(red: 0.26, green: 0.52, blue: 0.96) : .gray)
                        .cornerRadius(10)
                }
                .disabled(!viewModel.canRequestCode)
            }
        }
    }

    private var agreementSection: some View {
        HStack(spacing: 4) {
            Button(action: viewModel.toggleAgreement) {
                Image(systemName: viewModel.agreedToTerms ? "checkmark.square.fill" : "square")
                    .foregroundColor(viewModel.agreedToTerms ? .blue : .gray)
                    .font(.title3)
            }

            Text("我已阅读并同意")
                .foregroundColor(.secondary)

            Button {
                viewModel.agreementToShow = .user
            } label: {
                Text("《用户协议》")
                    .foregroundColor(.blue)
            }

            Text("和")
                .foregroundColor(.secondary)

            Button {
                viewModel.agreementToShow = .privacy
            } label: {
                Text("《隐私政策》")
                    .foregroundColor(.blue)
            }
        }
        .font(.subheadline)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loginButton: some View {
        Button(action: viewModel.login) {
            Text("登录")
                .font(.headline.bold())
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.canLogin ? Color(red: 0.26, green: 0.52, blue: 0.96) : Color.gray.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(12)
        }
        .disabled(!viewModel.canLogin)
    }

    private func agreementSheet(type: LoginViewModel.AgreementType) -> some View {
        NavigationView {
            ScrollView {
                Text(type.content)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(type.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") {
                        viewModel.agreementToShow = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let message = viewModel.toastMessage {
            ToastBanner(message: message)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(LoginViewModel())
}

private struct ToastBanner: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.8))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
    }
}
