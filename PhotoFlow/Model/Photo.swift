import Foundation

struct Photo: Hashable, Sendable {

    let id: String
    let author: String
    let imageURL: URL
}
