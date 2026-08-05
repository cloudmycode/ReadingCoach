//
//  ContentView.swift
//  ReadingApp
//
//  Created by wang on 2025/11/26.
//

import SwiftUI
import Combine

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var loginViewModel = LoginViewModel()
    @State private var isLoggedIn: Bool = false
    @State private var activeUserId: String?

    var body: some View {
        Group {
            if isLoggedIn {
                MainSelectionView()
                    .id(activeUserId ?? "logged-in")
            } else {
                LoginView()
                    .environmentObject(loginViewModel)
            }
        }
        .onAppear {
            checkLoginStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, isLoggedIn else { return }
            Task {
                await AppIconBadgeManager.refreshFromServer()
            }
        }
        .onChange(of: isLoggedIn) { _, loggedIn in
            if loggedIn {
                Task {
                    await AppIconBadgeManager.refreshFromServer()
                }
            } else {
                Task {
                    await AppIconBadgeManager.clear()
                }
            }
        }
        .onReceive(loginViewModel.$loginSuccess.removeDuplicates()) { success in
            guard success else { return }
            activeUserId = UserManager.shared.currentUserId()
            withAnimation(.easeInOut) {
                isLoggedIn = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NetworkManager.tokenExpiredNotification)) { _ in
            handleTokenExpired()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readingAppLogoutRequested)) { _ in
            handleManualLogout()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readingAppAddAccountRequested)) { _ in
            handleAddAccount()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readingAppReauthRequested)) { notification in
            let phone = notification.userInfo?["phone"] as? String ?? ""
            handleReauth(phone: phone)
        }
        .onReceive(NotificationCenter.default.publisher(for: .userDidSwitch)) { _ in
            activeUserId = UserManager.shared.currentUserId()
            Task {
                await AppIconBadgeManager.refreshFromServer()
            }
        }
    }

    private func checkLoginStatus() {
        if let user = UserManager.shared.currentUser(),
           !UserManager.shared.isTokenExpired(user: user) {
            UserScopedStorage.activateCurrentUserScope()
            activeUserId = user.id
            isLoggedIn = true
            Task {
                await AppIconBadgeManager.refreshFromServer()
            }
        } else {
            if UserManager.shared.currentUser() != nil {
                UserManager.shared.logoutCurrentUser()
            } else {
                UserScopedStorage.activateCurrentUserScope()
            }
            activeUserId = nil
            isLoggedIn = false
            Task {
                await AppIconBadgeManager.clear()
            }
        }
    }

    private func handleTokenExpired() {
        activeUserId = nil
        withAnimation(.easeInOut) {
            isLoggedIn = false
        }
        loginViewModel.loginSuccess = false
    }

    private func handleManualLogout() {
        UserManager.shared.logoutCurrentUser()
        activeUserId = nil
        withAnimation(.easeInOut) {
            isLoggedIn = false
        }
        loginViewModel.loginSuccess = false
    }

    private func handleAddAccount() {
        UserManager.shared.logoutCurrentUser()
        activeUserId = nil
        loginViewModel.prepareForNewAccount()
        withAnimation(.easeInOut) {
            isLoggedIn = false
        }
    }

    private func handleReauth(phone: String) {
        UserManager.shared.logoutCurrentUser()
        activeUserId = nil
        loginViewModel.prepareForReauth(phone: phone)
        withAnimation(.easeInOut) {
            isLoggedIn = false
        }
    }
}

#Preview {
    ContentView()
}
