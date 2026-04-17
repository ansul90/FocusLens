import Foundation

struct GeminiSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var apiKey: String {
        get { defaults.string(forKey: AppConstants.AI.userDefaultsKeyAPIKey) ?? "" }
        set { defaults.set(newValue, forKey: AppConstants.AI.userDefaultsKeyAPIKey) }
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: AppConstants.AI.userDefaultsKeyEnabled) }
        set { defaults.set(newValue, forKey: AppConstants.AI.userDefaultsKeyEnabled) }
    }

    var hasValidKey: Bool {
        isEnabled && !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
