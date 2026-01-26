import XCTest
@testable import CrateBotCore

final class DescriptiveTagMappingTests: XCTestCase {

    func testSubCategoryForBassTypeTags() {
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Punchy"), .bassType)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Walking"), .bassType)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "BoomingBass"), .bassType)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "GrindyBass"), .bassType)
    }

    func testSubCategoryForRhythmTags() {
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Broken"), .rhythm)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Swung"), .rhythm)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Driving"), .rhythm)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Loopy"), .rhythm)
    }

    func testSubCategoryForStyleTags() {
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Afro"), .style)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Electro"), .style)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Poppy"), .style)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Disco"), .style)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Classic"), .style)
    }

    func testSubCategoryForVibeTags() {
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Fun"), .vibes)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Funky"), .vibes)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Bouncy"), .vibes)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Dreamy"), .vibes)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Dark"), .vibes)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Dope"), .vibes)
    }

    func testSubCategoryForInstrumentTags() {
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Piano"), .instruments)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Organ"), .instruments)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Guitar"), .instruments)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Horns"), .instruments)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Congas"), .instruments)
    }

    func testSubCategoryForVocalTypeTags() {
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Singing"), .vocalType)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Chanting"), .vocalType)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Spoken Word"), .vocalType)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Rap"), .vocalType)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Instrumental"), .vocalType)
    }

    func testUnknownTagReturnsNil() {
        XCTAssertNil(DescriptiveTagMapping.subCategory(for: "UnknownTag"))
        XCTAssertNil(DescriptiveTagMapping.subCategory(for: "RandomStuff"))
    }

    func testTagsForSubCategory() {
        let rhythmTags = DescriptiveTagMapping.tags(for: .rhythm)
        XCTAssertTrue(rhythmTags.contains("Broken"))
        XCTAssertTrue(rhythmTags.contains("Swung"))
        XCTAssertTrue(rhythmTags.contains("Driving"))
        XCTAssertTrue(rhythmTags.contains("Loopy"))
        XCTAssertEqual(rhythmTags.count, 4)
    }

    func testOrderedSubCategories() {
        let ordered = DescriptiveSubCategory.allCases
        XCTAssertEqual(ordered[0], .bassType)
        XCTAssertEqual(ordered[1], .rhythm)
        XCTAssertEqual(ordered[2], .style)
        XCTAssertEqual(ordered[3], .vibes)
        XCTAssertEqual(ordered[4], .instruments)
        XCTAssertEqual(ordered[5], .vocalType)
    }
}
