import Foundation

struct MarkdownRenderer {
    private let markdownIt: String
    private let markdownItAnchor: String

    init() {
        markdownIt = MarkdownRenderer.loadResource(named: "markdown-it.min", ext: "js")
        markdownItAnchor = MarkdownRenderer.loadResource(named: "markdown-it-anchor.min", ext: "js")
    }

    func render(markdown: String, css: String) -> String {
        let encoded = Data(markdown.utf8).base64EncodedString()
        let script = """
        \(markdownIt)
        \(markdownItAnchor)
        function mdvSlugify(s) {
          return String(s)
            .trim()
            .toLowerCase()
            .replace(/[^a-z0-9\\s-]/g, "")
            .replace(/[\\s-]+/g, "-");
        }
        var md = markdownit({html: true, linkify: true, typographer: true});
        if (typeof markdownItAnchor !== "undefined") {
          md.use(markdownItAnchor, { slugify: mdvSlugify });
        }
        var bytes = Uint8Array.from(atob("\(encoded)"), c => c.charCodeAt(0));
        var mdSrc = new TextDecoder("utf-8").decode(bytes);
        document.getElementById("mdv-content").innerHTML = md.render(mdSrc);
        """
        return wrap(body: "<div id=\"mdv-content\"></div><script>\(script)</script>", css: css)
    }

    func wrap(body: String, css: String) -> String {
        """
        <!doctype html>
        <html>
          <head>
            <meta charset=\"utf-8\" />
            <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
            <style>\(css)</style>
          </head>
          <body>
            <article class=\"md\">\(body)</article>
          </body>
        </html>
        """
    }

    private static func loadResource(named: String, ext: String) -> String {
        guard let url = Bundle.module.url(forResource: named, withExtension: ext),
              let script = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return script
    }
}
