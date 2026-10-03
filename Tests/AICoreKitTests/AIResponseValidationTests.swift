import AICore
import XCTest

final class AIResponseValidationTests:
    XCTestCase
{
    func testCompletedTextIsTrimmed() throws {
        let response = AIResponse(
            text: "  Ready to use.\n",
            providerID: "test"
        )

        XCTAssertEqual(
            try response.validatedCompletedText(),
            "Ready to use."
        )
    }

    func testNonEmptyTruncatedTextFailsClosed() {
        let response = AIResponse(
            text: "This is only the beginning",
            providerID: "test",
            finishReason: .maxOutputReached
        )

        XCTAssertThrowsError(
            try response.validatedCompletedText()
        ) { error in
            XCTAssertEqual(
                error as? AICompletedTextValidationError,
                .outputTruncated
            )
        }
    }

    func testEmptyCompletedTextFailsClosed() {
        let response = AIResponse(
            text: "  \n ",
            providerID: "test",
            finishReason: .completed
        )

        XCTAssertThrowsError(
            try response.validatedCompletedText()
        ) { error in
            XCTAssertEqual(
                error as? AICompletedTextValidationError,
                .empty
            )
        }
    }
}
