import AppKit

// Capture the real system language from the global domain (unaffected by app-level AppleLanguages).
if let systemLanguages = CFPreferencesCopyValue(
    "AppleLanguages" as CFString,
    kCFPreferencesAnyApplication,
    kCFPreferencesCurrentUser,
    kCFPreferencesAnyHost
) as? [String], let first = systemLanguages.first {
    UserDefaults.standard.set(first, forKey: "detectedSystemLanguage")
}

// Apply language override BEFORE any framework initializes localization.
// This must run before GongjeApp.main() so the bundle resolves the correct lproj.
let languageOverride = UserDefaults.standard.string(forKey: "appLanguageOverride")
if let lang = languageOverride, lang != "system" {
    UserDefaults.standard.set([lang], forKey: "AppleLanguages")
} else {
    UserDefaults.standard.removeObject(forKey: "AppleLanguages")
}
UserDefaults.standard.synchronize()

GongjeApp.main()
