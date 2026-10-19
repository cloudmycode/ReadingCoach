import Foundation
import AVFoundation

@main
struct EdgeSpeechProtocolChecks {
    static func main() async throws {
        // Golden outputs from upstream edge-tts's v2 implementation, including a five-minute boundary.
        let vectors: [(TimeInterval, String)] = [
            (0, "52BC7A17B50DFEC9-28C4394775C8751CD2F6859C030C06DB1489ACAB3B3A7651831FC26895177ED6"),
            (1700000000, "2CD23A2CA0B2595A-F3C846C370E05F9CC83ACC5F995C5F5D87A4D0F14CE8936A0F902E64099E38A2"),
            (1700000099, "2CD23A2CA0B2595A-F3C846C370E05F9CC83ACC5F995C5F5D87A4D0F14CE8936A0F902E64099E38A2"),
            (1700000100, "0919602B5750900A-EC9DD394F23CB5635CF62A0E8E24136DCD32B26D10C543B10082E482D7516397"),
            (1792281600, "E4779CF1CC130B3F-E2F4BE724DD3B45DF81569996A4A70D26A223B7DF4A2D2D36ACB29D26AD88EDE")
        ]
        for (timestamp, expected) in vectors {
            let actual = EdgeSpeechToken.generate(date: Date(timeIntervalSince1970: timestamp))
            precondition(actual == expected, "Token mismatch at \(timestamp): \(actual)")
        }
        let request = try EdgeSpeechProtocol.request(date: Date(timeIntervalSince1970: 1700000000))
        precondition(request.timeoutInterval == 5)
        let url = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        let query = Dictionary(uniqueKeysWithValues: url.queryItems!.map { ($0.name, $0.value!) })
        precondition(url.scheme == "wss" && url.host == "api.msedgeservices.com")
        precondition(url.path == "/tts/cognitiveservices/websocket/v1")
        precondition(query["Ocp-Apim-Subscription-Key"] == EdgeSpeechProtocol.clientToken)
        precondition(query["TrustedClientToken"] == nil)
        precondition(query["Sec-MS-GEC-Version"] == "2-155.0.4283.45")
        precondition(query["Sec-MS-GEC"] == vectors[1].1)
        precondition(query["ConnectionId"]?.count == 32)
        print("PASS: v2 golden tokens, five-minute rollover, endpoint and handshake parameters")

        if CommandLine.arguments.contains("--live") {
            try await synthesize(voice: "en-US-EmmaMultilingualNeural", text: "Hello. This is a reading test.")
            try await synthesize(voice: "zh-CN-XiaoxiaoNeural", text: "这是一段朗读测试。")
        }
    }

    private static func synthesize(voice: String, text: String) async throws {
        let task = URLSession.shared.webSocketTask(with: try EdgeSpeechProtocol.request())
        // Also bound the receive loop if a server opens the socket but never finishes a turn.
        let timeout = Task {
            try await Task.sleep(nanoseconds: 30_000_000_000)
            task.cancel(with: .goingAway, reason: nil)
        }
        defer { timeout.cancel(); task.cancel(with: .normalClosure, reason: nil) }
        task.resume()
        do {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT+0000 (Coordinated Universal Time)'"
            let timestamp = formatter.string(from: Date())
            try await task.send(.string("X-Timestamp:\(timestamp)\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"true\"},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}"))
            let id = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            try await task.send(.string("X-RequestId:\(id)\r\nContent-Type:application/ssml+xml\r\nX-Timestamp:\(timestamp)Z\r\nPath:ssml\r\n\r\n<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'><voice name='\(voice)'><prosody pitch='+0Hz' rate='-5%' volume='+0%'>\(text)</prosody></voice></speak>"))
            var audio = Data()
            var boundaries: [SpeechWordBoundary] = []
            while true {
                switch try await task.receive() {
                case .data(let data):
                    guard data.count >= 2 else { continue }
                    let headerLength = Int(data[0]) * 256 + Int(data[1])
                    guard data.count >= 2 + headerLength else { continue }
                    let headers = String(decoding: data[2..<(2 + headerLength)], as: UTF8.self)
                    if headers.contains("Path:audio") { audio.append(data.dropFirst(2 + headerLength)) }
                case .string(let message):
                    if message.contains("Path:audio.metadata"), let separator = message.range(of: "\r\n\r\n") {
                        boundaries += SpeechWordBoundary.parse(metadata: Data(message[separator.upperBound...].utf8))
                    }
                    if message.contains("Path:turn.end") {
                        precondition(!audio.isEmpty && !boundaries.isEmpty, "Missing audio or word timing")
                        let player = try AVAudioPlayer(data: audio)
                        precondition(player.duration > 0)
                        print("PASS: live \(voice), \(audio.count) audio bytes, \(boundaries.count) word boundaries, duration \(player.duration)s")
                        return
                    }
                @unknown default: break
                }
            }
        } catch {
            let failure = error as NSError
            let status = (task.response as? HTTPURLResponse)?.statusCode
            print("FAIL: live synthesis domain=\(failure.domain) code=\(failure.code) HTTP=\(status.map(String.init) ?? "none") close=\(task.closeCode.rawValue)")
            // Do not print NSError.userInfo: it can contain the complete signed URL.
            throw NSError(domain: failure.domain, code: failure.code)
        }
    }
}
