import Foundation

/// Edge Read Aloud handshake. Keep the endpoint, client version and token version together.
enum EdgeSpeechProtocol {
    static let clientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    static let clientVersion = "155.0.4283.45"
    static let tokenVersion = "2-\(clientVersion)"

    static func request(date: Date = Date()) throws -> URLRequest {
        var url = URLComponents(string: "wss://api.msedgeservices.com/tts/cognitiveservices/websocket/v1")!
        url.queryItems = [
            URLQueryItem(name: "Ocp-Apim-Subscription-Key", value: clientToken),
            URLQueryItem(name: "Sec-MS-GEC", value: EdgeSpeechToken.generate(date: date)),
            URLQueryItem(name: "Sec-MS-GEC-Version", value: tokenVersion),
            URLQueryItem(name: "ConnectionId", value: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())
        ]
        guard let endpoint = url.url else { throw URLError(.badURL) }
        var request = URLRequest(url: endpoint, timeoutInterval: SpeechSynthesisPolicy.inactivityTimeout)
        let major = clientVersion.split(separator: ".")[0]
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(major).0.0.0 Safari/537.36 Edg/\(major).0.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold", forHTTPHeaderField: "Origin")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        // URLSession owns Upgrade, Sec-WebSocket-Key and compression negotiation.
        return request
    }
}
