import AVKit
import SwiftUI

struct PlayerRoutePickerButton: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.player = player
        view.isRoutePickerButtonBordered = false
        view.setRoutePickerButtonColor(.white, for: .normal)
        view.setRoutePickerButtonColor(.white, for: .normalHighlighted)
        view.setRoutePickerButtonColor(.systemBlue, for: .active)
        view.setRoutePickerButtonColor(.systemBlue, for: .activeHighlighted)
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {
        view.player = player
    }
}
