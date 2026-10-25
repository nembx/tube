// inject_end.js
//
// Injected at WKUserScriptInjectionTime.atDocumentEnd. Walks the rendered DOM
// for <video> and <source> elements, reports their src attributes via
// tubeVideoSink, and installs a MutationObserver to catch any media inserted
// after page load.
(function () {
    'use strict';
    if (window.__tubeMediaObserverInstalled) return;
    window.__tubeMediaObserverInstalled = true;

    var BLOCKED = ['googleads', 'googlesyndication.com', 'adtrafficquality', 'doubleclick'];

    function isBlocked(url) {
        if (!url) return true;
        if (typeof url !== 'string') url = String(url);
        if (url.indexOf('blob:') === 0) return true;
        var lower = url.toLowerCase();
        for (var i = 0; i < BLOCKED.length; i++) {
            if (lower.indexOf(BLOCKED[i]) >= 0) return true;
        }
        return false;
    }

    function post(url) {
        if (isBlocked(url)) return;
        try {
            var absolute = new URL(url, location.href).href;
            window.webkit.messageHandlers.tubeVideoSink.postMessage({
                url: absolute,
                source: 'tag'
            });
        } catch (e) {}
    }

    function scanNode(node) {
        if (!node || node.nodeType !== 1) return;
        if (node.tagName === 'VIDEO' || node.tagName === 'SOURCE') {
            if (node.src) post(node.src);
            if (node.getAttribute && node.getAttribute('data-src')) {
                post(node.getAttribute('data-src'));
            }
        }
        if (node.querySelectorAll) {
            var found = node.querySelectorAll('video, source');
            for (var i = 0; i < found.length; i++) {
                if (found[i].src) post(found[i].src);
            }
        }
    }

    scanNode(document.documentElement);

    // iframe 里的视频：站内播放页常把播放器放进 iframe，父文档看不到它的 <video>。
    // 同源时直接读，跨源时读不到（沙箱限制），靠 atDocumentStart 的 XHR/fetch hook 兜底。
    function scanFrames() {
        var frames = document.querySelectorAll('iframe');
        for (var i = 0; i < frames.length; i++) {
            var f = frames[i];
            // 不要把 iframe 的 src 当成视频：那是子页面地址，规则没写 videoURLPattern 时
            // 会被误当成播放源交给播放器。只扫它内部的 video/source。
            try {
                var doc = f.contentDocument;
                if (doc) scanNode(doc.documentElement);
            } catch (e) {}
        }
    }

    // 主动扫描：被动等 XHR/fetch 会漏掉「页面加载完就不再发请求」的站点
    // （视频地址写死在 DOM 或 iframe 里）。参考 Kazumi 的 Timer.periodic 每秒扫一遍。
    window.__tubeScanTimer = setInterval(function () {
        try {
            scanNode(document.documentElement);
            scanFrames();
        } catch (e) {}
    }, 1000);

    try {
        var observer = new MutationObserver(function (mutations) {
            for (var i = 0; i < mutations.length; i++) {
                var added = mutations[i].addedNodes;
                if (!added) continue;
                for (var j = 0; j < added.length; j++) {
                    scanNode(added[j]);
                }
                if (mutations[i].type === 'attributes' && mutations[i].target) {
                    var t = mutations[i].target;
                    if ((t.tagName === 'VIDEO' || t.tagName === 'SOURCE') && t.src) {
                        post(t.src);
                    }
                }
            }
        });
        observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['src']
        });
    } catch (e) {}

    scanFrames();
})();
