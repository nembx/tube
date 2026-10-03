import Foundation
import Testing
@testable import CezzuKit

@Suite("PlayerVolumeSliderGeometry")
struct PlayerVolumeSliderGeometryTests {

    @Test("落点按比例换算成音量")
    func volumeFromLocation() {
        #expect(PlayerVolumeSliderGeometry.volume(atX: 0, width: 100) == 0)
        #expect(PlayerVolumeSliderGeometry.volume(atX: 50, width: 100) == 0.5)
        #expect(PlayerVolumeSliderGeometry.volume(atX: 100, width: 100) == 1)
    }

    @Test("拖出轨道两端时夹紧")
    func volumeClampsOutsideTrack() {
        #expect(PlayerVolumeSliderGeometry.volume(atX: -40, width: 100) == 0)
        #expect(PlayerVolumeSliderGeometry.volume(atX: 260, width: 100) == 1)
    }

    @Test("轨道宽度为 0 时不做除法")
    func volumeHandlesZeroWidth() {
        #expect(PlayerVolumeSliderGeometry.volume(atX: 10, width: 0) == 0)
    }

    @Test("已填段占比同样夹在 0...1")
    func fractionClamps() {
        #expect(PlayerVolumeSliderGeometry.fraction(0.25) == 0.25)
        #expect(PlayerVolumeSliderGeometry.fraction(-1) == 0)
        #expect(PlayerVolumeSliderGeometry.fraction(3) == 1)
        #expect(PlayerVolumeSliderGeometry.fraction(.nan) == 0)
    }

    @Test("喇叭图标跟着音量分档")
    func iconTracksLevel() {
        #expect(PlayerVolumeSliderGeometry.icon(for: 0) == "speaker.slash.fill")
        #expect(PlayerVolumeSliderGeometry.icon(for: 0.2) == "speaker.wave.1.fill")
        #expect(PlayerVolumeSliderGeometry.icon(for: 0.5) == "speaker.wave.2.fill")
        #expect(PlayerVolumeSliderGeometry.icon(for: 1) == "speaker.wave.3.fill")
        // 脏值当静音，不至于画出个满音量的喇叭。
        #expect(PlayerVolumeSliderGeometry.icon(for: .nan) == "speaker.slash.fill")
    }
}
