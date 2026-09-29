import AppKit
import SwiftUI
import Combine
import IslandCore

@MainActor
final class IslandController: NSObject, NSPopoverDelegate {
    let model: IslandModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let presentation = IslandPresentation()
    private var observation: AnyCancellable?
    private var lastIndicator: IslandIndicator?
    private let notchPanel = NotchStatusPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var notchGeometry: NotchGeometry?

    init(model: IslandModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        notchPanel.backgroundColor = .clear; notchPanel.isOpaque = false; notchPanel.hasShadow = false
        notchPanel.level = .statusBar; notchPanel.hidesOnDeactivate = false; notchPanel.isMovable = false
        notchPanel.isReleasedWhenClosed = false
        notchPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: IslandView(model: model, presentation: presentation))
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        }
        model.openThread = { [weak self] row in self?.open(row) }
        model.closeOverview = { [weak self] in self?.popover.performClose(nil) }
        model.changed = { [weak self] in self?.refresh() }
        observation = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(updateDisplay), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateDisplay), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateDisplay), name: NSWorkspace.didWakeNotification, object: nil)
        updateDisplay()
        refresh()
    }

    @objc private func updateDisplay() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        let geometry = screen.flatMap {
            NotchGeometry(screen: $0.frame, visible: $0.visibleFrame, safeTop: $0.safeAreaInsets.top,
                          left: $0.auxiliaryTopLeftArea, right: $0.auxiliaryTopRightArea, scale: $0.backingScaleFactor)
        }
        guard geometry != notchGeometry || notchPanel.contentView == nil else { return }
        popover.close()
        notchGeometry = geometry
        if let geometry {
            let host = NSHostingView(rootView: NotchStatusView(model: model, geometry: geometry) { [weak self] in self?.toggleOverview() })
            host.sizingOptions = []
            notchPanel.contentView = host
            notchPanel.setFrame(geometry.frame, display: true)
            notchPanel.orderFrontRegardless()
            statusItem.isVisible = false
        } else {
            notchPanel.orderOut(nil)
            statusItem.isVisible = true
        }
    }

    private func toggleOverview() {
        if popover.isShown { popover.performClose(nil) }
        else { showOverview() }
    }

    private func refresh() {
        let indicator = IslandIndicator(activity: model.activity, connected: model.isConnected)
        if indicator != lastIndicator, let button = statusItem.button {
            lastIndicator = indicator
            button.image = NSImage(systemSymbolName: indicator.symbol, accessibilityDescription: "Codex Notch")
            button.image?.isTemplate = true
            button.imagePosition = indicator.title.isEmpty ? .imageOnly : .imageLeading
            button.title = indicator.title.isEmpty ? "" : " " + indicator.title
        }
        statusItem.button?.toolTip = "\(model.headline) · \(model.subtitle)"
        statusItem.button?.setAccessibilityLabel("Codex Notch: \(model.headline). \(model.subtitle)")
        // Feed events never create or focus a window. Only the user's action opens it.
        if popover.isShown { updateSize(reset: false) }
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            popover.performClose(nil)
            NSMenu.popUpContextMenu(makeMenu(), with: event, for: sender)
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showOverview()
        }
    }

    func showOverview() {
        guard let anchor: NSView = notchGeometry != nil ? notchPanel.contentView : statusItem.button else { return }
        if popover.isShown { return }
        updateSize(reset: true)
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        model.acknowledge()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        statusItem.button?.highlight(true)
    }

    private func updateSize(reset: Bool) {
        let count = model.isConnected ? model.activity.visible.count : 0
        let requested = count == 0 ? 2 : min(IslandLayout.maximumRows, count)
        let capacity = reset ? requested : max(presentation.rowCapacity, requested)
        if capacity != presentation.rowCapacity { presentation.rowCapacity = capacity }
        let size = NSSize(width: IslandLayout.width, height: IslandLayout.bodyHeight(capacity: capacity))
        if popover.contentSize != size { popover.contentSize = size }
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.highlight(false)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let heading = NSMenuItem(title: model.headline, action: nil, keyEquivalent: "")
        menu.addItem(heading)
        menu.addItem(.separator())
        add(menu, title: "Otevřít přehled", action: #selector(expand))
        add(menu, title: "Obnovit napojení", action: #selector(reconnect))
        let login = add(menu, title: "Spouštět po přihlášení", action: #selector(toggleLogin))
        login.state = model.loginEnabled ? .on : .off
        menu.addItem(.separator())
        add(menu, title: "Ukončit Codex Notch", action: #selector(quit), key: "q")
        return menu
    }

    @discardableResult
    private func add(_ menu: NSMenu, title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; menu.addItem(item)
        return item
    }
    @objc private func expand() { showOverview() }
    @objc private func reconnect() { model.reconnect() }
    @objc private func toggleLogin() { model.toggleLogin() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func open(_ row: ThreadSummary) {
        guard !model.demo else { return }
        let id = row.isSubagent ? row.parentID ?? row.id : row.id
        guard UUID(uuidString: id) != nil, let url = URL(string: "codex://threads/\(id)") else { return }
        guard NSWorkspace.shared.open(url) else {
            model.settingsError = "Odkaz na chat se nepodařilo otevřít. Spusť desktopový Codex a zkus to znovu."
            return
        }
        popover.performClose(nil)
    }

    func stop() {
        observation?.cancel()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        popover.performClose(nil)
        notchPanel.orderOut(nil)
        NSStatusBar.system.removeStatusItem(statusItem)
        model.stop()
    }
}
