import CoreGraphics
import Foundation

public enum PlayerTemporaryBoostRate {
    public static let defaultRate: Float = 2.0
    public static let minimumRate: Float = 1.0
    public static let maximumRate: Float = 3.0
    private static let pointsPerStep: CGFloat = 18

    static func canBegin(isPlaying: Bool, isBuffering: Bool) -> Bool {
        isPlaying && !isBuffering
    }

    public static func resolve(horizontalTranslation: CGFloat) -> Float {
        let rawSteps = horizontalTranslation / pointsPerStep
        let steps =
            rawSteps >= 0
            ? floor(rawSteps)
            : ceil(rawSteps)
        let rate = defaultRate + Float(steps) * 0.1
        return min(max(rate, minimumRate), maximumRate)
    }
}
