import AppKit

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
