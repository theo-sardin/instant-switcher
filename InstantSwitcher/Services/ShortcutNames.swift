import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static func binding(_ id: UUID) -> KeyboardShortcuts.Name {
        .init("binding.\(id.uuidString)")
    }
}
