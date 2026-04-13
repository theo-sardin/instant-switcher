import Foundation

struct AppBinding: Codable, Identifiable, Hashable {
    let id: UUID
    var bundleIdentifier: String
    var displayName: String
    var iconPath: String?
}

struct SpaceBinding: Codable, Identifiable, Hashable {
    let id: UUID
    var spaceIndex: Int
    var label: String
}

enum Binding: Codable, Identifiable, Hashable {
    case app(AppBinding)
    case space(SpaceBinding)

    var id: UUID {
        switch self {
        case .app(let b): return b.id
        case .space(let b): return b.id
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, payload }
    private enum Kind: String, Codable { case app, space }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .app:   self = .app(try c.decode(AppBinding.self, forKey: .payload))
        case .space: self = .space(try c.decode(SpaceBinding.self, forKey: .payload))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .app(let b):
            try c.encode(Kind.app, forKey: .kind)
            try c.encode(b, forKey: .payload)
        case .space(let b):
            try c.encode(Kind.space, forKey: .kind)
            try c.encode(b, forKey: .payload)
        }
    }
}
