import SwiftUI

/// 「弹幕凭证」设置块：开启后用户可以自己填 AppID / AppSecret，优先于内置凭证。
struct DanDanPlayCredentialsSettings: View {
    @AppStorage(DanDanPlayCredentialsStore.useCustomKey) private var useCustom: Bool =
        DanDanPlayCredentialsStore.useCustomDefault
    @AppStorage(DanDanPlayCredentialsStore.appIDKey) private var appID: String = ""
    @AppStorage(DanDanPlayCredentialsStore.appSecretKey) private var appSecret: String = ""

    var body: some View {
        Section {
            Toggle("使用自定义凭证", isOn: $useCustom)
                .cezzuToggleTint()

            if useCustom {
                TextField("AppID", text: $appID)
                    .autocorrectionDisabled(true)
                SecureField("AppSecret", text: $appSecret)
                    .autocorrectionDisabled(true)
            }
        } header: {
            Text("DanDanPlay 凭证")
        } footer: {
            if useCustom {
                Text("开启后优先使用你填入的凭证。关闭则使用 App 内置凭证（如有）。申请入口：https://doc.dandanplay.com/open/")
            } else {
                Text("默认使用 App 内置凭证（如有）。Tube 开源构建未预置凭证，请开启上方开关并填入自己的 AppID / AppSecret，以使用在线弹幕。")
            }
        }
    }
}
