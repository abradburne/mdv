import XCTest
@testable import mdv

final class FrontmatterTests: XCTestCase {
    func testStripsBasicFrontmatter() {
        let markdown = """
        ---
        title: Hello
        date: 2026-06-13
        ---
        # Heading

        Body text.
        """
        let result = AppModel.stripFrontmatter(from: markdown)
        XCTAssertEqual(result.markdown, "# Heading\n\nBody text.")
        XCTAssertEqual(result.title, "Hello")
    }

    func testExtractsQuotedTitle() {
        let doubleQuoted = AppModel.stripFrontmatter(from: "---\ntitle: \"My Doc\"\n---\nbody")
        XCTAssertEqual(doubleQuoted.title, "My Doc")

        let singleQuoted = AppModel.stripFrontmatter(from: "---\ntitle: 'My Doc'\n---\nbody")
        XCTAssertEqual(singleQuoted.title, "My Doc")
    }

    func testNoFrontmatterReturnsUnchanged() {
        let markdown = "# Just a doc\n\nNo frontmatter here."
        let result = AppModel.stripFrontmatter(from: markdown)
        XCTAssertEqual(result.markdown, markdown)
        XCTAssertNil(result.title)
    }

    func testUnclosedDelimiterReturnsUnchanged() {
        let markdown = "---\ntitle: Oops\n\nNever closed."
        let result = AppModel.stripFrontmatter(from: markdown)
        XCTAssertEqual(result.markdown, markdown)
        XCTAssertNil(result.title)
    }

    func testProseBetweenDashesIsNotFrontmatter() {
        // A thematic break followed by prose and another break is markdown,
        // not metadata — stripping it would eat document content.
        let markdown = "---\n\nSome opening words.\n\n---\n\nMore text."
        let result = AppModel.stripFrontmatter(from: markdown)
        XCTAssertEqual(result.markdown, markdown)
        XCTAssertNil(result.title)
    }

    func testYamlDocumentEndMarkerCloses() {
        let result = AppModel.stripFrontmatter(from: "---\ntitle: Dots\n...\nbody")
        XCTAssertEqual(result.markdown, "body")
        XCTAssertEqual(result.title, "Dots")
    }

    func testIndentedLinesAndCommentsAllowed() {
        let markdown = """
        ---
        # build metadata
        tags:
          - one
          - two
        ---
        body
        """
        let result = AppModel.stripFrontmatter(from: markdown)
        XCTAssertEqual(result.markdown, "body")
        XCTAssertNil(result.title)
    }

    func testIndentedTitleIsNotDocumentTitle() {
        let markdown = """
        ---
        meta:
          title: Nested
        ---
        body
        """
        let result = AppModel.stripFrontmatter(from: markdown)
        XCTAssertEqual(result.markdown, "body")
        XCTAssertNil(result.title)
    }

    func testEmptyFrontmatterIsStripped() {
        let result = AppModel.stripFrontmatter(from: "---\n---\nbody")
        XCTAssertEqual(result.markdown, "body")
        XCTAssertNil(result.title)
    }

    func testDelimiterMustBeFirstLine() {
        let markdown = "\n---\ntitle: Late\n---\nbody"
        let result = AppModel.stripFrontmatter(from: markdown)
        XCTAssertEqual(result.markdown, markdown)
        XCTAssertNil(result.title)
    }

    @MainActor
    func testFrontmatterCommentsDoNotBecomeTOCHeadings() {
        let markdown = """
        ---
        # this yaml comment looks like a heading
        title: Doc
        ---
        # Real Heading
        """
        let stripped = AppModel.stripFrontmatter(from: markdown)
        let toc = AppModel.extractTableOfContents(from: stripped.markdown)
        XCTAssertEqual(toc.map(\.title), ["Real Heading"])
    }
}
