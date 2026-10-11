import Foundation

/// 播放层上各块东西什么时候露面的唯一规则。
///
/// 这里把「载入」分成了两件事，因为它们该有的样子不一样：
///
/// - **备片**（提取源、载入 item）：手里还没有能播的东西，进度条没有时长、播放键按下去
///   什么也不会发生。控制层照摆，只是这几样灰着不可点，进度条走跑马灯。
/// - **缓冲**（画面已经有了，在等数据）：拖走进度条反而是跳出卡顿最快的办法，所以控制层
///   完全照常。
///
/// 两种情况都要摆一条载入提示，而且**不跟控制层抢位置**——控制层出来的时候它也不许走，
/// 否则用户点一下画面就再也看不出自己是在等还是卡死了。
struct PlayerOverlayVisibility {
    let controlsVisible: Bool
    let isTemporaryBoosting: Bool
    /// 播放器自己报的缓冲状态。备片阶段它也是 true，靠 `phase` 区分。
    let isBuffering: Bool
    let phase: PlaybackCoordinator.Phase
    /// 播放器报上来的时长。刚载完进缓冲的那几秒它常常还是 0。
    let duration: TimeInterval

    /// 还没拿到能播的东西。
    var isPreparing: Bool {
        switch phase {
        case .idle, .extracting, .loading:
            return true
        case .playing, .paused, .finished, .failed:
            return false
        }
    }

    /// 画面已经有了，只是在等数据。
    var isRebuffering: Bool {
        !isPreparing && isBuffering
    }

    /// 顶栏和底部操作栏同进同出 —— 它们是同一层控制层的两头，分开各算一套的话，
    /// 点一下画面会出现只剩一头的半截状态。
    var showsControls: Bool {
        guard !isTemporaryBoosting else { return false }
        // 备片时常驻：这一段用户至少还能换集、换源、改设置，或者干脆退出。
        if isPreparing { return true }
        switch phase {
        case .finished, .failed:
            // 这两种状态下要么得重试要么得退出，藏起来就没有出口了。
            return true
        case .playing, .paused, .idle, .extracting, .loading:
            // 暂停也跟着走：按下暂停常常就是为了看清这一帧，控制层赖着不走反而挡住它。
            // 暂停的那一刻仍然会亮出来（见 PlayerView 的 phase onChange），
            // 只是这之后点一下画面就能收走，再点一下叫回来。
            return controlsVisible
        }
    }

    /// 进度条和播放键能不能按。备片阶段一律不能 —— 按下去只会让人以为没反应。
    var playbackControlsEnabled: Bool {
        !isPreparing
    }

    /// 时长报上来了没有。
    var hasKnownDuration: Bool {
        duration.isFinite && duration > 0
    }

    /// 进度条没有时长可画的时候走跑马灯，也不接受拖拽。
    ///
    /// 不只是备片阶段：刚载完、正在缓冲首帧的那几秒时长同样还是 0，
    /// 这时候画一条停在 0% 的进度条，看起来就是卡在开头动不了。
    var showsIndeterminateProgress: Bool {
        isPreparing || !hasKnownDuration
    }

    /// 点一下暂停、双击快退快进、长按倍速这些手势。备片阶段全部失效。
    var allowsPlaybackInteraction: Bool {
        !isPreparing
    }

    /// 备片阶段压在画面上的那层薄灰。换集时上一集的最后一帧还挂在那儿，
    /// 压一层才看得出这已经不是当前内容了。
    var showsPreparingScrim: Bool {
        isPreparing
    }

    /// 备片 / 缓冲时的那条载入提示。
    ///
    /// **不看控制层的脸色**：等待状态是用户唯一的反馈来源，控制层一出来就把它藏掉，
    /// 等于点一下画面就把「还在转」变成「彻底没反应」。位置上两边错开即可。
    var showsLoadingIndicator: Bool {
        (isPreparing || isRebuffering) && !isTemporaryBoosting
    }

    var showsTemporaryBoostBadge: Bool {
        isTemporaryBoosting
    }
}
