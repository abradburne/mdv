import XCTest
@testable import mdv

final class MarkdownRendererTests: XCTestCase {
    @MainActor
    func testWrapAddsCSSAndArticle() {
        let renderer = MarkdownRenderer()
        let html = renderer.wrap(body: "<p>Hello</p>", css: "body { color: red; }", baseURL: nil)

        XCTAssertTrue(html.contains("<style>body { color: red; }</style>"))
        XCTAssertTrue(html.contains("<article class=\"md\"><p>Hello</p></article>"))
    }

    @MainActor
    func testRenderConvertsMarkdownToHTML() {
        let renderer = MarkdownRenderer()
        let html = renderer.render(markdown: "# Title", css: "", baseURL: nil)

        XCTAssertTrue(html.contains("document.getElementById(\"mdv-content\").innerHTML = md.render(mdSrc);"))
        XCTAssertTrue(html.contains("<div id=\"mdv-content\"></div>"))
    }

    @MainActor
    func testRenderSupportsTables() {
        let renderer = MarkdownRenderer()
        let markdown = """
        | A | B |
        | - | - |
        | 1 | 2 |
        """
        let html = renderer.render(markdown: markdown, css: "", baseURL: nil)

        XCTAssertTrue(html.contains("markdownit({html: true, linkify: true, typographer: true})"))
        XCTAssertTrue(html.contains("var mdSrc = new TextDecoder(\"utf-8\").decode(bytes);"))
    }
}
