import Foundation

final class PermissionManager {
    static let shared = PermissionManager()
    private init() {}
    var accessibilityGranted: Bool { false }
}
