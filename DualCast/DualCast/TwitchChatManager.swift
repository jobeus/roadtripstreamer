import Foundation
import Combine

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let username: String
    let message: String
    let color: String
    let timestamp: Date
}

@MainActor
class TwitchChatManager: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isConnected = false
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let channel = "scottywanders"
    private let maxMessages = 50
    private var shouldReconnect = false
    
    func connect() {
        shouldReconnect = true
        openConnection()
    }
    
    func disconnect() {
        shouldReconnect = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }
    
    private func openConnection() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        let url = URL(string: "wss://irc-ws.chat.twitch.tv:443")!
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        // Anonymous login with tags capability for colors
        sendRaw("CAP REQ :twitch.tv/tags")
        sendRaw("PASS SCHMOOPIIE")
        sendRaw("NICK justinfan\(Int.random(in: 10000...99999))")
        sendRaw("JOIN #\(channel)")
        
        isConnected = true
        print("[Chat] Connecting to #\(channel)...")
        receiveMessage()
    }
    
    private func sendRaw(_ text: String) {
        webSocketTask?.send(.string(text)) { error in
            if let error {
                print("[Chat] Send error: \(error)")
            }
        }
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleIRC(text)
                    default:
                        break
                    }
                    self.receiveMessage()
                    
                case .failure(let error):
                    print("[Chat] Receive error: \(error)")
                    self.isConnected = false
                    if self.shouldReconnect {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        self.openConnection()
                    }
                }
            }
        }
    }
    
    private func handleIRC(_ raw: String) {
        for line in raw.components(separatedBy: "\r\n") where !line.isEmpty {
            print("[Chat] RAW: \(line)")
            
            if line.hasPrefix("PING") {
                sendRaw("PONG :tmi.twitch.tv")
                continue
            }
            
            if line.contains("PRIVMSG") {
                if let chatMsg = parsePRIVMSG(line) {
                    messages.append(chatMsg)
                    if messages.count > maxMessages {
                        messages.removeFirst()
                    }
                    print("[Chat] \(chatMsg.username): \(chatMsg.message)")
                }
            }
        }
    }
    
    private func parsePRIVMSG(_ line: String) -> ChatMessage? {
        // Twitch IRC format with tags:
        // @badge-info=...;color=#FF0000;display-name=User;... :user!user@user.tmi.twitch.tv PRIVMSG #channel :message text
        
        var color = "#FFFFFF"
        var displayName = ""
        
        // 1. Extract tags (everything between @ and first space)
        var remainder = line
        if line.hasPrefix("@") {
            guard let spaceIdx = line.firstIndex(of: " ") else { return nil }
            let tags = String(line[line.index(after: line.startIndex)..<spaceIdx])
            remainder = String(line[line.index(after: spaceIdx)...])
            
            for tag in tags.components(separatedBy: ";") {
                let kv = tag.components(separatedBy: "=")
                guard kv.count >= 2 else { continue }
                switch kv[0] {
                case "color":
                    if !kv[1].isEmpty { color = kv[1] }
                case "display-name":
                    displayName = kv[1]
                default:
                    break
                }
            }
        }
        
        // 2. Extract username from :user!user@... prefix
        // remainder looks like: :user!user@user.tmi.twitch.tv PRIVMSG #channel :message
        guard remainder.hasPrefix(":") else { return nil }
        guard let bangIdx = remainder.firstIndex(of: "!") else { return nil }
        let username = displayName.isEmpty
            ? String(remainder[remainder.index(after: remainder.startIndex)..<bangIdx])
            : displayName
        
        // 3. Extract message (everything after "PRIVMSG #channel :")
        guard let msgRange = remainder.range(of: "PRIVMSG #\(channel) :") else { return nil }
        let message = String(remainder[msgRange.upperBound...])
        
        return ChatMessage(
            username: username,
            message: message,
            color: color,
            timestamp: Date()
        )
    }
}
