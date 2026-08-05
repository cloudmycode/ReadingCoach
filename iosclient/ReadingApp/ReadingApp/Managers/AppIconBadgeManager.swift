import UIKit
import UserNotifications

/// 根据今日待复习数量更新应用图标角标。
/// 说明：系统桌面角标只能显示数字，无法做成无数字的纯红点。
@MainActor
enum AppIconBadgeManager {
    static func refresh(pendingCount: Int) async {
        let allowed = await ensureBadgeAuthorizationIfNeeded()
        let count = max(0, pendingCount)
        guard allowed else {
            #if DEBUG
            print("[AppIconBadge] 无角标权限，跳过设置 count=\(count)")
            #endif
            return
        }

        do {
            if #available(iOS 16.0, *) {
                try await UNUserNotificationCenter.current().setBadgeCount(count)
            } else {
                UIApplication.shared.applicationIconBadgeNumber = count
            }
            #if DEBUG
            print("[AppIconBadge] 已设置角标 count=\(count)")
            #endif
        } catch {
            #if DEBUG
            print("[AppIconBadge] 设置角标失败: \(error.localizedDescription)")
            #endif
            // 部分系统版本上，即使新 API 失败，旧接口仍可能生效。
            UIApplication.shared.applicationIconBadgeNumber = count
        }
    }

    static func clear() async {
        await refresh(pendingCount: 0)
    }

    /// 从前台回到应用或登录后，按服务端今日待复习数刷新角标。
    static func refreshFromServer() async {
        guard UserManager.shared.currentUser() != nil else {
            await clear()
            return
        }
        do {
            let summary = try await ReviewAPI.shared.todaySummary()
            #if DEBUG
            print("[AppIconBadge] 今日待复习 dueCount=\(summary.dueCount)")
            #endif
            await refresh(pendingCount: summary.dueCount)
        } catch {
            #if DEBUG
            print("[AppIconBadge] 拉取今日任务失败: \(error.localizedDescription)")
            #endif
        }
    }

    @discardableResult
    private static func ensureBadgeAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()

        if settings.authorizationStatus == .notDetermined {
            // 仅申请 badge 时，部分系统版本不会弹出授权框，导致一直无法写角标。
            // 一并申请 alert，确保出现系统授权弹窗；用户仍可在设置里关掉横幅。
            _ = try? await center.requestAuthorization(options: [.badge, .alert])
            settings = await center.notificationSettings()
        }

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            if settings.badgeSetting == .disabled {
                #if DEBUG
                print("[AppIconBadge] 通知已授权，但角标开关被关闭")
                #endif
                return false
            }
            return true
        case .denied:
            #if DEBUG
            print("[AppIconBadge] 用户拒绝了通知权限，无法显示桌面角标")
            #endif
            return false
        case .notDetermined:
            return false
        @unknown default:
            return false
        }
    }
}
