import Foundation

/// `WKContentRuleList` 的 JSON 源码。屏蔽广告 / 检测脚本 / 图片资源。
public enum AdBlockRules {
    public static let jsonSource: String = """
        [
            {
                "trigger": { "url-filter": ".*googleads.*" },
                "action": { "type": "block" }
            },
            {
                "trigger": { "url-filter": ".*googlesyndication\\\\.com.*" },
                "action": { "type": "block" }
            },
            {
                "trigger": { "url-filter": ".*adtrafficquality.*" },
                "action": { "type": "block" }
            },
            {
                "trigger": { "url-filter": ".*doubleclick.*" },
                "action": { "type": "block" }
            },
            {
                "trigger": { "url-filter": ".*devtools-detector\\\\.js.*" },
                "action": { "type": "block" }
            },
            {
                "trigger": { "url-filter": ".*prestrain\\\\.html.*" },
                "action": { "type": "block" }
            },
            {
                "trigger": { "url-filter": ".*", "resource-type": ["image"] },
                "action": { "type": "block" }
            }
        ]
        """
}
