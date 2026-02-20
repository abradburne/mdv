import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WebKit

@main
@MainActor
final class AppMain: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var windows: [NSWindow] = []
    private var closedWindows: [NSWindow] = []
    private var settingsWindow: NSWindow?
    private let settingsModel = SettingsModel()
    private var windowModels: [ObjectIdentifier: AppModel] = [:]
    private var suppressOpenPaths: Set<String> = []
    private let appDisplayName = "mdv"
    private var recentMenu: NSMenu?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppMain()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        let args = CommandLine.arguments.dropFirst()
        if args.isEmpty {
            DispatchQueue.main.async {
                if self.windows.isEmpty {
                    _ = self.createWindow(model: AppModel())
                }
            }
        } else {
            suppressOpenPaths = Set(args.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
            for path in args {
                openURL(URL(fileURLWithPath: path))
            }
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if windows.isEmpty {
                _ = createWindow(model: AppModel())
            }
            windows.last?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @MainActor
    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About \(appDisplayName)",
            action: #selector(showAbout(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(
            withTitle: "Settings…",
            action: #selector(openSettings(_:)),
            keyEquivalent: ","
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit \(appDisplayName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(
            withTitle: "Open…",
            action: #selector(openDocument(_:)),
            keyEquivalent: "o"
        )
        let recentMenu = NSMenu(title: "Open Recent")
        recentMenu.delegate = self
        recentMenu.autoenablesItems = false
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recentMenu
        fileMenu.addItem(recentItem)
        fileMenu.addItem(
            withTitle: "New Window",
            action: #selector(newWindow(_:)),
            keyEquivalent: "n"
        )
        fileMenu.addItem(.separator())
        fileMenu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApplication.shared.mainMenu = mainMenu
        NSApplication.shared.windowsMenu = windowMenu

        self.recentMenu = recentMenu
    }

    @objc
    @MainActor
    private func openDocument(_ sender: Any?) {
        openPanel()
    }

    @objc
    @MainActor
    private func newWindow(_ sender: Any?) {
        _ = createWindow(model: AppModel())
    }

    @objc
    @MainActor
    private func openSettings(_ sender: Any?) {
        showSettingsWindow()
    }

    @objc
    @MainActor
    private func showAbout(_ sender: Any?) {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String
        let versionString = build == nil ? version : "\(version) (\(build!))"
        let credits = NSAttributedString(string: "Super Simple Markdown Viewer\n© 2026 Alan Bradburne · alanb@hey.com")

        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: appDisplayName,
            .version: versionString,
            .credits: credits
        ]
        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
    }

    @MainActor
    private func showSettingsWindow() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Settings"
        window.contentView = NSHostingView(rootView: SettingsView(model: settingsModel))
        window.makeKeyAndOrderFront(nil)
        self.settingsWindow = window
    }

    private func createWindow(model: AppModel) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = appDisplayName
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.delegate = self
        windows.append(window)
        windowModels[ObjectIdentifier(window)] = model
        return window
    }

    private func openURL(_ url: URL) {
        let standardized = url.standardizedFileURL

        if let existing = windowModels.first(where: { $0.value.documentURL == standardized }) {
            let window = windows.first { ObjectIdentifier($0) == existing.key }
            window?.makeKeyAndOrderFront(nil)
            NSDocumentController.shared.noteNewRecentDocumentURL(standardized)
            return
        }

        if let targetWindow = NSApplication.shared.keyWindow,
           let targetModel = windowModels[ObjectIdentifier(targetWindow)],
           !targetModel.hasDocument {
            targetModel.open(url: standardized)
            targetWindow.title = standardized.lastPathComponent
            targetWindow.representedURL = standardized
            NSDocumentController.shared.noteNewRecentDocumentURL(standardized)
            return
        }

        let model = AppModel()
        model.open(url: standardized)
        let window = createWindow(model: model)
        window.title = standardized.lastPathComponent
        window.representedURL = standardized
        NSDocumentController.shared.noteNewRecentDocumentURL(standardized)
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.plainText]
        if let mdType = UTType(filenameExtension: "md") {
            types.insert(mdType, at: 0)
        }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.openURL(url)
            }
        }
    }

    @objc
    private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        openURL(url)
    }

    @objc
    private func clearRecent(_ sender: Any?) {
        NSDocumentController.shared.clearRecentDocuments(nil)
        updateRecentMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === recentMenu else { return }
        updateRecentMenu()
    }

    private func updateRecentMenu() {
        guard let menu = recentMenu else { return }
        menu.removeAllItems()

        let urls = NSDocumentController.shared.recentDocumentURLs
        if urls.isEmpty {
            let item = NSMenuItem(title: "No Recent Documents", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return
        }

        for url in urls {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.representedObject = url
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let clearItem = NSMenuItem(title: "Clear Menu", action: #selector(clearRecent(_:)), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let standardized = url.standardizedFileURL.path
            if suppressOpenPaths.remove(standardized) != nil {
                continue
            }
            openURL(url)
        }
    }

    func application(_ application: NSApplication, openFile filename: String) -> Bool {
        let standardized = URL(fileURLWithPath: filename).standardizedFileURL.path
        if suppressOpenPaths.remove(standardized) != nil {
            return true
        }
        openURL(URL(fileURLWithPath: filename))
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if let webView = findWebView(in: window.contentView) {
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.stopLoading()
            webView.loadHTMLString("", baseURL: nil)
        }
        windows.removeAll { $0 === window }
        windowModels.removeValue(forKey: ObjectIdentifier(window))
        closedWindows.append(window)
    }

    private func findWebView(in view: NSView?) -> WKWebView? {
        guard let view else { return nil }
        if let webView = view as? WKWebView {
            return webView
        }
        for subview in view.subviews {
            if let found = findWebView(in: subview) {
                return found
            }
        }
        return nil
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            MarkdownWebView(html: model.html, htmlFileURL: model.htmlFileURL, readAccessURL: model.baseURL)

            Divider()

            HStack(spacing: 16) {
                Text(model.statusText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Toggle("Live Reload", isOn: $model.liveReloadEnabled)
                    .toggleStyle(.switch)

                Picker("Style", selection: $model.selectedPreset) {
                    ForEach(CssPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.menu)

                Button("Reload") {
                    model.reload()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CLI Helper")
                .font(.title2)

            Text("Install a small command-line helper so you can run `mdv file.md` from Terminal.")
                .foregroundStyle(.secondary)

            Button("Install CLI Helper") {
                model.installCLIHelper()
            }

            if !model.cliInstallStatus.isEmpty {
                Text(model.cliInstallStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 260)
    }
}

@MainActor
final class LinkRoutingDelegate: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""

        if navigationAction.navigationType == .linkActivated,
           let fragment = url.fragment,
           (scheme.isEmpty || scheme == "file") {
            let js = "var el = document.getElementById('\(fragment)'); if (el) { el.scrollIntoView({behavior: 'smooth', block: 'start'}); }"
            webView.evaluateJavaScript(js, completionHandler: nil)
            decisionHandler(.cancel)
            return
        }

        if ["http", "https"].contains(scheme) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let htmlFileURL: URL?
    let readAccessURL: URL?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        if #available(macOS 13.3, *) {
            view.isInspectable = true
        }
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if let htmlFileURL {
            let accessURL = URL(fileURLWithPath: "/")
            nsView.loadFileURL(htmlFileURL, allowingReadAccessTo: accessURL)
        } else {
            nsView.loadHTMLString(html, baseURL: readAccessURL)
        }
    }

    func makeCoordinator() -> LinkRoutingDelegate {
        LinkRoutingDelegate()
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: LinkRoutingDelegate) {
        nsView.navigationDelegate = nil
        nsView.stopLoading()
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var html: String = AppModel.placeholderHTML
    @Published var htmlFileURL: URL?
    @Published var statusText: String = "Open a Markdown file (.md)"
    @Published var liveReloadEnabled: Bool = true {
        didSet { refreshWatcher() }
    }
    @Published var selectedPreset: CssPreset = .classic {
        didSet {
            UserDefaults.standard.set(selectedPreset.rawValue, forKey: Self.presetKey)
            reload()
        }
    }

    private(set) var baseURL: URL?
    var documentURL: URL?
    private var watcher: FileWatcher?
    private let renderer = MarkdownRenderer()
    private static let presetKey = "markdownViewerPreset"
    private var tempHTMLURL: URL?

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.presetKey),
           let preset = CssPreset(rawValue: raw) {
            selectedPreset = preset
        }
    }

    func open(path: String) {
        open(url: URL(fileURLWithPath: path))
    }

    func open(url: URL) {
        let standardized = url.standardizedFileURL
        documentURL = standardized
        baseURL = standardized.deletingLastPathComponent()
        load(url: standardized)
        refreshWatcher()
    }

    func reload() {
        guard let url = documentURL else { return }
        load(url: url)
    }

    private func refreshWatcher() {
        guard liveReloadEnabled, let url = documentURL else {
            watcher = nil
            return
        }
        watcher = FileWatcher(url: url) { [weak self] in
            DispatchQueue.main.async {
                self?.reload()
            }
        }
    }

    private func load(url: URL) {
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let css = loadCss()
            self.html = renderer.render(markdown: markdown, css: css, baseURL: baseURL)
            self.htmlFileURL = writeHTMLToTemp(self.html)
            self.statusText = url.lastPathComponent
        } catch {
            html = renderer.wrap(body: "<p>Failed to load markdown.</p>", css: loadCss(), baseURL: baseURL)
            htmlFileURL = nil
            statusText = "Error: \(error.localizedDescription)"
        }
    }

    private func loadCss() -> String {
        guard let url = Bundle.module.url(forResource: selectedPreset.resourceName, withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8) else {
            return Self.fallbackCss
        }
        return css
    }

    private static let placeholderHTML = """
    <!doctype html>
    <html><body><article class=\"md\"><h1>Markdown Viewer</h1><p>Open a .md file to begin.</p></article></body></html>
    """

    private static let fallbackCss = """
    body { font-family: Georgia, serif; padding: 32px; }
    """

    private func writeHTMLToTemp(_ html: String) -> URL? {
        do {
            let fileURL = try tempHTMLFileURL()
            try html.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }

    private func tempHTMLFileURL() throws -> URL {
        if let tempHTMLURL {
            return tempHTMLURL
        }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("mdv", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let fileURL = base.appendingPathComponent(UUID().uuidString).appendingPathExtension("html")
        tempHTMLURL = fileURL
        return fileURL
    }

    var hasDocument: Bool {
        documentURL != nil
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var cliInstallStatus: String = ""

    func installCLIHelper() {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let localBin = URL(fileURLWithPath: "/usr/local/bin", isDirectory: true)
        let userBin = home.appendingPathComponent("bin", isDirectory: true)
        let appBundlePath = Bundle.main.bundleURL.path
        let script = """
        #!/bin/sh
        exec open -a "\(appBundlePath)" "$@"
        """

        do {
            try fileManager.createDirectory(at: localBin, withIntermediateDirectories: true)
            let scriptURL = localBin.appendingPathComponent("mdv")
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            chmod(scriptURL.path, 0o755)
            cliInstallStatus = "Installed to /usr/local/bin/mdv."
        } catch {
            do {
                try fileManager.createDirectory(at: userBin, withIntermediateDirectories: true)
                let scriptURL = userBin.appendingPathComponent("mdv")
                try script.write(to: scriptURL, atomically: true, encoding: .utf8)
                chmod(scriptURL.path, 0o755)

                let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
                if !path.split(separator: ":").contains(Substring(userBin.path)) {
                    cliInstallStatus = "Installed to ~/bin/mdv. Add ~/bin to your PATH."
                } else {
                    cliInstallStatus = "Installed to ~/bin/mdv."
                }
            } catch {
                cliInstallStatus = "Install failed: \(error.localizedDescription)"
            }
        }
    }

    private func resolvedExecutablePath() -> String {
        if let execURL = Bundle.main.executableURL {
            return execURL.path
        }
        return "/usr/bin/env mdv"
    }
}

enum CssPreset: String, CaseIterable, Identifiable {
    case classic
    case modern
    case minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .modern: return "Modern"
        case .minimal: return "Minimal"
        }
    }

    var resourceName: String {
        rawValue
    }
}

final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "mdviewer.filewatcher")
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        start()
    }

    deinit {
        stop()
    }

    private func start() {
        stop()
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )

        source.setEventHandler { [weak self, weak source] in
            guard let self else { return }
            let flags = source?.data ?? []
            if flags.contains(.delete) || flags.contains(.rename) {
                self.start()
            }
            self.onChange()
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.descriptor >= 0 {
                close(self.descriptor)
                self.descriptor = -1
            }
        }

        self.source = source
        source.resume()
    }

    private func stop() {
        source?.cancel()
        source = nil
    }
}
