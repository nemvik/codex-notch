import AppKit
import SwiftUI
import Combine
import QuartzCore
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
    private let surfacePanel = NotchStatusPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var notchGeometry: NotchGeometry?
    private var hoverState = NotchHoverState()
    private var hoverTimer: Timer?
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    private var menuTracking = false
    private var previousApplication: NSRunningApplication?

    init(model: IslandModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        for panel in [notchPanel, surfacePanel] {
            panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
            panel.level = .statusBar; panel.hidesOnDeactivate = false; panel.isMovable = false
            panel.isReleasedWhenClosed = false; panel.minSize = .zero
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        }
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
        model.closeOverview = { [weak self] in self?.closeOverview() }
        model.changed = { [weak self] in self?.refresh() }
        observation = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(updateDisplay), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(resetInteraction), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(resetInteraction), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDeactivated), name: NSApplication.didResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuBegan), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuEnded), name: NSMenu.didEndTrackingNotification, object: nil)
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closeOverview(restoreFocus: false) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            if let self, event.type == .keyDown, event.keyCode == 53,
               self.presentation.notchPhase == .expanded, !self.menuTracking,
               self.model.settingsError == nil, self.surfacePanel.attachedSheet == nil {
                self.closeOverview()
                return nil
            }
            if event.type == .keyDown { return event }
            if let self, !self.menuTracking, self.model.settingsError == nil, self.surfacePanel.attachedSheet == nil, event.window !== self.notchPanel, event.window !== self.surfacePanel,
               self.presentation.notchPhase != .resting {
                self.closeOverview(restoreFocus: false)
            }
            return event
        }
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.samplePointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
        updateDisplay()
        refresh()
    }

    @objc private func applicationDeactivated() {
        if presentation.notchPhase == .expanded { closeOverview(restoreFocus: false) }
    }

    @objc private func resetInteraction() {
        closeOverview(restoreFocus: false)
        hoverState = NotchHoverState()
        updateDisplay()
    }

    @objc private func updateDisplay() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        let geometry = screen.flatMap {
            NotchGeometry(screen: $0.frame, visible: $0.visibleFrame, safeTop: $0.safeAreaInsets.top,
                          left: $0.auxiliaryTopLeftArea, right: $0.auxiliaryTopRightArea, scale: $0.backingScaleFactor)
        }
        guard geometry != notchGeometry || notchPanel.contentView == nil else { return }
        popover.close()
        hoverState = NotchHoverState()
        presentation.notchPhase = .resting
        surfacePanel.acceptsKeyboard = false
        surfacePanel.orderOut(nil)
        notchGeometry = geometry
        if let geometry {
            let host = FirstMouseHostingView(rootView: NotchAnchorView(model: model, presentation: presentation, geometry: geometry) { [weak self] in self?.toggleOverview() })
            let surface = FirstMouseHostingView(rootView: NotchSurfaceView(model: model, presentation: presentation, geometry: geometry, toggle: { [weak self] in self?.toggleOverview() }, includesAnchor: false))
            surface.sizingOptions = []
            surfacePanel.contentView = surface
            surfacePanel.setFrame(geometry.bodyFrame(phase: .resting, capacity: presentation.rowCapacity), display: false)
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
        if popover.isShown || presentation.notchPhase == .expanded { closeOverview() }
        else { showOverview() }
    }

    @objc private func menuBegan() { menuTracking = true }
    @objc private func menuEnded() { menuTracking = false }

    private func samplePointer() {
        guard let geometry = notchGeometry, presentation.notchPhase != .expanded, !menuTracking, model.settingsError == nil else { return }
        let point = NSEvent.mouseLocation
        let visible = hoverState.sample(insideApproach: geometry.approachFrame.contains(point),
                                        insideSurface: presentation.notchPhase == .revealed && surfacePanel.frame.contains(point),
                                        mouseDown: NSEvent.pressedMouseButtons != 0,
                                        now: ProcessInfo.processInfo.systemUptime)
        let next: NotchPhase = visible ? .revealed : .resting
        if next != presentation.notchPhase { setNotchPhase(next) }
    }

    private func setNotchPhase(_ phase: NotchPhase, animate: Bool = true) {
        guard let geometry = notchGeometry else { return }
        let duration = animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.22 : 0
        withAnimation(duration > 0 ? .easeOut(duration: duration) : nil) {
            presentation.notchPhase = phase
        }
        surfacePanel.acceptsKeyboard = phase == .expanded
        if phase != .resting { surfacePanel.orderFrontRegardless() }
        let frame = geometry.bodyFrame(phase: phase, capacity: presentation.rowCapacity)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            if duration > 0 { surfacePanel.animator().setFrame(frame, display: true) }
            else { surfacePanel.setFrame(frame, display: true) }
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.presentation.notchPhase == .resting else { return }
                self.surfacePanel.orderOut(nil)
            }
        }
    }

    private func closeOverview(restoreFocus: Bool = true) {
        hoverState.suppressUntilExit()
        if presentation.notchPhase != .resting { setNotchPhase(.resting) }
        popover.performClose(nil)
        surfacePanel.resignKey()
        if restoreFocus, NSApp.isActive { previousApplication?.activate(options: []) }
        previousApplication = nil
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
        if popover.isShown || presentation.notchPhase == .expanded { updateSize(reset: false) }
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
        if popover.isShown || presentation.notchPhase == .expanded { return }
        if !NSApp.isActive { previousApplication = NSWorkspace.shared.frontmostApplication }
        updateSize(reset: true)
        model.acknowledge()
        if notchGeometry != nil {
            setNotchPhase(.expanded)
            NSApp.activate(ignoringOtherApps: true)
            surfacePanel.makeKeyAndOrderFront(nil)
        } else if let anchor = statusItem.button {
            popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            statusItem.button?.highlight(true)
        }
    }

    private func updateSize(reset: Bool) {
        let count = model.isConnected ? model.activity.visible.count : 0
        let requested = count == 0 ? 2 : min(IslandLayout.maximumRows, count)
        let capacity = reset ? requested : max(presentation.rowCapacity, requested)
        let capacityChanged = capacity != presentation.rowCapacity
        if capacityChanged { presentation.rowCapacity = capacity }
        let size = NSSize(width: IslandLayout.width, height: IslandLayout.bodyHeight(capacity: capacity))
        if popover.contentSize != size { popover.contentSize = size }
        if presentation.notchPhase == .expanded, let geometry = notchGeometry {
            let frame = geometry.bodyFrame(phase: .expanded, capacity: capacity)
            if capacityChanged {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    surfacePanel.animator().setFrame(frame, display: true)
                }
            }
        }
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
        closeOverview(restoreFocus: false)
    }

    func stop() {
        observation?.cancel()
        hoverTimer?.invalidate()
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        popover.performClose(nil)
        notchPanel.orderOut(nil)
        surfacePanel.orderOut(nil)
        NSStatusBar.system.removeStatusItem(statusItem)
        model.stop()
    }
}
