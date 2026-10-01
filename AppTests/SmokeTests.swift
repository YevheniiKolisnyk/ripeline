import Foundation
import Testing
import RipelineCore
@testable import Ripeline

struct SmokeTests {
    @Test func coreIsLinked() {
        #expect(SessionSettings().pausesCountAsRest)
    }

    @Test func appRunsInsideTheSandbox() {
        #expect(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil)
    }
}
