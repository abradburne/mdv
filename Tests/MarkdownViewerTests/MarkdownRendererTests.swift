import XCTest
@testable import mdv

final class MarkdownRendererTests: XCTestCase {
    @MainActor
    func testWrapAddsCSSAndArticle() {
        let renderer = MarkdownRenderer()
        let html = renderer.wrap(body: "<p>Hello</p>", css: "body { color: red; }")

        XCTAssertTrue(html.contains("<style>body { color: red; }</style>"))
        XCTAssertTrue(html.contains("<article class=\"md\"><p>Hello</p></article>"))
    }

    @MainActor
    func testRenderConvertsMarkdownToHTML() throws {
        let renderer = MarkdownRenderer()
        let html = try renderer.render(markdown: "# Title", css: "")

        XCTAssertTrue(html.contains("<h1>Title</h1>"))
    }

    @MainActor
    func testRenderSupportsTables() throws {
        let renderer = MarkdownRenderer()
        let markdown = """
        | A | B |
        | - | - |
        | 1 | 2 |
        """
        let html = try renderer.render(markdown: markdown, css: "")

        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<td>1</td>"))
    }
}
