import SwiftUI

struct PlayerEpisodeSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var settings: EpisodePlaybackSettings
    let title: String

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    durationRow("跳过片头", seconds: $settings.openingSeconds)
                    durationRow("跳过片尾", seconds: $settings.endingSeconds)
                } header: {
                    Text(title)
                } footer: {
                    Text("按本部番剧保存，后续剧集沿用。设为 0 秒关闭；续播已超过片头时不回退，手动拖回片头也不会再次自动跳过。片头与片尾总时长达到视频长度时不执行跳过。")
                }
                Section {
                    Toggle("自动播放下一集", isOn: $settings.autoPlayNext)
                        .tubeToggleTint()
                } footer: {
                    Text("进入设定的片尾区间或本集播放结束后，显示 5 秒倒计时，可取消或立即播放下一集。关闭时跳到片尾结束位置；最后一集不循环播放。")
                }
            }
            .tubeSettingsFormStyle()
            .navigationTitle("片头片尾与连续播放")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func durationRow(_ title: String, seconds: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: seconds, in: 0...600, step: 5) {
                HStack {
                    Text(title)
                    Spacer()
                    Text("\(Int(seconds.wrappedValue)) 秒")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }
}
