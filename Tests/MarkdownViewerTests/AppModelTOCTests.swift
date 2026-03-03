import XCTest
@testable import mdv

final class AppModelTOCTests: XCTestCase {
    @MainActor
    func testExtractTableOfContentsBuildsH1AndNestedH2() {
        let markdown = """
        # Intro
        Some text
        ## First child
        ## Second child
        # Next
        ## Another child
        """

        let toc = AppModel.extractTableOfContents(from: markdown)

        XCTAssertEqual(toc.count, 2)
        XCTAssertEqual(toc[0].title, "Intro")
        XCTAssertEqual(toc[0].anchor, "intro")
        XCTAssertEqual(toc[0].children.map(\.title), ["First child", "Second child"])
        XCTAssertEqual(toc[0].children.map(\.anchor), ["first-child", "second-child"])
        XCTAssertEqual(toc[1].title, "Next")
        XCTAssertEqual(toc[1].children.map(\.title), ["Another child"])
    }

    @MainActor
    func testExtractTableOfContentsSkipsHeadingInsideCodeFenceAndDisambiguatesDuplicates() {
        let markdown = """
        # Repeated
        ## Child

        ```
        # Not heading
        ## Also not heading
        ```

        # Repeated
        ## Child
        """

        let toc = AppModel.extractTableOfContents(from: markdown)

        XCTAssertEqual(toc.count, 2)
        XCTAssertEqual(toc[0].anchor, "repeated")
        XCTAssertEqual(toc[1].anchor, "repeated-1")
        XCTAssertEqual(toc[0].children.first?.anchor, "child")
        XCTAssertEqual(toc[1].children.first?.anchor, "child-1")
    }
}
