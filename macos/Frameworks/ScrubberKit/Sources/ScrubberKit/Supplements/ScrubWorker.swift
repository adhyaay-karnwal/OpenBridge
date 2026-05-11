//
//  ScrubWorker.swift
//  AppleQuery
//
//  Created by QAQ on 2023/8/23.
//

import WebKit

private let accessControlSourceCode = ###"""
[
  {
    "trigger": {
      "url-filter": ".*",
      "resource-type": ["style-sheet"]
    },
    "action": {
      "type": "block"
    }
  },
  {
    "trigger": {
      "url-filter": ".*",
      "resource-type": ["font"]
    },
    "action": {
      "type": "block"
    }
  },
  {
    "trigger": {
      "url-filter": ".*",
      "resource-type": ["image"]
    },
    "action": {
      "type": "block"
    }
  },
  {
    "trigger": {
      "url-filter": ".*",
      "resource-type": ["media"]
    },
    "action": {
      "type": "block"
    }
  }
]
"""###
private var accessControlRule: WKContentRuleList?

class ScrubWorker: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let web = WebView()
    private let baseUrl: URL

    struct ScrubResult {
        let url: URL
        let document: String
    }

    private var completion: ((ScrubResult) -> Void)?

    init(baseUrl: URL, softTimeout: TimeInterval = 15, completion: @escaping (ScrubResult) -> Void) {
        self.baseUrl = baseUrl
        self.completion = completion

        super.init()

        web.uiDelegate = self
        web.navigationDelegate = self
        let request = URLRequest(
            url: baseUrl,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: softTimeout
        )
        web.load(request)

        scheduleContentReporter(delay: softTimeout)
    }

    deinit {
        performCompletion()
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        web.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight)") { _, _ in
        }
        scheduleContentReporter(delay: 3) // in case of another navigation fired by js
    }

    var navigationLimit = 4

    func webView(
        _: WKWebView,
        decidePolicyFor _: WKNavigationAction,
        preferences _: WKWebpagePreferences,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        guard navigationLimit > 0 else {
            decisionHandler(.cancel, .init())
            scheduleContentReporter(delay: 0)
            return
        }
        navigationLimit -= 1
        scheduleContentReporter(delay: 5)
        decisionHandler(.allow, .init())
    }

    func cancel() {
        if Thread.isMainThread {
            performCompletion()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.performCompletion()
            }
        }
    }

    func scheduleContentReporter(delay: Double) {
        assert(Thread.isMainThread)
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(performCompletion),
            object: nil
        )
        perform(#selector(performCompletion), with: nil, afterDelay: delay)
    }

    @objc
    private func performCompletion() {
        guard let completion else { return }
        self.completion = nil
        web.evaluateJavaScript("document.documentElement.outerHTML") { data, _ in
            completion(.init(url: self.web.url ?? self.baseUrl, document: data as? String ?? ""))
        }
    }
}

private extension ScrubWorker {
    class WebView: WKWebView {
        init() {
            let config = WKWebViewConfiguration()

            // MARK: - 通用无头配置

            // 抑制增量渲染：在内存中完全加载后再处理，提高无头模式下的处理效率
            config.suppressesIncrementalRendering = true
            // 强制升级 HTTPS
            config.upgradeKnownHostsToHTTPS = true
            // 禁止 AirPlay
            config.allowsAirPlayForMediaPlayback = false
            // 禁止所有媒体自动播放
            config.mediaTypesRequiringUserActionForPlayback = .all

            // 禁止 JS 自动打开新窗口 (防止弹窗干扰)
            config.preferences.javaScriptCanOpenWindowsAutomatically = false

            // 数据存储 (保持原逻辑，使用持久化存储)
            config.websiteDataStore = .init(forIdentifier: ScrubberConfiguration.storageIdentifier)

            // MARK: - iOS 特定配置

            #if os(iOS)
                config.allowsInlineMediaPlayback = false
                // 禁止画中画
                config.allowsPictureInPictureMediaPlayback = false
                // 移除数据检测器 (电话、日历等)，节省 CPU
                config.dataDetectorTypes = []
                // 忽略视口限制，允许页面按原始布局渲染
                config.ignoresViewportScaleLimits = true
            #endif

            // MARK: - macOS 特定配置

            #if os(macOS)
                // 遵循网页内容的排版方向
                config.userInterfaceDirectionPolicy = .content
            #endif

            // MARK: - 版本适配

            if #available(iOS 17.0, macOS 14.0, *) {
                config.allowsInlinePredictions = false
            }

            // MARK: - 注入脚本规则

            if let accessControlRule {
                config.userContentController.add(accessControlRule)
            } else {
                assertionFailure("accessControlRule is nil, please call setup at boot")
            }

            // 初始化
            // 注意：无头模式下 frame 大小会影响 CSS 媒体查询结果 模拟一个长滚动页面
            super.init(frame: .init(x: 0, y: 0, width: 1024, height: 3000), configuration: config)

            // MARK: - User Agent 设置

            // 必须在 super.init 之后设置 customUserAgent，而不是使用 applicationNameForUserAgent
            // applicationNameForUserAgent 只会追加在默认 UA 后面，而 customUserAgent 是完全替换
            customUserAgent = ScrubberConfiguration.desktopChromeUserAgent
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }
    }
}

extension ScrubWorker {
    static func compileAccessRules() {
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "PlainTextAccessControlRule",
            encodedContentRuleList: accessControlSourceCode
        ) { list, _ in
            accessControlRule = list
        }
    }
}
