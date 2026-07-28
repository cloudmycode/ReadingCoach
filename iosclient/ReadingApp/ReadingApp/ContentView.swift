//
//  ContentView.swift
//  ReadingApp
//
//  Created by wang on 2025/11/26.
//

import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var loginViewModel = LoginViewModel()
    @State private var isLoggedIn: Bool = false
    
    var body: some View {
        Group {
            if isLoggedIn {
                MainSelectionView()
            } else {
                LoginView()
                    .environmentObject(loginViewModel)
            }
        }
        .onAppear {
            checkLoginStatus()
        }
        .onReceive(loginViewModel.$loginSuccess.removeDuplicates()) { success in
            guard success else { return }
            withAnimation(.easeInOut) {
                isLoggedIn = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NetworkManager.tokenExpiredNotification)) { _ in
            // 令牌过期，自动跳转到登录页
            handleTokenExpired()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readingAppLogoutRequested)) { _ in
            handleManualLogout()
        }
    }
    
    private func checkLoginStatus() {
        // 检查是否有已登录用户且令牌未过期
        if let user = UserManager.shared.currentUser(),
           !UserManager.shared.isTokenExpired(user: user) {
            UserScopedStorage.activateCurrentUserScope()
            isLoggedIn = true
        } else {
            // 如果令牌已过期，清除用户
            if UserManager.shared.currentUser() != nil {
                UserManager.shared.logout()
            } else {
                UserScopedStorage.activateCurrentUserScope()
            }
            isLoggedIn = false
        }
    }
    
    private func handleTokenExpired() {
        // 令牌过期，清除登录状态并跳转到登录页
        withAnimation(.easeInOut) {
            isLoggedIn = false
        }
        // 重置登录视图模型状态
        loginViewModel.loginSuccess = false
    }

    private func handleManualLogout() {
        UserManager.shared.logout()
        withAnimation(.easeInOut) {
            isLoggedIn = false
        }
        loginViewModel.loginSuccess = false
    }
}

#Preview {
    ContentView()
}
