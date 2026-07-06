//
//  AppConfig.swift
//  ReadingApp
//
//  Created by GPT-5.1 Codex on 2025/11/26.
//

import Foundation

enum AppConfig {
    enum API {
        static let scheme = Bundle.main.object(forInfoDictionaryKey: "API_SCHEME") as? String ?? "http"
        static let domain = Bundle.main.object(forInfoDictionaryKey: "API_HOST") as? String ?? "127.0.0.1"
        static let port = Bundle.main.object(forInfoDictionaryKey: "API_PORT") as? Int
        
        static var serverBaseURL: URL {
            var components = URLComponents()
            components.scheme = scheme
            components.host = domain
            if let port {
                components.port = port
            }
            components.path = ""
            return components.url!
        }

        static var baseURL: URL {
            serverBaseURL.appendingPathComponent("api")
        }
    }
}
