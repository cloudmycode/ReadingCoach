import SwiftUI

/// Shown only before the first usable list, so a pending request never looks like an empty list.
struct ListLoadingView: View {
    let isLoading: Bool
    let errorMessage: String?
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            if let errorMessage, !isLoading {
                Image(systemName: "wifi.exclamationmark").font(.title2).foregroundStyle(.secondary)
                Text("暂时无法加载").font(.headline)
                Text(errorMessage).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("重新加载", action: retry)
            } else {
                ProgressView("正在加载…")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}
