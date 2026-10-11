import AVFoundation
import AVKit
import Observation
import QuartzCore
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// 裸 `AVPlayer` 渲染面板 —— 只画视频，不带任何系统控制条。
///
/// SwiftUI 的 `VideoPlayer` 在所有平台都强制显示原生播放控件且没有关闭 API，
/// 会和 `GlassPlayerControls` 叠在一起（就是用户看到的"底部有两条 control bar"）。
/// 唯一的解法是下到 UIKit / AppKit 层，直接把 `AVPlayerLayer` 塞进宿主视图。
///
/// 当 `superResolutionMode` 不是 `.off` 时，宿主视图会在 `AVPlayerLayer` 之上
/// 叠一层 `CAMetalLayer`，由 `VideoSuperResolutionPipeline` 驱动；
/// 此时 `AVPlayerLayer` 被隐藏（保持其音频 / PiP 链路完整）。
///
/// ⚠️ 这是 TubeKit 内**第二个**允许写 `#if canImport(UIKit)` / `AppKit` 分叉的文件
/// （第一个是 `Extraction/WebViewVideoExtractor.swift`）。分叉已经压到最小：
/// 只有平台桥那一小段，业务逻辑和调用方（`PlayerView`）完全无感知。
/// **不要在别的文件里抄这个模式** —— 再次遇到跨平台需求时，优先走 SwiftUI 原生。
public struct PlayerSurface: View {
    public let player: AVPlayer
    public let gravity: AVLayerVideoGravity
    public let pictureInPictureController: PlayerPictureInPictureController?
    public let superResolutionMode: SuperResolutionMode
    public let superResolutionDiagnostics: SuperResolutionDiagnosticsBridge?

    public init(
        player: AVPlayer,
        gravity: AVLayerVideoGravity = .resizeAspect,
        pictureInPictureController: PlayerPictureInPictureController? = nil,
        superResolutionMode: SuperResolutionMode = .off,
        superResolutionDiagnostics: SuperResolutionDiagnosticsBridge? = nil
    ) {
        self.player = player
        self.gravity = gravity
        self.pictureInPictureController = pictureInPictureController
        self.superResolutionMode = superResolutionMode
        self.superResolutionDiagnostics = superResolutionDiagnostics
    }

    public var body: some View {
        PlayerLayerBridge(
            player: player,
            gravity: gravity,
            pictureInPictureController: pictureInPictureController,
            superResolutionMode: superResolutionMode,
            superResolutionDiagnostics: superResolutionDiagnostics
        )
    }
}

@MainActor
@Observable
public final class PlayerPictureInPictureController {
    public private(set) var isSupported: Bool = false
    public private(set) var isActive: Bool = false

    private var startImpl: @MainActor () -> Void = {}
    private var didStartLifecycleImpl: @MainActor () -> Void = {}
    private var restoreLifecycleImpl: @MainActor (@escaping (Bool) -> Void) -> Void = { completion in
        completion(true)
    }

    public init() {}

    public func start() {
        guard isSupported else { return }
        startImpl()
    }

    fileprivate func configure(
        isSupported: Bool,
        start: @escaping @MainActor () -> Void = {}
    ) {
        self.isSupported = isSupported
        self.startImpl = start
    }

    func setLifecycle(
        didStart: @escaping @MainActor () -> Void = {},
        restoreUserInterface: @escaping @MainActor (@escaping (Bool) -> Void) -> Void = { completion in
            completion(true)
        }
    ) {
        self.didStartLifecycleImpl = didStart
        self.restoreLifecycleImpl = restoreUserInterface
    }

    fileprivate func handleDidStart() {
        isActive = true
        didStartLifecycleImpl()
    }

    fileprivate func handleWillStop() {
        isActive = false
    }

    fileprivate func handleRestoreUserInterface(completion: @escaping (Bool) -> Void) {
        restoreLifecycleImpl(completion)
    }
}

// MARK: - platform bridge

#if canImport(UIKit)

    /// iOS 宿主：自管根 layer，子 layer 是 AVPlayerLayer + 可选 CAMetalLayer。
    final class PlayerLayerHostView: UIView {
        let playerLayer = AVPlayerLayer()
        var superResolutionLayer: CAMetalLayer?
        var pipeline: VideoSuperResolutionPipeline?
        var displayLink: CADisplayLink?
        var itemObservation: NSKeyValueObservation?

        /// 给 DisplayLinkTarget 用的统一入口，让两个平台的 tick 代码长得一样。
        var superResolutionDisplayLink: CADisplayLink? { displayLink }
        var currentMode: SuperResolutionMode = .off

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            layer.addSublayer(playerLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            superResolutionLayer?.frame = bounds
            // 手动加进来的 sublayer 不会继承屏幕缩放，contentsScale 默认是 1。
            // 不同步的话超分流水线拿到的「层像素尺寸」其实是点数，3 倍屏上会
            // 少算三倍，把放大倍率算成 1:1，Anime4K 的放大链就被它自己的
            // //!WHEN 门槛全部跳过了。
            superResolutionLayer?.contentsScale = displayScale
            CATransaction.commit()
        }

        /// 当前屏幕的缩放倍数。还没进 window 时退回 trait 里的值。
        var displayScale: CGFloat {
            let scale = window?.screen.scale ?? traitCollection.displayScale
            return scale > 0 ? scale : 1
        }
    }

    struct PlayerLayerBridge: UIViewRepresentable {
        let player: AVPlayer
        let gravity: AVLayerVideoGravity
        let pictureInPictureController: PlayerPictureInPictureController?
        let superResolutionMode: SuperResolutionMode
        let superResolutionDiagnostics: SuperResolutionDiagnosticsBridge?

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeUIView(context: Context) -> PlayerLayerHostView {
            let view = PlayerLayerHostView()
            view.playerLayer.player = player
            view.playerLayer.videoGravity = gravity
            context.coordinator.attachPictureInPicture(
                to: view.playerLayer,
                bridge: pictureInPictureController
            )
            context.coordinator.applySuperResolution(
                mode: superResolutionMode,
                player: player,
                view: view,
                diagnostics: superResolutionDiagnostics
            )
            return view
        }

        func updateUIView(_ view: PlayerLayerHostView, context: Context) {
            if view.playerLayer.player !== player {
                view.playerLayer.player = player
            }
            if view.playerLayer.videoGravity != gravity {
                view.playerLayer.videoGravity = gravity
            }
            context.coordinator.attachPictureInPicture(
                to: view.playerLayer,
                bridge: pictureInPictureController
            )
            context.coordinator.applySuperResolution(
                mode: superResolutionMode,
                player: player,
                view: view,
                diagnostics: superResolutionDiagnostics
            )
        }

        static func dismantleUIView(_ view: PlayerLayerHostView, coordinator: Coordinator) {
            coordinator.teardown(view: view)
        }

        @MainActor
        final class Coordinator: NSObject, AVPictureInPictureControllerDelegate, @unchecked Sendable {
            private var controller: AVPictureInPictureController?
            private weak var bridge: PlayerPictureInPictureController?

            func attachPictureInPicture(
                to layer: AVPlayerLayer,
                bridge: PlayerPictureInPictureController?
            ) {
                self.bridge = bridge
                guard let bridge else {
                    controller = nil
                    return
                }

                guard AVPictureInPictureController.isPictureInPictureSupported() else {
                    controller = nil
                    bridge.configure(isSupported: false)
                    return
                }

                if controller?.playerLayer !== layer {
                    guard let next = AVPictureInPictureController(playerLayer: layer) else {
                        controller = nil
                        bridge.configure(isSupported: false)
                        return
                    }
                    next.delegate = self
                    controller = next
                }

                bridge.configure(isSupported: controller != nil) { [weak self] in
                    self?.controller?.startPictureInPicture()
                }
            }

            func applySuperResolution(
                mode: SuperResolutionMode,
                player: AVPlayer,
                view: PlayerLayerHostView,
                diagnostics: SuperResolutionDiagnosticsBridge?
            ) {
                let resolved = SuperResolutionCapability.resolved(mode, on: SuperResolutionCapability.defaultDevice)
                if resolved == view.currentMode {
                    // 模式没变 —— 让 KVO 负责 item 切换，避免每次 SwiftUI update 都 remove/add
                    // AVPlayerItemVideoOutput 把主线程拖死。
                    return
                }
                view.currentMode = resolved

                if resolved == .off {
                    view.displayLink?.invalidate()
                    view.displayLink = nil
                    view.itemObservation?.invalidate()
                    view.itemObservation = nil
                    view.pipeline?.detach()
                    view.pipeline = nil
                    view.superResolutionLayer?.removeFromSuperlayer()
                    view.superResolutionLayer = nil
                    view.playerLayer.isHidden = false
                    return
                }

                if view.pipeline == nil {
                    if let pipeline = VideoSuperResolutionPipeline() {
                        view.pipeline = pipeline
                        view.superResolutionLayer = pipeline.metalLayer
                        view.layer.addSublayer(pipeline.metalLayer)
                        pipeline.metalLayer.frame = view.bounds
                        pipeline.metalLayer.contentsScale = view.displayScale
                        pipeline.onDiagnosticsChange = { [weak diagnostics] in diagnostics?.update($0) }
                    } else {
                        // GPU 不可用，降级为关闭。
                        view.currentMode = .off
                        view.playerLayer.isHidden = false
                        return
                    }
                }

                view.pipeline?.setMode(resolved)
                view.pipeline?.attach(to: player.currentItem)
                view.playerLayer.isHidden = true

                view.itemObservation?.invalidate()
                view.itemObservation = player.observe(\.currentItem, options: [.new]) { [weak view] _, change in
                    let item = change.newValue ?? nil
                    Task { @MainActor in
                        view?.pipeline?.attach(to: item)
                    }
                }

                if view.displayLink == nil {
                    let link = CADisplayLink(
                        target: DisplayLinkTarget(view: view),
                        selector: #selector(DisplayLinkTarget.tick)
                    )
                    link.add(to: .main, forMode: .common)
                    view.displayLink = link
                }
            }

            func teardown(view: PlayerLayerHostView) {
                view.displayLink?.invalidate()
                view.displayLink = nil
                view.itemObservation?.invalidate()
                view.itemObservation = nil
                view.pipeline?.detach()
                view.pipeline = nil
                view.superResolutionLayer?.removeFromSuperlayer()
                view.superResolutionLayer = nil
            }

            nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
                MainActor.assumeIsolated {
                    self.bridge?.handleDidStart()
                }
            }

            nonisolated func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
                MainActor.assumeIsolated {
                    self.bridge?.handleWillStop()
                }
            }

            nonisolated func pictureInPictureController(
                _ pictureInPictureController: AVPictureInPictureController,
                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
            ) {
                nonisolated(unsafe) let handler = completionHandler
                MainActor.assumeIsolated {
                    self.bridge?.handleRestoreUserInterface(completion: handler) ?? handler(true)
                }
            }
        }
    }

    /// `CADisplayLink` 不能直接持有 closure；包一层 weak target 把 tick 转发给 pipeline。
    @MainActor
    final class DisplayLinkTarget: NSObject {
        weak var view: PlayerLayerHostView?
        private var didApplyFrameRate = false
        init(view: PlayerLayerHostView) { self.view = view }
        @objc func tick() {
            guard let view, let pipeline = view.pipeline else { return }
            pipeline.drawNextFrame()
            applyPreferredFrameRate(pipeline: pipeline, view: view)
        }

        /// 片源帧率是开播后才解出来的，所以每帧问一次，拿到了就收敛并不再改。
        private func applyPreferredFrameRate(
            pipeline: VideoSuperResolutionPipeline,
            view: PlayerLayerHostView
        ) {
            guard !didApplyFrameRate,
                  let range = SuperResolutionDisplayLinkPolicy.preferredFrameRateRange(
                      videoFrameRate: pipeline.nominalVideoFrameRate
                  )
            else { return }
            didApplyFrameRate = true
            view.superResolutionDisplayLink?.preferredFrameRateRange = range
        }
    }

#elseif canImport(AppKit)

    /// macOS 宿主：显式管理一个根 CALayer，子 layer = AVPlayerLayer + 可选 CAMetalLayer。
    final class PlayerLayerHostView: NSView {
        let playerLayer = AVPlayerLayer()
        var superResolutionLayer: CAMetalLayer?
        var pipeline: VideoSuperResolutionPipeline?
        var macDisplayLink: CADisplayLink?
        var itemObservation: NSKeyValueObservation?

        /// 给 DisplayLinkTarget 用的统一入口，让两个平台的 tick 代码长得一样。
        var superResolutionDisplayLink: CADisplayLink? { macDisplayLink }
        var currentMode: SuperResolutionMode = .off

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            // 实时跟随窗口拖拽，避免 live resize 期间等 layout 才重绘。
            layerContentsRedrawPolicy = .duringViewResize
            let root = CALayer()
            root.backgroundColor = NSColor.black.cgColor
            // 关掉 bounds/position 隐式动画，否则 resize 结束时会出现 0–2s 的线性放大。
            root.actions = [
                "bounds": NSNull(),
                "position": NSNull(),
                "contents": NSNull(),
                "sublayers": NSNull(),
            ]
            playerLayer.actions = [
                "bounds": NSNull(),
                "position": NSNull(),
                "contents": NSNull(),
                "frame": NSNull(),
            ]
            root.addSublayer(playerLayer)
            layer = root
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            // live resize 期间 AppKit 会频繁调用这里；立刻同步 layer，保证跟手。
            syncLayerFrames()
        }

        override func layout() {
            super.layout()
            syncLayerFrames()
        }

        /// 当前屏幕的缩放倍数。还没进 window 时按 Retina 估。
        var displayScale: CGFloat {
            let scale = window?.backingScaleFactor ?? 2
            return scale > 0 ? scale : 1
        }

        private func syncLayerFrames() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            layer?.frame = CGRect(origin: .zero, size: bounds.size)
            playerLayer.frame = bounds
            // 见 iOS 宿主里的同一处注释：sublayer 不继承屏幕缩放。
            superResolutionLayer?.contentsScale = displayScale
            superResolutionLayer?.frame = bounds
        }
    }

    struct PlayerLayerBridge: NSViewRepresentable {
        let player: AVPlayer
        let gravity: AVLayerVideoGravity
        let pictureInPictureController: PlayerPictureInPictureController?
        let superResolutionMode: SuperResolutionMode
        let superResolutionDiagnostics: SuperResolutionDiagnosticsBridge?

        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeNSView(context: Context) -> PlayerLayerHostView {
            let view = PlayerLayerHostView()
            view.playerLayer.player = player
            view.playerLayer.videoGravity = gravity
            pictureInPictureController?.configure(isSupported: false)
            context.coordinator.applySuperResolution(
                mode: superResolutionMode,
                player: player,
                view: view,
                diagnostics: superResolutionDiagnostics
            )
            return view
        }

        func updateNSView(_ view: PlayerLayerHostView, context: Context) {
            if view.playerLayer.player !== player {
                view.playerLayer.player = player
            }
            if view.playerLayer.videoGravity != gravity {
                view.playerLayer.videoGravity = gravity
            }
            pictureInPictureController?.configure(isSupported: false)
            context.coordinator.applySuperResolution(
                mode: superResolutionMode,
                player: player,
                view: view,
                diagnostics: superResolutionDiagnostics
            )
        }

        static func dismantleNSView(_ view: PlayerLayerHostView, coordinator: Coordinator) {
            coordinator.teardown(view: view)
        }

        @MainActor
        final class Coordinator: NSObject, @unchecked Sendable {
            func applySuperResolution(
                mode: SuperResolutionMode,
                player: AVPlayer,
                view: PlayerLayerHostView,
                diagnostics: SuperResolutionDiagnosticsBridge?
            ) {
                let resolved = SuperResolutionCapability.resolved(mode, on: SuperResolutionCapability.defaultDevice)
                if resolved == view.currentMode, view.pipeline != nil || resolved == .off {
                    if resolved.requiresPipeline {
                        view.pipeline?.attach(to: player.currentItem)
                    }
                    return
                }
                view.currentMode = resolved

                if resolved == .off {
                    view.macDisplayLink?.invalidate()
                    view.macDisplayLink = nil
                    view.itemObservation?.invalidate()
                    view.itemObservation = nil
                    view.pipeline?.detach()
                    view.pipeline = nil
                    view.superResolutionLayer?.removeFromSuperlayer()
                    view.superResolutionLayer = nil
                    view.playerLayer.isHidden = false
                    return
                }

                if view.pipeline == nil {
                    if let pipeline = VideoSuperResolutionPipeline() {
                        view.pipeline = pipeline
                        view.superResolutionLayer = pipeline.metalLayer
                        pipeline.metalLayer.actions = [
                            "bounds": NSNull(),
                            "position": NSNull(),
                            "contents": NSNull(),
                            "frame": NSNull(),
                        ]
                        view.layer?.addSublayer(pipeline.metalLayer)
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        pipeline.metalLayer.frame = view.bounds
                        pipeline.metalLayer.contentsScale = view.displayScale
                        CATransaction.commit()
                    } else {
                        view.currentMode = .off
                        view.playerLayer.isHidden = false
                        return
                    }
                    if let pipeline = view.pipeline {
                        pipeline.onDiagnosticsChange = { [weak diagnostics] in diagnostics?.update($0) }
                    }
                }

                view.pipeline?.setMode(resolved)
                view.pipeline?.attach(to: player.currentItem)
                view.playerLayer.isHidden = true

                view.itemObservation?.invalidate()
                view.itemObservation = player.observe(\.currentItem, options: [.new]) { [weak view] _, change in
                    let item = change.newValue ?? nil
                    Task { @MainActor in
                        view?.pipeline?.attach(to: item)
                    }
                }

                if view.macDisplayLink == nil {
                    // macOS 14+ 提供 NSView.displayLink，但绑定到 view 上会比 attach 全局 link 更安全。
                    let link = view.displayLink(target: DisplayLinkTarget(view: view), selector: #selector(DisplayLinkTarget.tick))
                    link.add(to: .main, forMode: .common)
                    view.macDisplayLink = link
                }
            }

            func teardown(view: PlayerLayerHostView) {
                view.macDisplayLink?.invalidate()
                view.macDisplayLink = nil
                view.itemObservation?.invalidate()
                view.itemObservation = nil
                view.pipeline?.detach()
                view.pipeline = nil
                view.superResolutionLayer?.removeFromSuperlayer()
                view.superResolutionLayer = nil
            }
        }
    }

    @MainActor
    final class DisplayLinkTarget: NSObject {
        weak var view: PlayerLayerHostView?
        private var didApplyFrameRate = false
        init(view: PlayerLayerHostView) { self.view = view }
        @objc func tick() {
            guard let view, let pipeline = view.pipeline else { return }
            pipeline.drawNextFrame()
            applyPreferredFrameRate(pipeline: pipeline, view: view)
        }

        /// 片源帧率是开播后才解出来的，所以每帧问一次，拿到了就收敛并不再改。
        private func applyPreferredFrameRate(
            pipeline: VideoSuperResolutionPipeline,
            view: PlayerLayerHostView
        ) {
            guard !didApplyFrameRate,
                  let range = SuperResolutionDisplayLinkPolicy.preferredFrameRateRange(
                      videoFrameRate: pipeline.nominalVideoFrameRate
                  )
            else { return }
            didApplyFrameRate = true
            view.superResolutionDisplayLink?.preferredFrameRateRange = range
        }
    }

#endif
