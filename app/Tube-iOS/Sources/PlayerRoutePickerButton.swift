import AVKit
import SwiftUI

struct PlayerRoutePickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = true
        view.tintColor = .white
        view.activeTintColor = .systemBlue
        view.accessibilityLabel = "AirPlay 投屏"
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
