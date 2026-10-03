import CezzuKit
import SwiftUI

struct PlayerInteractionOverlay: View {
    let actions: PlayerInteractionActions

    @State private var pressStartDate: Date?
    @State private var boostTask: Task<Void, Never>?
    @State private var isBoosting = false
    @State private var latestTranslation: CGSize = .zero

    private let longPressDuration: Duration = .milliseconds(350)

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged(handleDragChanged)
                    .onEnded(handleDragEnded)
            )
            .allowsHitTesting(true)
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        latestTranslation = value.translation

        if pressStartDate == nil {
            pressStartDate = value.time
            boostTask = Task { @MainActor in
                try? await Task.sleep(for: longPressDuration)
                guard !Task.isCancelled, pressStartDate != nil else { return }
                isBoosting = true
                actions.beginTemporaryBoost()
                actions.updateTemporaryBoost(
                    PlayerTemporaryBoostRate.resolve(horizontalTranslation: latestTranslation.width)
                )
            }
        }

        guard isBoosting else { return }
        actions.updateTemporaryBoost(
            PlayerTemporaryBoostRate.resolve(horizontalTranslation: value.translation.width)
        )
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        let duration = pressStartDate.map { value.time.timeIntervalSince($0) } ?? 0
        let isTap = !isBoosting && duration < 0.35 && abs(value.translation.width) < 12 && abs(value.translation.height) < 12

        boostTask?.cancel()
        boostTask = nil

        if isBoosting {
            actions.endTemporaryBoost()
        } else if isTap {
            actions.toggleControls()
        }

        isBoosting = false
        pressStartDate = nil
        latestTranslation = .zero
    }
}
