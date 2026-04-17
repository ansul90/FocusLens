import ServiceManagement

struct LoginItemManager {
    static func registerAtLogin() {
        do {
            try SMAppService.mainApp.register()
        } catch {
            // Already registered or unsupported — not fatal
        }
    }
}
