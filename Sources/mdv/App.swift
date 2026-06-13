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
    private let appVersion = "0.5.0"

    static func main() {
        let app = NSApplication.shared
        let delegate = AppMain()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        var args = CommandLine.arguments.dropFirst()
        if args.contains("--settings") {
            args.removeAll { $0 == "--settings" }
            showSettingsWindow()
        }
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
            withTitle: "Hide \(appDisplayName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthersItem = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
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
        fileMenu.addItem(.separator())
        fileMenu.addItem(
            withTitle: "Print…",
            action: #selector(printDocument(_:)),
            keyEquivalent: "p"
        )
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(
            withTitle: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        editMenu.addItem(
            withTitle: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "Z"
        )
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "Find…",
            action: #selector(findInDocument(_:)),
            keyEquivalent: "f"
        )
        editMenu.addItem(
            withTitle: "Find Next",
            action: #selector(findNext(_:)),
            keyEquivalent: "g"
        )
        editMenu.addItem(
            withTitle: "Find Previous",
            action: #selector(findPrevious(_:)),
            keyEquivalent: "G"
        )
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

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

    private func keyWindowModel() -> AppModel? {
        guard let keyWindow = NSApplication.shared.keyWindow else { return nil }
        return windowModels[ObjectIdentifier(keyWindow)]
    }

    @objc
    @MainActor
    private func findInDocument(_ sender: Any?) {
        keyWindowModel()?.showFindBar()
    }

    @objc
    @MainActor
    private func findNext(_ sender: Any?) {
        keyWindowModel()?.findNext()
    }

    @objc
    @MainActor
    private func findPrevious(_ sender: Any?) {
        keyWindowModel()?.findPrevious()
    }

    @objc
    @MainActor
    private func printDocument(_ sender: Any?) {
        guard let window = NSApplication.shared.keyWindow,
              let webView = findWebView(in: window.contentView) else { return }

        let printInfo = NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false

        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        // WebKit's print view starts zero-sized and prints blank pages
        // unless it's given a real frame up front.
        operation.view?.frame = NSRect(origin: .zero, size: printInfo.paperSize)
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
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
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Settings"
        window.titlebarAppearsTransparent = true
        // Keep a strong reference without letting close() release the window
        // out from under us — reopening would crash on a dangling pointer.
        window.isReleasedWhenClosed = false
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
        model.onDocumentOpened = { [weak window, weak model] url in
            window?.title = model?.documentTitle ?? url.lastPathComponent
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
            targetWindow.title = targetModel.documentTitle ?? standardized.lastPathComponent
            targetWindow.representedURL = standardized
            NSDocumentController.shared.noteNewRecentDocumentURL(standardized)
            return
        }

        // Window first so onDocumentOpened is wired before open() fires it.
        let model = AppModel()
        _ = createWindow(model: model)
        model.open(url: standardized)
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
            if model.isFindBarVisible {
                FindBarView(model: model)
                Divider()
            }

            MarkdownWebView(
                html: model.html,
                htmlFileURL: model.htmlFileURL,
                readAccessURL: model.baseURL,
                tocScrollRequest: model.tocScrollRequest,
                findRequest: model.findRequest,
                onFileDrop: openDropped(url:),
                onFindResult: { found in model.findNotFound = !found }
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
                window.title = model.documentTitle ?? standardized.lastPathComponent
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

struct FindBarView: View {
    @ObservedObject var model: AppModel
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find in document", text: $model.findQuery)
                .textFieldStyle(.plain)
                .focused($isFieldFocused)
                .onSubmit { model.findNext() }

            if model.findNotFound && !model.findQuery.isEmpty {
                Text("Not found")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button {
                model.findPrevious()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .help("Find Previous")

            Button {
                model.findNext()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .help("Find Next")

            Button("Done") {
                model.closeFindBar()
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .onAppear { isFieldFocused = true }
        .onChange(of: model.findActivation) { _ in isFieldFocused = true }
        .onChange(of: model.findQuery) { _ in model.findQueryChanged() }
        .onExitCommand { model.closeFindBar() }
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

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case appearance
    case commandLine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .commandLine: return "Command Line"
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintbrush.fill"
        case .commandLine: return "terminal.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .appearance: return .blue
        case .commandLine: return .indigo
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var selection: SettingsSection? = .appearance

    private var current: SettingsSection { selection ?? .appearance }

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsSection.allCases, selection: $selection) { section in
                SettingsSidebarRow(section: section)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(width: 190)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Text(current.title)
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 4)

                Group {
                    switch current {
                    case .appearance:
                        AppearanceSettingsPane(model: model)
                    case .commandLine:
                        CommandLineSettingsPane(model: model)
                    }
                }
                .groupedFormStyle()

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 680, height: 400)
    }
}

private struct SettingsSidebarRow: View {
    let section: SettingsSection

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(section.iconColor)
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: section.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                )
            Text(section.title)
        }
        .padding(.vertical, 2)
    }
}

struct AppearanceSettingsPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker("Default style", selection: $model.defaultPreset) {
                    ForEach(CssPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }

                HStack {
                    Text("Font size")
                    Spacer()
                    Slider(value: $model.fontSize, in: 12...24, step: 1)
                        .frame(width: 180)
                    Text("\(Int(model.fontSize)) px")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
            } footer: {
                Text("Changes apply to all open windows immediately.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CommandLineSettingsPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Terminal command")
                        Text("Install a helper so you can run `mdv file.md` from Terminal.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Install…") {
                        model.installCLIHelper()
                    }
                }
            } footer: {
                if !model.cliInstallStatus.isEmpty {
                    Text(model.cliInstallStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private extension View {
    // Grouped form (System Settings look) needs macOS 13; older systems
    // fall back to the default form layout.
    @ViewBuilder
    func groupedFormStyle() -> some View {
        if #available(macOS 13.0, *) {
            formStyle(.grouped)
        } else {
            self
        }
    }
}

@MainActor
final class LinkRoutingDelegate: NSObject, WKNavigationDelegate {
    private var pendingScrollAnchor: String?
    private var lastScrollRequestID: UUID?
    private var lastFindRequestID: UUID?
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

    func handle(findRequest: FindRequest?, in webView: WKWebView, onResult: @escaping @MainActor (Bool) -> Void) {
        guard let findRequest, findRequest.id != lastFindRequestID else { return }
        lastFindRequestID = findRequest.id

        let configuration = WKFindConfiguration()
        configuration.backwards = findRequest.backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        webView.find(findRequest.query, configuration: configuration) { result in
            onResult(result.matchFound)
        }
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
    let findRequest: FindRequest?
    let onFileDrop: (URL) -> Void
    let onFindResult: @MainActor (Bool) -> Void

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
        context.coordinator.handle(findRequest: findRequest, in: nsView, onResult: onFindResult)
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
    @Published var isFindBarVisible: Bool = false
    @Published var findQuery: String = ""
    @Published var findRequest: FindRequest?
    @Published var findNotFound: Bool = false
    @Published var findActivation = UUID()

    private(set) var documentTitle: String?
    private(set) var baseURL: URL?
    var documentURL: URL?
    private var watcher: FileWatcher?
    private let renderer = MarkdownRenderer()
    static let presetKey = "markdownViewerPreset"
    static let fontSizeKey = "markdownViewerFontSize"
    nonisolated static let defaultFontSize: Double = 16
    private static let sidebarVisibleKey = "markdownViewerSidebarVisible"
    private var tempHTMLURL: URL?
    // nonisolated(unsafe): only written once in init, read in deinit;
    // NotificationCenter.removeObserver is thread-safe.
    private nonisolated(unsafe) var appearanceObserver: NSObjectProtocol?
    var onDocumentOpened: ((URL) -> Void)?

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.presetKey),
           let preset = CssPreset(rawValue: raw) {
            selectedPreset = preset
        }
        isSidebarVisible = UserDefaults.standard.bool(forKey: Self.sidebarVisibleKey)
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .mdvAppearanceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.appearanceSettingsChanged()
            }
        }
    }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    private func appearanceSettingsChanged() {
        if let raw = UserDefaults.standard.string(forKey: Self.presetKey),
           let preset = CssPreset(rawValue: raw),
           preset != selectedPreset {
            selectedPreset = preset // didSet re-renders
        } else {
            reload()
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
            let raw = try String(contentsOf: url, encoding: .utf8)
            let document = Self.stripFrontmatter(from: raw)
            documentTitle = document.title
            let css = loadCss()
            self.html = renderer.render(markdown: document.markdown, css: css, baseURL: baseURL)
            self.htmlFileURL = writeHTMLToTemp(self.html)
            self.tableOfContents = Self.extractTableOfContents(from: document.markdown)
            self.statusText = url.lastPathComponent
        } catch {
            html = renderer.wrap(body: "<p>Failed to load markdown.</p>", css: loadCss(), baseURL: baseURL)
            htmlFileURL = nil
            documentTitle = nil
            tableOfContents = []
            statusText = "Error: \(error.localizedDescription)"
        }
    }

    // YAML frontmatter is machine metadata — readers shouldn't see it rendered
    // as a literal `---` block. Only strip when the block actually looks like
    // YAML; a `---` thematic break followed by prose must stay untouched.
    nonisolated static func stripFrontmatter(from markdown: String) -> (markdown: String, title: String?) {
        let lines = markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        guard lines.count > 1,
              lines[0].trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return (markdown, nil)
        }

        var closeIndex: Int?
        for index in 1..<lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "---" || trimmed == "..." {
                closeIndex = index
                break
            }
        }
        guard let closeIndex else { return (markdown, nil) }

        let block = lines[1..<closeIndex]
        var title: String?
        for line in block {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let isIndented = line.hasPrefix(" ") || line.hasPrefix("\t")
            if isIndented || trimmed.hasPrefix("- ") || trimmed == "-" { continue }
            // Top-level lines must be `key:` pairs, or the block isn't YAML.
            guard let colon = trimmed.firstIndex(of: ":"),
                  Self.isYamlKey(trimmed[trimmed.startIndex..<colon]) else {
                return (markdown, nil)
            }
            if title == nil, trimmed[trimmed.startIndex..<colon].lowercased() == "title" {
                var value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if value.count >= 2,
                   (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                title = value.isEmpty ? nil : value
            }
        }

        let body = lines[(closeIndex + 1)...].joined(separator: "\n")
        return (body, title)
    }

    private nonisolated static func isYamlKey(_ key: Substring) -> Bool {
        !key.isEmpty && key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." || $0 == " " }
    }

    func showFindBar() {
        isFindBarVisible = true
        findActivation = UUID()
    }

    func closeFindBar() {
        isFindBarVisible = false
        findNotFound = false
    }

    func findNext() {
        submitFind(backwards: false)
    }

    func findPrevious() {
        submitFind(backwards: true)
    }

    func findQueryChanged() {
        findNotFound = false
        guard !findQuery.isEmpty else { return }
        submitFind(backwards: false)
    }

    private func submitFind(backwards: Bool) {
        guard !findQuery.isEmpty else { return }
        findRequest = FindRequest(query: findQuery, backwards: backwards)
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
        let base: String
        if let url = Bundle.module.url(forResource: selectedPreset.resourceName, withExtension: "css"),
           let css = try? String(contentsOf: url, encoding: .utf8) {
            base = css
        } else {
            base = Self.fallbackCss
        }
        let size = Self.effectiveFontSize(stored: UserDefaults.standard.double(forKey: Self.fontSizeKey))
        return base + "\n" + Self.fontSizeCss(size)
    }

    // Presets size text in rem, so scaling the root font-size scales everything.
    nonisolated static func fontSizeCss(_ size: Double) -> String {
        "html { font-size: \(Int(size))px; }"
    }

    nonisolated static func effectiveFontSize(stored: Double) -> Double {
        stored > 0 ? stored : defaultFontSize
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

struct FindRequest: Equatable {
    let id = UUID()
    let query: String
    let backwards: Bool
}

extension Notification.Name {
    static let mdvAppearanceChanged = Notification.Name("mdvAppearanceChanged")
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var cliInstallStatus: String = ""
    @Published var defaultPreset: CssPreset {
        didSet {
            guard defaultPreset != oldValue else { return }
            UserDefaults.standard.set(defaultPreset.rawValue, forKey: AppModel.presetKey)
            NotificationCenter.default.post(name: .mdvAppearanceChanged, object: nil)
        }
    }
    @Published var fontSize: Double {
        didSet {
            guard fontSize != oldValue else { return }
            UserDefaults.standard.set(fontSize, forKey: AppModel.fontSizeKey)
            NotificationCenter.default.post(name: .mdvAppearanceChanged, object: nil)
        }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: AppModel.presetKey),
           let preset = CssPreset(rawValue: raw) {
            defaultPreset = preset
        } else {
            defaultPreset = .classic
        }
        fontSize = AppModel.effectiveFontSize(
            stored: UserDefaults.standard.double(forKey: AppModel.fontSizeKey)
        )
    }

    func installCLIHelper() {
        // Bundle.main.bundleURL only points at the .app when launched from one;
        // a `swift run` dev build resolves to .build/…/debug, which `open -a` rejects.
        guard let appBundleURL = Self.resolvedAppBundleURL(
            bundleURL: Bundle.main.bundleURL,
            workspaceLookup: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        ) else {
            cliInstallStatus = "Install failed. Couldn't locate mdv.app — run this from the installed app."
            return
        }

        cliInstallStatus = "Installing CLI helper…"
        let appBundlePath = appBundleURL.path

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let status = Self.installCLIHelperStatus(appBundlePath: appBundlePath)
            DispatchQueue.main.async {
                self?.cliInstallStatus = status
            }
        }
    }

    nonisolated static func resolvedAppBundleURL(bundleURL: URL, workspaceLookup: (String) -> URL?) -> URL? {
        if bundleURL.pathExtension == "app" {
            return bundleURL
        }
        return workspaceLookup("jp.co.xenocode.mdv")
    }

    nonisolated static func cliScript(appPath: String) -> String {
        """
        #!/bin/sh
        exec open -a "\(appPath)" "$@"
        """
    }

    // Runs on a background queue — must not inherit the class's @MainActor
    // isolation or Swift 6's runtime check traps (_dispatch_assert_queue_fail).
    private nonisolated static func installCLIHelperStatus(appBundlePath: String) -> String {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let script = cliScript(appPath: appBundlePath)
        let installDirs: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
            home.appendingPathComponent("bin", isDirectory: true)
        ]

        var installedAt: URL?
        var failures: [String] = []

        for dir in installDirs {
            do {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
                let scriptURL = dir.appendingPathComponent("mdv")
                try script.write(to: scriptURL, atomically: true, encoding: .utf8)
                chmod(scriptURL.path, 0o755)
                installedAt = scriptURL
                break
            } catch {
                failures.append("\(dir.path): \(error.localizedDescription)")
            }
        }

        guard let installedAt else {
            let details = failures.isEmpty ? "unknown error" : failures.joined(separator: " | ")
            return "Install failed. Could not write helper. \(details)"
        }

        let zshPath = commandPathFromShell(
            executable: "/bin/zsh",
            args: ["-lic", "command -v mdv 2>/dev/null || true"]
        )
        let bashPath = commandPathFromShell(
            executable: "/bin/bash",
            args: ["-lc", "command -v mdv 2>/dev/null || true"]
        )
        let verified = [("zsh", zshPath), ("bash", bashPath)]
            .compactMap { shell, path in path?.isEmpty == false ? "\(shell): \(path!)" : nil }

        if !verified.isEmpty {
            return "Installed to \(prettyPath(installedAt.path)). Visible in \(verified.joined(separator: ", "))."
        }

        let parent = installedAt.deletingLastPathComponent().path
        return """
        Installed to \(prettyPath(installedAt.path)), but new shells can't find `mdv` yet.
        Add this to ~/.zprofile, then open a new terminal:
        export PATH="\(parent):$PATH"
        """
    }

    private nonisolated static func commandPathFromShell(executable: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : path
        } catch {
            return nil
        }
    }

    private nonisolated static func prettyPath(_ absolutePath: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if absolutePath.hasPrefix(home + "/") {
            return "~/" + absolutePath.dropFirst(home.count + 1)
        }
        return absolutePath
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
