import AppKit
import SwiftUI

@MainActor
final class OverlayPanelController: NSObject, NSWindowDelegate {
    private static let defaultSize = NSSize(width: 720, height: 340)
    private static let minimumSize = NSSize(width: 420, height: 180)
    private static let maximumSize = NSSize(width: 1_600, height: 1_000)

    private let model: AppModel
    private let panel: EdgePermissivePanel
    private let controlsPanel: NSPanel
    private var interactionState = OverlayInteractionState()
    private var resizeStartFrame: NSRect?
    nonisolated(unsafe) private var localMouseMonitor: Any?
    nonisolated(unsafe) private var globalMouseMonitor: Any?

    init(model: AppModel) {
        self.model = model
        panel = EdgePermissivePanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        controlsPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: OverlayControlsGeometry.size(isLocked: false)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.delegate = self
        panel.contentView = NSHostingView(rootView: LyricsOverlayView(model: model))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.acceptsMouseMovedEvents = true
        panel.minSize = Self.minimumSize
        panel.maxSize = Self.maximumSize
        panel.setFrameAutosaveName("LyricFloatOverlay")

        controlsPanel.contentView = NSHostingView(rootView: OverlayControlsView(model: model))
        controlsPanel.backgroundColor = .clear
        controlsPanel.isOpaque = false
        controlsPanel.hasShadow = false
        controlsPanel.level = .floating
        controlsPanel.isFloatingPanel = true
        controlsPanel.hidesOnDeactivate = false
        controlsPanel.canHide = false
        controlsPanel.becomesKeyOnlyIfNeeded = true
        controlsPanel.isMovableByWindowBackground = false
        controlsPanel.ignoresMouseEvents = false
        controlsPanel.acceptsMouseMovedEvents = true

        installMouseMonitors()
        ensureVisible()
    }

    deinit {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
    }

    func applyPreferences() {
        panel.ignoresMouseEvents = model.preferences.locked
        let collectionBehavior: NSWindow.CollectionBehavior = model.preferences.allSpaces
            ? [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]
            : [.fullScreenAuxiliary, .ignoresCycle]
        panel.collectionBehavior = collectionBehavior
        controlsPanel.collectionBehavior = collectionBehavior

        if model.preferences.overlayVisible {
            ensureVisible()
            panel.orderFrontRegardless()
            updateControlsVisibility()
        } else {
            controlsPanel.orderOut(nil)
            panel.orderOut(nil)
        }
        AppLog.windowing.info("Applied overlay window preferences")
    }

    func beginResize() {
        guard !model.preferences.locked, interactionState.begin(.resize) else { return }
        resizeStartFrame = panel.frame
    }

    func beginMove() -> Bool {
        guard !model.preferences.locked, interactionState.begin(.move) else { return false }
        controlsPanel.orderOut(nil)
        return true
    }

    func endMove() {
        guard interactionState.end(.move) else { return }
        panel.saveFrame(usingName: "LyricFloatOverlay")
        ensurePartiallyVisible()
        positionControlsPanel()
        updateControlsVisibility()
    }

    func resize(by translation: CGSize) {
        guard interactionState.isActive(.resize), let resizeStartFrame else { return }
        let frame = OverlayResizeGeometry.frame(
            startingAt: resizeStartFrame,
            translation: translation,
            minimumSize: Self.minimumSize,
            maximumSize: Self.maximumSize
        )
        panel.setFrame(frame, display: true)
    }

    func endResize() {
        guard interactionState.end(.resize), resizeStartFrame != nil else { return }
        resizeStartFrame = nil
        panel.saveFrame(usingName: "LyricFloatOverlay")
        ensurePartiallyVisible()
        positionControlsPanel()
        updateControlsVisibility()
    }

    func resetSize() {
        let currentFrame = panel.frame
        let frame = NSRect(
            x: currentFrame.midX - Self.defaultSize.width / 2,
            y: currentFrame.midY - Self.defaultSize.height / 2,
            width: Self.defaultSize.width,
            height: Self.defaultSize.height
        )
        panel.setFrame(frame, display: true)
        panel.saveFrame(usingName: "LyricFloatOverlay")
        ensurePartiallyVisible()
    }

    func centerOnCurrentDisplay() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main
                ?? NSScreen.screens.first else {
            return
        }

        panel.setFrame(
            OverlayRecoveryGeometry.centeredFrame(panel.frame, in: screen.visibleFrame),
            display: true
        )
        panel.orderFrontRegardless()
        panel.saveFrame(usingName: "LyricFloatOverlay")
        positionControlsPanel()
    }

    func windowDidMove(_ notification: Notification) {
        guard !interactionState.isActive(.move) else { return }
        positionControlsPanel()
        ensurePartiallyVisible()
        updateControlsVisibility()
    }

    func windowDidResize(_ notification: Notification) {
        positionControlsPanel()
        guard !interactionState.isActive(.resize) else { return }
        ensurePartiallyVisible()
        updateControlsVisibility()
    }

    private func ensureVisible() {
        guard !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) else {
            return
        }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.midY - panel.frame.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    private func ensurePartiallyVisible() {
        guard !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) else {
            return
        }
        ensureVisible()
    }

    private func installMouseMonitors() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseUp]

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.updateControlsVisibility()
            }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateControlsVisibility()
            }
        }
    }

    private func updateControlsVisibility() {
        let mouseLocation = NSEvent.mouseLocation
        let mouseIsOverOverlay = panel.frame.contains(mouseLocation)
        let mouseIsOverControls = controlsPanel.frame.contains(mouseLocation)

        guard model.preferences.overlayVisible,
              panel.isVisible,
              panel.occlusionState.contains(.visible),
              mouseIsOverOverlay || mouseIsOverControls
                || interactionState.isActive(.move)
                || interactionState.isActive(.resize) else {
            controlsPanel.orderOut(nil)
            return
        }

        positionControlsPanel()
        if !controlsPanel.isVisible {
            controlsPanel.orderFrontRegardless()
        }
    }

    private func positionControlsPanel() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
                ?? screenWithLargestIntersection(for: panel.frame)
                ?? NSScreen.main else {
            return
        }

        controlsPanel.setFrame(
            OverlayControlsGeometry.frame(
                in: panel.frame,
                visibleFrame: screen.visibleFrame,
                isLocked: model.preferences.locked
            ),
            display: false
        )
    }

    private func screenWithLargestIntersection(for frame: NSRect) -> NSScreen? {
        NSScreen.screens.max {
            $0.frame.intersection(frame).area < $1.frame.intersection(frame).area
        }
    }
}

enum OverlayResizeGeometry {
    static func frame(
        startingAt start: NSRect,
        translation: CGSize,
        minimumSize: CGSize,
        maximumSize: CGSize
    ) -> NSRect {
        let width = min(max(start.width + translation.width, minimumSize.width), maximumSize.width)
        let height = min(max(start.height + translation.height, minimumSize.height), maximumSize.height)

        return NSRect(
            x: start.minX,
            y: start.maxY - height,
            width: width,
            height: height
        )
    }
}

enum OverlayInteractionKind {
    case move
    case resize
}

struct OverlayInteractionState {
    private(set) var active: OverlayInteractionKind?

    mutating func begin(_ interaction: OverlayInteractionKind) -> Bool {
        guard active == nil else { return false }
        active = interaction
        return true
    }

    mutating func end(_ interaction: OverlayInteractionKind) -> Bool {
        guard active == interaction else { return false }
        active = nil
        return true
    }

    func isActive(_ interaction: OverlayInteractionKind) -> Bool {
        active == interaction
    }
}

enum OverlayRecoveryGeometry {
    static func centeredFrame(_ frame: CGRect, in visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.midY - frame.height / 2,
            width: frame.width,
            height: frame.height
        )
    }
}

enum OverlayVisibleGeometry {
    static func frame(
        _ frame: CGRect,
        constrainedTo visibleFrame: CGRect,
        minimumVisibleSize: CGSize
    ) -> CGRect {
        let visibleWidth = min(frame.width, minimumVisibleSize.width)
        let visibleHeight = min(frame.height, minimumVisibleSize.height)
        let minX = visibleFrame.minX - frame.width + visibleWidth
        let maxX = visibleFrame.maxX - visibleWidth
        let minY = visibleFrame.minY - frame.height + visibleHeight
        let maxY = visibleFrame.maxY - visibleHeight

        return CGRect(
            x: min(max(frame.minX, minX), maxX),
            y: min(max(frame.minY, minY), maxY),
            width: frame.width,
            height: frame.height
        )
    }
}

enum OverlayControlsGeometry {
    private static let inset: CGFloat = 8

    static func size(isLocked: Bool) -> CGSize {
        CGSize(width: 80, height: 40)
    }

    static func frame(in overlayFrame: CGRect, visibleFrame: CGRect, isLocked: Bool) -> CGRect {
        let size = size(isLocked: isLocked)
        let visibleOverlay = overlayFrame.intersection(visibleFrame)
        let anchor = visibleOverlay.isNull || visibleOverlay.isEmpty ? visibleFrame : visibleOverlay
        let minX = visibleFrame.minX + inset
        let maxX = visibleFrame.maxX - size.width - inset
        let minY = visibleFrame.minY + inset
        let maxY = visibleFrame.maxY - size.height - inset

        return CGRect(
            x: min(max(anchor.maxX - size.width - inset, minX), maxX),
            y: min(max(anchor.minY + inset, minY), maxY),
            width: size.width,
            height: size.height
        )
    }
}

private final class EdgePermissivePanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? screen
            ?? self.screen
        guard let visibleFrame = targetScreen?.visibleFrame else { return frameRect }

        return OverlayVisibleGeometry.frame(
            frameRect,
            constrainedTo: visibleFrame,
            minimumVisibleSize: CGSize(width: 76, height: 48)
        )
    }
}

private struct OverlayControlsView: View {
    @ObservedObject var model: AppModel
    @State private var isResizing = false

    var body: some View {
        HStack(spacing: 4) {
            pinButton
            resizeHandle
                .opacity(model.preferences.locked ? 0 : 1)
                .allowsHitTesting(!model.preferences.locked)
        }
        .frame(
            width: OverlayControlsGeometry.size(isLocked: model.preferences.locked).width,
            height: OverlayControlsGeometry.size(isLocked: model.preferences.locked).height
        )
    }

    private var pinButton: some View {
        Button(action: model.toggleLock) {
            Image(systemName: model.preferences.locked ? "pin.fill" : "pin")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(model.preferences.locked ? Color.yellow : .white)
                .shadow(color: .black.opacity(0.95), radius: 2, y: 0)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.preferences.locked ? "解除固定歌词" : "固定歌词并穿透点击")
        .allowsWindowActivationEvents(true)
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(isResizing ? 1 : 0.88))
            .shadow(color: .black.opacity(0.95), radius: 2, y: 0)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if !isResizing {
                            isResizing = true
                            model.beginOverlayResize()
                        }
                        model.resizeOverlay(by: value.translation)
                    }
                    .onEnded { _ in
                        isResizing = false
                        model.endOverlayResize()
                    }
            )
            .help("拖动调整歌词窗口大小")
            .allowsWindowActivationEvents(true)
    }
}

private extension CGRect {
    var area: CGFloat {
        isNull || isInfinite ? 0 : width * height
    }
}
