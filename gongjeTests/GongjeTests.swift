import XCTest
@testable import gongje

final class GongjeTests: XCTestCase {
    func testWhisperModelRecommendation() {
        XCTAssertEqual(WhisperModel.recommended(forRAMGB: 8), .cantoneseSmall)
        XCTAssertEqual(WhisperModel.recommended(forRAMGB: 16), .cantoneseLargeV3Turbo)
        XCTAssertEqual(WhisperModel.recommended(forRAMGB: 32), .cantoneseLargeV3Turbo)
    }

    func testWhisperModelDisplayNames() {
        for model in WhisperModel.allCases {
            XCTAssertFalse(model.displayName.isEmpty)
            XCTAssertFalse(model.id.isEmpty)
        }
    }
}
