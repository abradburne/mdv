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
    private let githubRepo = "abradburne/mdv"
    private let appVersion = "0.3.0"

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
        Task { await checkForUpdates() }
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

    private func checkForUpdates() async {
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        let url = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let releaseURL = json["html_url"] as? String else { return }

        let latest = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? appVersion

        guard versionIsNewer(latest, than: current) else { return }

        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = "Update Available"
            alert.informativeText = "mdv \(latest) is available (you have \(current))."
            alert.addButton(withTitle: "Download Update")
            alert.addButton(withTitle: "Not Now")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: releaseURL)!)
            }
        }
    }

    private func versionIsNewer(_ latest: String, than current: String) -> Bool {
        let parse: (String) -> [Int] = { $0.split(separator: ".").compactMap { Int($0) } }
        let l = parse(latest), c = parse(current)
        for i in 0..<max(l.count, c.count) {
            let lv = i < l.count ? l[i] : 0
            let cv = i < c.count ? c[i] : 0
            if lv != cv { return lv > cv }
        }
        return false
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

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let toggleSidebarItem = NSMenuItem(
            title: "Toggle Sidebar",
            action: #selector(toggleSidebar(_:)),
            keyEquivalent: "s"
        )
        toggleSidebarItem.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(toggleSidebarItem)
        viewMenu.addItem(.separator())
        let zoomInItem = NSMenuItem(title: "Zoom In", action: #selector(zoomIn(_:)), keyEquivalent: "+")
        viewMenu.addItem(zoomInItem)
        let zoomOutItem = NSMenuItem(title: "Zoom Out", action: #selector(zoomOut(_:)), keyEquivalent: "-")
        viewMenu.addItem(zoomOutItem)
        let zoomResetItem = NSMenuItem(title: "Actual Size", action: #selector(zoomReset(_:)), keyEquivalent: "0")
        viewMenu.addItem(zoomResetItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

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
        let version = info?["CFBundleShortVersionString"] as? String ?? appVersion
        let build = info?["CFBundleVersion"] as? String
        let versionString = build.map { b in b != version ? "\(version) (\(b))" : version } ?? version
        let credits = NSAttributedString(string: "Super Simple Markdown Viewer\n© 2026 Alan Bradburne · alanb@hey.com")

        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: appDisplayName,
            .applicationVersion: versionString,
            .version: "",
            .credits: credits
        ]
        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
    }

    private func keyWindowWebView() -> WKWebView? {
        findWebView(in: NSApplication.shared.keyWindow?.contentView)
    }

    @objc
    @MainActor
    private func toggleSidebar(_ sender: Any?) {
        if NSApplication.shared.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: sender) {
            return
        }
        guard let keyWindow = NSApplication.shared.keyWindow,
              let model = windowModels[ObjectIdentifier(keyWindow)] else { return }
        model.isSidebarVisible.toggle()
    }

    @objc
    @MainActor
    private func zoomIn(_ sender: Any?) {
        guard let wv = keyWindowWebView() else { return }
        wv.pageZoom = min(wv.pageZoom + 0.1, 3.0)
    }

    @objc
    @MainActor
    private func zoomOut(_ sender: Any?) {
        guard let wv = keyWindowWebView() else { return }
        wv.pageZoom = max(wv.pageZoom - 0.1, 0.5)
    }

    @objc
    @MainActor
    private func zoomReset(_ sender: Any?) {
        keyWindowWebView()?.pageZoom = 1.0
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
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = appDisplayName
        window.toolbar = NSToolbar(identifier: "mdv-toolbar")
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.delegate = self
        windows.append(window)
        windowModels[ObjectIdentifier(window)] = model
        model.onDocumentOpened = { [weak window] url in
            window?.title = url.lastPathComponent
            window?.representedURL = url
        }
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
    @State private var isDropTargeted: Bool = false

    var body: some View {
        Group {
            if #available(macOS 13.0, *) {
                modernSplitView
            } else {
                legacySplitView
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.tint.opacity(0.65), lineWidth: 2)
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleDrop(providers:))
    }

    @available(macOS 13.0, *)
    private var modernSplitView: some View {
        NavigationSplitView {
            TOCSidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            detailPane
        }
    }

    private var legacySplitView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Group {
                if model.isSidebarVisible {
                    HSplitView {
                        TOCSidebarView(model: model)
                            .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)
                            .padding(.leading, 12)
                            .padding(.vertical, 12)
                        detailPane
                    }
                } else {
                    detailPane
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    model.isSidebarVisible.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(model.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
            }
        }
    }

    private var detailPane: some View {
        VStack(spacing: 0) {
            MarkdownWebView(
                html: model.html,
                htmlFileURL: model.htmlFileURL,
                readAccessURL: model.baseURL,
                tocScrollRequest: model.tocScrollRequest,
                onFileDrop: openDropped(url:)
            )

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
            .padding(.vertical, 10)
            .glassSurface(cornerRadius: 14)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            if let data = item as? Data,
               let url = NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL? {
                Task { @MainActor in
                    openDropped(url: url)
                }
                return
            }
            if let url = item as? URL {
                Task { @MainActor in
                    openDropped(url: url)
                }
                return
            }
            if let path = item as? String {
                Task { @MainActor in
                    openDropped(url: URL(fileURLWithPath: path))
                }
            }
        }

        return true
    }

    private func openDropped(url: URL) {
        let standardized = url.standardizedFileURL
        guard isMarkdownFile(url: standardized) else { return }

        Task { @MainActor in
            model.open(url: standardized)
            if let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
                window.title = standardized.lastPathComponent
                window.representedURL = standardized
            }
            NSDocumentController.shared.noteNewRecentDocumentURL(standardized)
        }
    }

    private func isMarkdownFile(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["md", "markdown", "mdown", "mkd", "mkdn"].contains(ext)
    }
}

struct TOCSidebarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        List {
            if model.tableOfContents.isEmpty {
                Text("No headings found")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.tableOfContents) { section in
                    Section {
                        ForEach(section.children) { child in
                            Button {
                                model.scrollToHeading(anchor: child.anchor)
                            } label: {
                                Text(child.title)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Button {
                            model.scrollToHeading(anchor: section.anchor)
                        } label: {
                            Text(section.title)
                                .font(.headline)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Contents")
        .frame(minWidth: 220, idealWidth: 260)
    }
}

private struct GlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.46),
                                Color.white.opacity(0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
            .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
    }
}

private extension View {
    func glassSurface(cornerRadius: CGFloat) -> some View {
        modifier(GlassSurfaceModifier(cornerRadius: cornerRadius))
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
    private var pendingScrollAnchor: String?
    private var lastScrollRequestID: UUID?
    private var lastLoadedHTML: String?
    private var lastLoadedFileURL: URL?

    func loadIfNeeded(webView: WKWebView, html: String, htmlFileURL: URL?, readAccessURL: URL?) {
        guard html != lastLoadedHTML || htmlFileURL != lastLoadedFileURL else { return }
        lastLoadedHTML = html
        lastLoadedFileURL = htmlFileURL

        if let htmlFileURL {
            let accessURL = URL(fileURLWithPath: "/")
            webView.loadFileURL(htmlFileURL, allowingReadAccessTo: accessURL)
        } else {
            webView.loadHTMLString(html, baseURL: readAccessURL)
        }
    }

    func handle(scrollRequest: TOCScrollRequest?, in webView: WKWebView) {
        guard let scrollRequest, scrollRequest.id != lastScrollRequestID else { return }
        lastScrollRequestID = scrollRequest.id
        scrollToAnchor(scrollRequest.anchor, in: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let anchor = pendingScrollAnchor else { return }
        pendingScrollAnchor = nil
        scrollToAnchor(anchor, in: webView)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""

        if navigationAction.navigationType == .linkActivated,
           let fragment = url.fragment,
           (scheme.isEmpty || scheme == "file") {
            scrollToAnchor(fragment, in: webView)
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

    private func scrollToAnchor(_ anchor: String, in webView: WKWebView) {
        if webView.isLoading {
            pendingScrollAnchor = anchor
            return
        }
        let escaped = anchor
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let js = "var el = document.getElementById('\(escaped)'); if (el) { el.scrollIntoView({behavior: 'smooth', block: 'start'}); }"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let htmlFileURL: URL?
    let readAccessURL: URL?
    let tocScrollRequest: TOCScrollRequest?
    let onFileDrop: (URL) -> Void

    func makeNSView(context: Context) -> DropAwareWebView {
        let config = WKWebViewConfiguration()
        let view = DropAwareWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        view.onFileDrop = onFileDrop
        if #available(macOS 13.3, *) {
            view.isInspectable = true
        }
        return view
    }

    func updateNSView(_ nsView: DropAwareWebView, context: Context) {
        nsView.onFileDrop = onFileDrop
        context.coordinator.loadIfNeeded(
            webView: nsView,
            html: html,
            htmlFileURL: htmlFileURL,
            readAccessURL: readAccessURL
        )
        context.coordinator.handle(scrollRequest: tocScrollRequest, in: nsView)
    }

    func makeCoordinator() -> LinkRoutingDelegate {
        LinkRoutingDelegate()
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: LinkRoutingDelegate) {
        nsView.navigationDelegate = nil
        nsView.stopLoading()
    }
}

final class DropAwareWebView: WKWebView {
    var onFileDrop: ((URL) -> Void)?
    private static let legacyFilenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        registerForDraggedTypes([.fileURL, .URL, Self.legacyFilenamesType, .string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        firstFileURL(from: sender.draggingPasteboard) == nil ? [] : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        firstFileURL(from: sender.draggingPasteboard) == nil ? [] : .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        firstFileURL(from: sender.draggingPasteboard) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = firstFileURL(from: sender.draggingPasteboard) else { return false }
        onFileDrop?(url)
        return true
    }

    private func firstFileURL(from pasteboard: NSPasteboard) -> URL? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let first = urls.first {
            return first
        }

        if let names = pasteboard.propertyList(forType: Self.legacyFilenamesType) as? [String],
           let first = names.first {
            return URL(fileURLWithPath: first)
        }

        if let string = pasteboard.string(forType: .fileURL) ?? pasteboard.string(forType: .URL),
           let url = URL(string: string), url.isFileURL {
            return url
        }

        return nil
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
    @Published var isSidebarVisible: Bool = false {
        didSet { UserDefaults.standard.set(isSidebarVisible, forKey: Self.sidebarVisibleKey) }
    }
    @Published var tableOfContents: [TOCSection] = []
    @Published var tocScrollRequest: TOCScrollRequest?

    private(set) var baseURL: URL?
    var documentURL: URL?
    private var watcher: FileWatcher?
    private let renderer = MarkdownRenderer()
    private static let presetKey = "markdownViewerPreset"
    private static let sidebarVisibleKey = "markdownViewerSidebarVisible"
    private var tempHTMLURL: URL?
    var onDocumentOpened: ((URL) -> Void)?

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.presetKey),
           let preset = CssPreset(rawValue: raw) {
            selectedPreset = preset
        }
        isSidebarVisible = UserDefaults.standard.bool(forKey: Self.sidebarVisibleKey)
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
        onDocumentOpened?(standardized)
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
            self.tableOfContents = Self.extractTableOfContents(from: markdown)
            self.statusText = url.lastPathComponent
        } catch {
            html = renderer.wrap(body: "<p>Failed to load markdown.</p>", css: loadCss(), baseURL: baseURL)
            htmlFileURL = nil
            tableOfContents = []
            statusText = "Error: \(error.localizedDescription)"
        }
    }

    func scrollToHeading(anchor: String) {
        tocScrollRequest = TOCScrollRequest(anchor: anchor)
    }

    static func extractTableOfContents(from markdown: String) -> [TOCSection] {
        var sections: [TOCSection] = []
        var slugCounts: [String: Int] = [:]
        var inCodeFence = false

        for rawLine in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inCodeFence.toggle()
                continue
            }
            if inCodeFence { continue }

            guard let heading = parseHeading(from: line), [1, 2].contains(heading.level) else { continue }

            let baseSlug = slugified(heading.title)
            let anchor = uniqueSlug(for: baseSlug, counts: &slugCounts)
            if heading.level == 1 {
                sections.append(TOCSection(title: heading.title, anchor: anchor, children: []))
            } else if !sections.isEmpty {
                let child = TOCChild(title: heading.title, anchor: anchor)
                sections[sections.count - 1].children.append(child)
            }
        }

        return sections
    }

    private static func parseHeading(from line: String) -> (level: Int, title: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }

        var level = 0
        for char in trimmed {
            if char == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level) else { return nil }

        let index = trimmed.index(trimmed.startIndex, offsetBy: level)
        guard index < trimmed.endIndex, trimmed[index].isWhitespace else { return nil }

        var title = trimmed[index...].trimmingCharacters(in: .whitespaces)
        while title.hasSuffix("#") {
            title.removeLast()
            title = title.trimmingCharacters(in: .whitespaces)
        }

        guard !title.isEmpty else { return nil }
        return (level, title)
    }

    private static func slugified(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = String(trimmed.map { char in
            if char.isASCII, (char.isLetter || char.isNumber || char == "-" || char.isWhitespace) {
                return char
            }
            return " "
        })
        let pieces = filtered
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .map(String.init)
        return pieces.isEmpty ? "section" : pieces.joined(separator: "-")
    }

    private static func uniqueSlug(for base: String, counts: inout [String: Int]) -> String {
        if let count = counts[base] {
            counts[base] = count + 1
            return "\(base)-\(count)"
        }
        counts[base] = 1
        return base
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
    <html>
      <head>
        <meta charset=\"utf-8\" />
        <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
        <style>
          :root { color-scheme: light dark; }
          html, body { height: 100%; margin: 0; }
          body {
            font-family: -apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Helvetica Neue\", sans-serif;
            background:
              radial-gradient(900px 500px at -10% -10%, rgba(109, 196, 255, 0.22), transparent 60%),
              radial-gradient(800px 420px at 110% 120%, rgba(168, 144, 255, 0.18), transparent 55%),
              linear-gradient(135deg, rgba(250, 250, 252, 0.95), rgba(240, 242, 246, 0.88));
            color: rgba(28, 28, 30, 0.92);
            display: grid;
            place-items: center;
            padding: 24px;
            box-sizing: border-box;
          }
          .empty {
            width: min(640px, calc(100vw - 48px));
            border-radius: 20px;
            padding: 28px 30px;
            background: rgba(255, 255, 255, 0.60);
            border: 1px solid rgba(255, 255, 255, 0.66);
            box-shadow: 0 18px 40px rgba(0, 0, 0, 0.12);
            backdrop-filter: blur(12px);
            box-sizing: border-box;
          }
          h1 {
            margin: 0 0 10px;
            font-size: clamp(32px, 5.1vw, 44px);
            line-height: 1.08;
            letter-spacing: -0.04em;
            font-weight: 760;
          }
          p {
            margin: 0;
            font-size: 18px;
            line-height: 1.55;
            color: rgba(44, 44, 46, 0.80);
          }
          ul {
            margin: 16px 0 0;
            padding-left: 20px;
            color: rgba(44, 44, 46, 0.78);
            font-size: 15px;
            line-height: 1.5;
          }
          code {
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, monospace;
            font-size: 0.92em;
            padding: 2px 6px;
            border-radius: 6px;
            background: rgba(0, 0, 0, 0.07);
          }
          @media (prefers-color-scheme: dark) {
            body {
              background:
                radial-gradient(900px 500px at -10% -10%, rgba(106, 167, 255, 0.20), transparent 60%),
                radial-gradient(800px 420px at 110% 120%, rgba(170, 140, 255, 0.18), transparent 55%),
                linear-gradient(135deg, rgba(23, 23, 26, 0.95), rgba(31, 32, 37, 0.92));
              color: rgba(245, 245, 247, 0.95);
            }
            .empty {
              background: rgba(28, 28, 31, 0.58);
              border-color: rgba(255, 255, 255, 0.18);
              box-shadow: 0 18px 40px rgba(0, 0, 0, 0.35);
            }
            p, ul { color: rgba(235, 235, 240, 0.80); }
            code { background: rgba(255, 255, 255, 0.12); }
          }
          @media (max-width: 720px) {
            .empty {
              padding: 22px 20px;
              border-radius: 16px;
            }
            h1 { font-size: clamp(28px, 7.5vw, 38px); }
            p { font-size: 16px; }
            ul { font-size: 14px; }
          }
        </style>
      </head>
      <body>
        <article class=\"empty\">
          <h1>Markdown Viewer</h1>
          <p>Drop a markdown file here, or press <code>Cmd+O</code> to open one.</p>
          <ul>
            <li>Use the sidebar button to browse headings.</li>
            <li>Toggle live reload for instant updates while editing.</li>
          </ul>
        </article>
      </body>
    </html>
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

struct TOCSection: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let anchor: String
    var children: [TOCChild]
}

struct TOCChild: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let anchor: String
}

struct TOCScrollRequest: Equatable {
    let id = UUID()
    let anchor: String
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
        nohup open -g -a "\(appBundlePath)" "$@" >/dev/null 2>&1 &
        exit 0
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
