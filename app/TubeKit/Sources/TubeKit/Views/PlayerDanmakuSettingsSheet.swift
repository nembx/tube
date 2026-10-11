import SwiftUI

public struct PlayerDanmakuSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                DanmakuSettingsContent()
            }
            .formStyle(.grouped)
            .navigationTitle("弹幕设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
