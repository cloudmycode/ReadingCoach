//
//  NetworkManager.swift
//  ReadingApp
//
//  统一的网络请求管理器，处理令牌过期和错误处理
//

import Foundation

/// 网络请求管理器，统一处理认证、错误处理和令牌过期
final class NetworkManager {
    static let shared = NetworkManager()
    
    private let session: URLSession
    private let baseURL: URL
    
    /// 令牌过期通知
    static let tokenExpiredNotification = Notification.Name("TokenExpiredNotification")
    
    init(session: URLSession = .shared) {
        self.session = session
        self.baseURL = AppConfig.API.baseURL
    }
    
    /// 执行网络请求，自动处理认证和错误
    func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        headers: [String: String]? = nil,
        timeout: TimeInterval? = nil,
        responseType: T.Type
    ) async throws -> T {
        // 正确构建 URL，处理查询参数
        let url: URL
        if endpoint.contains("?") {
            // endpoint 包含查询参数，需要分离路径和查询字符串
            let components = endpoint.split(separator: "?", maxSplits: 1)
            let path = String(components[0])
            let queryString = components.count > 1 ? String(components[1]) : nil
            
            // 使用 URLComponents 正确构建 URL
            var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
            // 正确拼接路径（确保以 / 开头，避免重复）
            let basePath = urlComponents.path
            let newPath = basePath.hasSuffix("/") ? basePath + path : basePath + "/" + path
            urlComponents.path = newPath
            
            // 设置查询参数
            if let queryString = queryString {
                urlComponents.query = queryString
            }
            
            guard let finalURL = urlComponents.url else {
                throw APIError.invalidURL
            }
            url = finalURL
        } else {
            // 没有查询参数，直接追加路径
            url = baseURL.appendingPathComponent(endpoint)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let timeout = timeout {
            request.timeoutInterval = timeout
        }
        
        // 只在有请求体时设置 Content-Type
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        // 添加认证令牌
        if let token = UserManager.shared.currentToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // 添加自定义请求头
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // 设置请求体
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.network(NSError(domain: "NetworkError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的响应"]))
            }
            
            // 处理 HTTP 状态码
            switch httpResponse.statusCode {
            case 200..<300:
                // 成功响应
                break
            case 401:
                // 未授权 - 令牌过期或无效
                await handleUnauthorized()
                let message = extractErrorMessage(from: data) ?? "令牌无效，请重新登录"
                throw APIError.server(message: message)
            case 400..<500:
                // 客户端错误
                let message = extractErrorMessage(from: data) ?? "请求错误"
                throw APIError.server(message: message)
            case 500..<600:
                // 服务器错误
                let message = extractErrorMessage(from: data) ?? "服务器错误"
                throw APIError.server(message: message)
            default:
                let message = extractErrorMessage(from: data) ?? "请求失败"
                throw APIError.server(message: message)
            }
            
            // 解析响应数据
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            // 尝试解析为 APIResponse<T>
            if let apiResponse = try? decoder.decode(APIResponse<T>.self, from: data) {
                if let payload = apiResponse.data, apiResponse.success {
                    return payload
                } else {
                    throw APIError.server(message: apiResponse.message)
                }
            }
            
            // 尝试直接解析为 T
            if let direct = try? decoder.decode(T.self, from: data) {
                return direct
            }
            
            throw APIError.decoding
            
        } catch let error as APIError {
            throw error
        } catch {
            if Self.isCancellation(error) {
                throw CancellationError()
            }
            throw APIError.network(error)
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
    
    /// 执行 multipart/form-data 请求
    func requestMultipart(
        endpoint: String,
        method: String = "POST",
        body: Data,
        contentType: String,
        headers: [String: String]? = nil
    ) async throws -> Data {
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        
        // 添加认证令牌
        if let token = UserManager.shared.currentToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // 添加自定义请求头
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        request.httpBody = body
        request.timeoutInterval = 120
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.network(NSError(domain: "NetworkError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的响应"]))
        }
        
        // 处理 HTTP 状态码
        switch httpResponse.statusCode {
        case 200..<300:
            return data
        case 401:
            // 未授权 - 令牌过期或无效
            await handleUnauthorized()
            let message = extractErrorMessage(from: data) ?? "令牌无效，请重新登录"
            throw APIError.server(message: message)
        default:
            let message = extractErrorMessage(from: data) ?? "请求失败"
            throw APIError.server(message: message)
        }
    }
    
    /// 处理未授权错误（401）
    private func handleUnauthorized() async {
        // 清除本地令牌
        UserManager.shared.clearCurrentUser()
        
        // 发送令牌过期通知
        await MainActor.run {
            NotificationCenter.default.post(name: NetworkManager.tokenExpiredNotification, object: nil)
        }
    }
    
    /// 从响应数据中提取错误消息
    private func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? String else {
            return nil
        }
        return message
    }
}
