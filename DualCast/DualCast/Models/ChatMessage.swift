import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let username: String
    let message: String
    let color: String
    let timestamp: Date
}
