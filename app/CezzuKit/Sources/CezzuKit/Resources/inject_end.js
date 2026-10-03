// inject_end.js
//
// Injected at WKUserScriptInjectionTime.atDocumentEnd. Walks the rendered DOM
// for <video> and <source> elements, reports their src attributes via
// cezzuVideoSink, and installs a MutationObserver to catch any media inserted
// after page load.
(function () {
    'use strict';
    if (window.__cezzuMediaObserverInstalled) return;
    window.__cezzuMediaObserverInstalled = true;

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
            window.webkit.messageHandlers.cezzuVideoSink.postMessage({
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
})();
