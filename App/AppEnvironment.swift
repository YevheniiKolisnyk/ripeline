import Foundation
import os
import RipelineCore

/// Builds the app's object graph. The only place that chooses real services over test ones.
@MainActor
final class AppEnvironment {
    let settings: AppSettings
    let controller: SessionController
    let setupModel: DaySetupModel
    let overviewModel: DayOverviewModel
    let historyModel: HistoryModel
    let garden: GardenModel
    let crateModel: CrateModel
    let router = AppRouter()
    let store: any DayStore
    let notifier: any Notifier
    /// `true` when running under XCTest: nothing real is touched.
    let isInert: Bool
    private let wakeObserver: WakeObserver?

    private init(
        settings: AppSettings, controller: SessionController, store: any DayStore, harvest: any HarvestStore,
        notifier: any Notifier, isInert: Bool, wakeObserver: WakeObserver?
    ) {
        self.settings = settings
        self.controller = controller
        overviewModel = DayOverviewModel(source: controller)
        let garden = GardenModel(store: harvest)
        self.garden = garden
        crateModel = CrateModel(store: store, garden: garden)
        historyModel = HistoryModel(
            store: store, activeDayID: { [weak controller] in controller?.activeDayID },
            onDayDeleted: { [garden] snapshot in garden.forget(day: snapshot) }
        )
        setupModel = DaySetupModel(
            settings: settings, clock: SystemClock(),
            canStart: { [weak controller] in controller?.isAllowed(.startDay) ?? false },
            start: { [weak controller] request in await controller?.startDay(request: request) ?? false }
        )
        self.store = store
        self.notifier = notifier
        self.isInert = isInert
        self.wakeObserver = wakeObserver
    }

    /// Whether the process was started by XCTest. The unit tests are hosted inside this app, so
    /// without this check running them would read the developer's real day and talk to the
    /// real notification center.
    static func isRunningTests(_ environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
    }

    static func make(processEnvironment: [String: String] = ProcessInfo.processInfo.environment) -> AppEnvironment {
        isRunningTests(processEnvironment) ? makeInert() : makeLive()
    }

    private static func makeInert() -> AppEnvironment {
        let suite = "ripeline.inert"
        UserDefaults().removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite) ?? .standard)
        let store = InMemoryDayStore()
        let notifier = NullNotifier()
        let controller = SessionController(
            clock: SystemClock(), store: store, notifier: notifier, ticker: NullTicker(), settings: settings
        )
        return AppEnvironment(
            settings: settings, controller: controller, store: store, harvest: InMemoryHarvestStore(), notifier: notifier,
            isInert: true, wakeObserver: nil
        )
    }

    private static func makeLive() -> AppEnvironment {
        let settings = AppSettings()
        let store: any DayStore
        do {
            store = FileDayStore(directory: try FileDayStore.defaultDirectory())
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "Ripeline", category: "launch")
                .error("Cannot use the days directory; days will not be saved: \(error.localizedDescription, privacy: .public)")
            store = InMemoryDayStore()
        }
        let harvest: any HarvestStore
        do {
            harvest = FileHarvestStore(file: try FileHarvestStore.defaultFile())
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "Ripeline", category: "launch")
                .error("Cannot use the harvest file; picked tomatoes will not be saved: \(error.localizedDescription, privacy: .public)")
            harvest = InMemoryHarvestStore()
        }
        let notifier = SystemNotifier()
        let controller = SessionController(
            clock: SystemClock(), store: store, notifier: notifier, ticker: TaskTicker(), settings: settings
        )
        controller.restore()
        let observer = WakeObserver { [weak controller] in controller?.refresh() }
        return AppEnvironment(
            settings: settings, controller: controller, store: store, harvest: harvest, notifier: notifier,
            isInert: false, wakeObserver: observer
        )
    }
}
