import Foundation
import Testing
@testable import Ripeline

struct NotifierTests {
    private let kinds: [SignalKind] = [.workEnded, .breakEnded, .dayFinished]

    private func bundle(for language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test(arguments: ["en", "uk"])
    func contentIsFilledInForEveryKind(language: String) throws {
        let bundle = try bundle(for: language)
        for kind in kinds {
            let content = SignalContent(kind: kind, bundle: bundle)
            #expect(!content.title.isEmpty, "\(kind) title")
            #expect(!content.body.isEmpty, "\(kind) body")
            #expect(!content.title.hasPrefix("notification."), "\(kind) title is an untranslated key")
            #expect(!content.body.hasPrefix("notification."), "\(kind) body is an untranslated key")
        }
    }

    @Test func ukrainianDiffersFromEnglish() throws {
        let english = try bundle(for: "en"), ukrainian = try bundle(for: "uk")
        for kind in kinds {
            #expect(SignalContent(kind: kind, bundle: english) != SignalContent(kind: kind, bundle: ukrainian))
        }
    }

    @Test func eachKindHasItsOwnTitle() throws {
        let english = try bundle(for: "en")
        let titles = Set(kinds.map { SignalContent(kind: $0, bundle: english).title })
        #expect(titles.count == kinds.count)
    }
}
