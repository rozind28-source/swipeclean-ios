import SwiftUI
import Observation

enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case dark = "dark"
    case light = "light"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "Системная"
        case .dark:
            return "Тёмная"
        case .light:
            return "Светлая"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }
}

@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Keys {
        static let theme = "app_theme"
        static let hapticsEnabled = "haptics_enabled"
        static let hideCompletedGroups = "hide_completed_groups"
    }

    var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme)
        }
    }

    var hapticsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hapticsEnabled, forKey: Keys.hapticsEnabled)
        }
    }

    var hideCompletedGroups: Bool {
        didSet {
            UserDefaults.standard.set(hideCompletedGroups, forKey: Keys.hideCompletedGroups)
        }
    }

    init() {
        let defaults = UserDefaults.standard

        // По умолчанию тёмная тема
        if let storedTheme = defaults.string(forKey: Keys.theme),
           let parsedTheme = AppTheme(rawValue: storedTheme) {
            self.theme = parsedTheme
        } else {
            self.theme = .dark
        }

        // По умолчанию тактильный отклик включён
        if defaults.object(forKey: Keys.hapticsEnabled) != nil {
            self.hapticsEnabled = defaults.bool(forKey: Keys.hapticsEnabled)
        } else {
            self.hapticsEnabled = true
        }

        // По умолчанию не скрывать
        self.hideCompletedGroups = defaults.bool(forKey: Keys.hideCompletedGroups)
    }
}
