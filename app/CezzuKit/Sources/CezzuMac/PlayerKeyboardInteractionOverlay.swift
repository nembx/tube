import AppKit
import CezzuKit
import SwiftUI

struct PlayerKeyboardInteractionOverlay: NSViewRepresentable {
    let actions: PlayerInteractionActions

    func makeNSView(context: Context) -> PlayerKeyboardInteractionView {
        let view = PlayerKeyboardInteractionView()
        view.actions = actions
        return view
    }

    func updateNSView(_ nsView: PlayerKeyboardInteractionView, context: Context) {
        nsView.actions = actions
        nsView.ensureFirstResponder()
    }
}

final class PlayerKeyboardInteractionView: NSView {
    var actions: PlayerInteractionActions = .init()

    private var rightArrowTask: Task<Void, Never>?
    private var isRightArrowHeld: Bool = false
    private var didActivateTemporaryBoost: Bool = false
    private var mouseBoostTask: Task<Void, Never>?
    private var mouseDownPoint: CGPoint?
    private var mouseDownDate: Date?
    private var isMouseBoosting: Bool = false

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        ensureFirstResponder()
    }

    func ensureFirstResponder() {
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        mouseDownPoint = point
        mouseDownDate = Date()
        isMouseBoosting = false
        mouseBoostTask?.cancel()
        mouseBoostTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, self.mouseDownPoint != nil else { return }
            self.isMouseBoosting = true
            self.actions.beginTemporaryBoost()
            self.actions.updateTemporaryBoost(rate(for: point))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = mouseDownPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        guard isMouseBoosting else { return }
        actions.updateTemporaryBoost(
            PlayerTemporaryBoostRate.resolve(horizontalTranslation: current.x - origin.x)
        )
    }

    override func mouseUp(with event: NSEvent) {
        let current = convert(event.locationInWindow, from: nil)
        let isTap = isMouseTap(at: current)

        mouseBoostTask?.cancel()
        mouseBoostTask = nil

        if isMouseBoosting {
            Task { @MainActor in actions.endTemporaryBoost() }
        } else if isTap {
            Task { @MainActor in actions.toggleControls() }
        }

        mouseDownPoint = nil
        mouseDownDate = nil
        isMouseBoosting = false
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49:
            Task { @MainActor in actions.togglePlayPause() }
        case 123:
            Task { @MainActor in actions.seekRelative(-10) }
        case 124:
            guard !isRightArrowHeld else { return }
            isRightArrowHeld = true
            didActivateTemporaryBoost = false
            rightArrowTask?.cancel()
            rightArrowTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                guard let self, self.isRightArrowHeld else { return }
                self.didActivateTemporaryBoost = true
                self.actions.beginTemporaryBoost()
            }
        default:
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        switch event.keyCode {
        case 124:
            isRightArrowHeld = false
            rightArrowTask?.cancel()
            rightArrowTask = nil
            if didActivateTemporaryBoost {
                didActivateTemporaryBoost = false
                Task { @MainActor in actions.endTemporaryBoost() }
            } else {
                Task { @MainActor in actions.seekRelative(10) }
            }
        default:
            super.keyUp(with: event)
        }
    }

    private func isMouseTap(at point: CGPoint) -> Bool {
        guard let origin = mouseDownPoint, let mouseDownDate else { return false }
        let duration = Date().timeIntervalSince(mouseDownDate)
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        return duration < 0.35 && abs(dx) < 8 && abs(dy) < 8
    }

    private func rate(for point: CGPoint) -> Float {
        guard let origin = mouseDownPoint else { return PlayerTemporaryBoostRate.defaultRate }
        return PlayerTemporaryBoostRate.resolve(horizontalTranslation: point.x - origin.x)
    }
}
