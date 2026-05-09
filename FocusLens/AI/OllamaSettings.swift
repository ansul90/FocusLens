import Foundation

enum ModelMatch {
    case exact
    case prefix(closest: String)
    case none
}

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

    /// Matches the configured model name against a list of available model names.
    /// Tries exact match first; falls back to base-name prefix match.
    func matchModel(in available: [String]) -> ModelMatch {
        let configured = modelName.lowercased()
        let configuredBase = configured.components(separatedBy: ":").first ?? configured

        if available.contains(where: { $0.lowercased() == configured }) {
            return .exact
        }
        if let closest = available.first(where: {
            ($0.lowercased().components(separatedBy: ":").first ?? $0.lowercased()) == configuredBase
        }) {
            return .prefix(closest: closest)
        }
        return .none
    }
}
