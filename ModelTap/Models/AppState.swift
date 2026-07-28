import Foundation

struct RequestNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}
