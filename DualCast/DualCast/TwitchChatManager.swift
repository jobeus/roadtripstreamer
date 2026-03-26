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
    private var channel: String = ""
    private let maxMessages = 50
    private var shouldReconnect = false
    
    func connect(to channel: String) {
        guard !channel.isEmpty else { return }
        self.channel = channel.lowercased().trimmingCharacters(in: .whitespaces)
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
        let url = URL(string: "wss://irc-ws.chat.twitch.tv:443")!
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        // Anonymous login
        sendRaw("CAP REQ :twitch.tv/tags")
        sendRaw("NICK justinfan\(Int.random(in: 10000...99999))")
        sendRaw("JOIN #\(channel)")
        
        isConnected = true
        receiveMessage()
    }
    
    private func sendRaw(_ text: String) {
        webSocketTask?.send(.string(text)) { error in
            if let error {
                print("WebSocket send error: \(error)")
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
                    self.receiveMessage() // Continue listening
                    
                case .failure(let error):
                    print("WebSocket receive error: \(error)")
                    self.isConnected = false
                    if self.shouldReconnect {
                        // Reconnect after 3 seconds
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        self.openConnection()
                    }
                }
            }
        }
    }
    
    private func handleIRC(_ raw: String) {
        for line in raw.components(separatedBy: "\r\n") where !line.isEmpty {
            // Respond to PING to stay connected
            if line.hasPrefix("PING") {
                sendRaw("PONG :tmi.twitch.tv")
                continue
            }
            
            // Parse PRIVMSG
            if line.contains("PRIVMSG") {
                if let chatMsg = parsePRIVMSG(line) {
                    messages.append(chatMsg)
                    if messages.count > maxMessages {
                        messages.removeFirst()
                    }
                }
            }
        }
    }
    
    private func parsePRIVMSG(_ line: String) -> ChatMessage? {
        // Format: @tags :user!user@user.tmi.twitch.tv PRIVMSG #channel :message
        var color = "#FFFFFF"
        
        // Extract color from tags
        if let tagsEnd = line.firstIndex(of: " "), line.hasPrefix("@") {
            let tags = String(line[line.index(after: line.startIndex)..<tagsEnd])
            for tag in tags.components(separatedBy: ";") {
                let parts = tag.components(separatedBy: "=")
                if parts.count == 2 && parts[0] == "color" && !parts[1].isEmpty {
                    color = parts[1]
                }
            }
        }
        
        // Extract username
        guard let userStart = line.firstIndex(of: ":"),
              let userEnd = line.firstIndex(of: "!") else { return nil }
        
        let afterTags = line[userStart...]
        guard let realUserStart = afterTags.firstIndex(of: ":"),
              let realUserEnd = afterTags.firstIndex(of: "!") else { return nil }
        
        let username = String(afterTags[afterTags.index(after: realUserStart)..<realUserEnd])
        
        // Extract message (everything after "PRIVMSG #channel :")
        guard let privmsgRange = line.range(of: "PRIVMSG #\(channel) :") else { return nil }
        let message = String(line[privmsgRange.upperBound...])
        
        return ChatMessage(
            username: username,
            message: message,
            color: color,
            timestamp: Date()
        )
    }
}
