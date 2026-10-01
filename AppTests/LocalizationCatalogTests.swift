import Foundation
import Testing
@testable import Ripeline

/// The String Catalog is compiled into `<language>.lproj/Localizable.strings` in the app bundle.
/// Reading those (rather than the source file) keeps the test working inside the App Sandbox.
struct LocalizationCatalogTests {
    private func strings(_ language: String) throws -> [String: String] {
        let path = try #require(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language))
        let table = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
        return table
    }

    @Test func englishAndUkrainianHaveTheSameKeys() throws {
        let english = try strings("en")
        let ukrainian = try strings("uk")
        #expect(Set(english.keys) == Set(ukrainian.keys))
        #expect(!english.isEmpty)
    }

    @Test func everyValueIsFilledIn() throws {
        for language in ["en", "uk"] {
            for (key, value) in try strings(language) {
                #expect(!value.trimmingCharacters(in: .whitespaces).isEmpty, "\(language) / \(key) is empty")
                #expect(value != key, "\(language) / \(key) is untranslated")
            }
        }
    }

    /// Product names and the like may legitimately read the same in both languages.
    private let sameInBothLanguages: Set<String> = ["app.name"]

    @Test func ukrainianDiffersFromEnglish() throws {
        let english = try strings("en")
        let ukrainian = try strings("uk")
        for (key, value) in english where !sameInBothLanguages.contains(key) {
            #expect(ukrainian[key] != value, "\(key) has the same text in en and uk")
        }
    }
}
