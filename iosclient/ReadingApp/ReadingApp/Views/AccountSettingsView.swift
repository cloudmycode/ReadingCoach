//
//  AccountSettingsView.swift
//  ReadingApp
//

import SwiftUI

struct AccountSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var savedUsers: [StoredUser] = []
    @State private var toastMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let current = UserManager.shared.currentUser() {
                    Section("当前账号") {
                        accountRow(current, isCurrent: true)
                    }
                }

                let others = savedUsers.filter { $0.id != UserManager.shared.currentUserId() }
                if !others.isEmpty {
                    Section("切换账号") {
                        ForEach(others) { user in
                            Button {
                                switchTo(user)
                            } label: {
                                accountRow(user, isCurrent: false)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        NotificationCenter.default.post(name: .readingAppAddAccountRequested, object: nil)
                        dismiss()
                    } label: {
                        Label("添加账号", systemImage: "person.badge.plus")
                    }

                    Button(role: .destructive) {
                        NotificationCenter.default.post(name: .readingAppLogoutRequested, object: nil)
                        dismiss()
                    } label: {
                        Label("退出当前账号", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                reloadUsers()
            }
            .overlay(alignment: .bottom) {
                if let toastMessage {
                    Text(toastMessage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.78))
                        .clipShape(Capsule())
                        .padding(.bottom, 24)
                        .onTapGesture { self.toastMessage = nil }
                        .task(id: toastMessage) {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            if self.toastMessage == toastMessage {
                                self.toastMessage = nil
                            }
                        }
                }
            }
        }
    }

    private func reloadUsers() {
        savedUsers = UserManager.shared.savedUsers()
    }

    private func switchTo(_ user: StoredUser) {
        switch UserManager.shared.switchUser(id: user.id) {
        case .success:
            toastMessage = "已切换到 \(displayName(for: user))"
            reloadUsers()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                dismiss()
            }
        case .needsReauth(let phone):
            NotificationCenter.default.post(
                name: .readingAppReauthRequested,
                object: nil,
                userInfo: ["phone": phone]
            )
            dismiss()
        case .userNotFound:
            toastMessage = "账号不存在，请重新登录"
            reloadUsers()
        }
    }

    private func accountRow(_ user: StoredUser, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(Color(red: 0.20, green: 0.49, blue: 0.93))

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName(for: user))
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
                if let phone = user.phone, !phone.isEmpty {
                    Text(maskPhone(phone))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(red: 0.04, green: 0.65, blue: 0.35))
            } else if UserManager.shared.isTokenExpired(user: user) {
                Text("需重新登录")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    private func displayName(for user: StoredUser) -> String {
        if let nickname = user.nickname, !nickname.isEmpty {
            return nickname
        }
        if let phone = user.phone, !phone.isEmpty {
            return maskPhone(phone)
        }
        return "用户 \(user.id)"
    }

    private func maskPhone(_ phone: String) -> String {
        guard phone.count >= 7 else { return phone }
        let prefix = phone.prefix(3)
        let suffix = phone.suffix(4)
        return "\(prefix)****\(suffix)"
    }
}

extension Notification.Name {
    static let readingAppReauthRequested = Notification.Name("ReadingAppReauthRequested")
}

#Preview {
    AccountSettingsView()
}
