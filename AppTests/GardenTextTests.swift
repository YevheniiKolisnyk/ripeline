import Foundation
import RipelineCore
import Testing
@testable import Ripeline

struct GardenTextTests {
    private func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test func percentRoundsToWholeNumbers() {
        #expect(GardenText.percent(0.404) == 40)
        #expect(GardenText.percent(1.256) == 126)
    }

    @Test func labelsAreInBothLanguages() throws {
        let en = try bundle("en"), uk = try bundle("uk")
        #expect(GardenText.basket(3, bundle: en) == "Picked: 3")
        #expect(GardenText.basket(3, bundle: uk) == "Зібрано: 3")
        #expect(GardenText.crateTotal(12, bundle: en) == "12 in the crate")
        #expect(GardenText.crateTotal(12, bundle: uk) == "У ящику: 12")
        #expect(GardenText.crateLabel(total: 12, bundle: en) == "Crate, tomatoes: 12")
    }

    @Test func aTomatoIsDescribedByItsGrowthAndWhetherItCanBePicked() throws {
        let en = try bundle("en")
        #expect(GardenText.tomatoLabel(growth: 0.4, availability: .growing, isPicked: false, bundle: en) == "Tomato, 40% grown")
        #expect(GardenText.tomatoLabel(growth: 1.1, availability: .pickable, isPicked: false, bundle: en) == "Tomato, 110% grown, ready to pick")
        #expect(GardenText.tomatoLabel(growth: 1.1, availability: .pickable, isPicked: true, bundle: en) == "Picked tomato, 110%")
        let uk = try bundle("uk")
        #expect(GardenText.tomatoLabel(growth: 0.4, availability: .growing, isPicked: false, bundle: uk) == "Помідор, виріс на 40%")
    }
}
