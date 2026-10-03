// inject_start.js
//
// Injected at WKUserScriptInjectionTime.atDocumentStart, BEFORE any page script.
// Hooks XMLHttpRequest, fetch, and Response.text so that any HLS manifest or
// video URL flowing through the page is reported back to Swift via
// webkit.messageHandlers.cezzuVideoSink.postMessage(...).
//
// See design.md D4 for the WKWebView-based extraction strategy.
(function () {
    'use strict';
    if (window.__cezzuVideoSinkInstalled) return;
    window.__cezzuVideoSinkInstalled = true;

    var BLOCKED_HOSTS = [
        'googleads',
        'googlesyndication.com',
        'adtrafficquality',
        'doubleclick'
    ];
    var EXTENSION_BLACKLIST = [
        '.js', '.css', '.html', '.htm', '.json',
        '.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp', '.ico',
        '.woff', '.woff2', '.ttf', '.otf', '.wasm'
    ];

    function isBlockedHost(url) {
        try {
            var lower = String(url).toLowerCase();
            for (var i = 0; i < BLOCKED_HOSTS.length; i++) {
                if (lower.indexOf(BLOCKED_HOSTS[i]) >= 0) return true;
            }
        } catch (e) {}
        return false;
    }

    function isM3U8Url(url) {
        try {
            var u = new URL(url, location.href);
            return u.pathname.toLowerCase().indexOf('.m3u8') >= 0;
        } catch (e) {
            return String(url).toLowerCase().indexOf('.m3u8') >= 0;
        }
    }

    function isM3U8Body(text) {
        if (!text || typeof text !== 'string') return false;
        return text.trimStart().indexOf('#EXTM3U') === 0;
    }

    function hasBlacklistedExtension(url) {
        try {
            var u = new URL(url, location.href);
            var path = u.pathname.toLowerCase();
            for (var i = 0; i < EXTENSION_BLACKLIST.length; i++) {
                if (path.endsWith(EXTENSION_BLACKLIST[i])) return true;
            }
        } catch (e) {}
        return false;
    }

    function post(payload) {
        try {
            window.webkit.messageHandlers.cezzuVideoSink.postMessage(payload);
        } catch (e) {
            // sink not installed yet — ignore
        }
    }

    function reportUrl(url, source) {
        if (!url) return;
        if (isBlockedHost(url)) return;
        if (typeof url === 'string' && url.indexOf('blob:') === 0) return;
        try {
            var absolute = new URL(url, location.href).href;
            post({ url: absolute, source: source });
        } catch (e) {
            post({ url: String(url), source: source });
        }
    }

    // ----- XMLHttpRequest hook -----
    var origOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (method, url) {
        try {
            this.__cezzuUrl = url;
            this.__cezzuMethod = method;
            if (isM3U8Url(url)) {
                reportUrl(url, 'xhr-url');
            }
            this.addEventListener('load', function () {
                try {
                    var ct = this.getResponseHeader && this.getResponseHeader('Content-Type');
                    if (ct && (ct.indexOf('mpegurl') >= 0 || ct.indexOf('vnd.apple.mpegurl') >= 0)) {
                        reportUrl(this.__cezzuUrl, 'xhr-ct');
                        return;
                    }
                    if (this.responseType === '' || this.responseType === 'text') {
                        if (isM3U8Body(this.responseText)) {
                            reportUrl(this.__cezzuUrl, 'xhr-body');
                        }
                    }
                } catch (err) {}
            });
        } catch (err) {}
        return origOpen.apply(this, arguments);
    };

    // Range request capture (for progressive MP4)
    var origSend = XMLHttpRequest.prototype.send;
    var origSetHeader = XMLHttpRequest.prototype.setRequestHeader;
    XMLHttpRequest.prototype.setRequestHeader = function (name, value) {
        try {
            if (String(name).toLowerCase() === 'range') {
                this.__cezzuHasRange = true;
            }
        } catch (e) {}
        return origSetHeader.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function () {
        try {
            if (this.__cezzuHasRange && this.__cezzuUrl && !hasBlacklistedExtension(this.__cezzuUrl)) {
                reportUrl(this.__cezzuUrl, 'range');
            }
        } catch (e) {}
        return origSend.apply(this, arguments);
    };

    // ----- fetch hook -----
    var origFetch = window.fetch;
    if (typeof origFetch === 'function') {
        window.fetch = function (input, init) {
            var url = (typeof input === 'string') ? input : (input && input.url);
            try {
                if (isM3U8Url(url)) {
                    reportUrl(url, 'fetch-url');
                }
                var headers = (init && init.headers) || (input && input.headers);
                if (headers) {
                    var rangeValue = null;
                    if (typeof headers.get === 'function') {
                        rangeValue = headers.get('range') || headers.get('Range');
                    } else if (typeof headers === 'object') {
                        rangeValue = headers['range'] || headers['Range'];
                    }
                    if (rangeValue && !hasBlacklistedExtension(url)) {
                        reportUrl(url, 'fetch-range');
                    }
                }
            } catch (e) {}
            return origFetch.apply(this, arguments).then(function (response) {
                try {
                    var ct = response.headers && response.headers.get && response.headers.get('Content-Type');
                    if (ct && (ct.indexOf('mpegurl') >= 0 || ct.indexOf('vnd.apple.mpegurl') >= 0)) {
                        reportUrl(response.url || url, 'fetch-ct');
                        return response;
                    }
                    var cloned = response.clone();
                    cloned.text().then(function (text) {
                        if (isM3U8Body(text)) {
                            reportUrl(response.url || url, 'fetch-body');
                        }
                    }).catch(function () {});
                } catch (e) {}
                return response;
            });
        };
    }
})();
