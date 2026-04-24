import Foundation

struct OllamaSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get {
            let stored = defaults.object(forKey: AppConstants.Ollama.userDefaultsKeyEnabled)
            return stored == nil ? true : defaults.bool(forKey: AppConstants.Ollama.userDefaultsKeyEnabled)
        }
        set { defaults.set(newValue, forKey: AppConstants.Ollama.userDefaultsKeyEnabled) }
    }

    var host: String {
        get { defaults.string(forKey: AppConstants.Ollama.userDefaultsKeyHost) ?? AppConstants.Ollama.defaultHost }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: AppConstants.Ollama.userDefaultsKeyHost) }
    }

    var modelName: String {
        get { defaults.string(forKey: AppConstants.Ollama.userDefaultsKeyModel) ?? AppConstants.Ollama.defaultModel }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: AppConstants.Ollama.userDefaultsKeyModel) }
    }

    var baseURL: URL {
        URL(string: host) ?? URL(string: AppConstants.Ollama.defaultHost)!
    }
}
