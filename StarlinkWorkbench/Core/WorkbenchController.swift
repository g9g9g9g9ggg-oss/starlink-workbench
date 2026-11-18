import Foundation
import WebKit
import SafariServices
import UniformTypeIdentifiers
import PhotosUI

/// 工作台 WebView 壳控制器：iOS 版对应安卓 MainActivity。
/// - 注入微信皮肤（与安卓同款脚本）
/// - JS 桥 StarlinkApp.torch → 闪光灯；navigator.vibrate polyfill → 触感
/// - 外链走应用内浏览器；下载接原生下载器；文件选择接相册/相机/文件
final class WorkbenchController: NSObject, ObservableObject {

    // MARK: - 壳层状态（供顶部进度条/标题等使用）

    @Published var progress: Double = 0
    @Published var pageTitle: String = "星链工作台"
    @Published var canGoBack: Bool = false

    weak var model: AppModel?
    let webView: WKWebView
    private var observations: [NSKeyValueObservation] = []
    private var downloadDestinations: [WKDownload: URL] = [:]
    var filePickerCoordinator: FilePickerCoordinator?

    init(model: AppModel) {
        self.model = model
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()               // 持久化会话，与 Safari 天然隔离（对齐安卓独立数据目录）
        cfg.allowsInlineMediaPlayback = true

        let ucc = cfg.userContentController
        ucc.addUserScript(WKUserScript(source: WorkbenchController.skinScript,
                                       injectionTime: .atDocumentStart,
                                       forMainFrameOnly: false))
        ucc.addUserScript(WKUserScript(source: WorkbenchController.bridgeScript,
                                       injectionTime: .atDocumentStart,
                                       forMainFrameOnly: true))

        webView = WKWebView(frame: .zero, configuration: cfg)
        super.init()

        ucc.add(self, name: "torch")
        ucc.add(self, name: "vibrate")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true   // 侧滑返回（微信同款）

        let pObs = webView.observe(\.estimatedProgress, options: [.new]) { web, _ in
            DispatchQueue.main.async { self.progress = web.estimatedProgress }
        }
        let tObs = webView.observe(\.title, options: [.new]) { web, _ in
            DispatchQueue.main.async {
                self.pageTitle = (web.title?.isEmpty == false) ? web.title! : "星链工作台"
            }
        }
        let bObs = webView.observe(\.canGoBack, options: [.new]) { web, _ in
            DispatchQueue.main.async { self.canGoBack = web.canGoBack }
        }
        observations = [pObs, tObs, bObs]
    }

    // MARK: - 注入脚本

    /// 微信皮肤（与安卓 1.6.1 注入的脚本逐字一致）
    static let skinScript = """
    (function(){try{localStorage.setItem('xl_skin','wechat');document.documentElement.dataset.skin='wechat';}catch(e){}})();
    """

    /// 原生桥：闪光灯 + 震动（对齐安卓 addJavascriptInterface + navigator.vibrate polyfill）
    static let bridgeScript = """
    (function(){
      try {
        window.StarlinkApp = {
          isApp: true,
          torch: function (n) {
            try { webkit.messageHandlers.torch.postMessage(Math.max(1, Math.min(6, n || 2))); } catch (e) {}
          },
          vibrate: function (p) {
            try { webkit.messageHandlers.vibrate.postMessage(JSON.stringify(Array.isArray(p) ? p : [350, 200, 350])); } catch (e) {}
          }
        };
        if (!navigator.vibrate) {
          navigator.vibrate = function (p) {
            try { window.StarlinkApp.vibrate(p); } catch (e) {}
            return true;
          };
        }
      } catch (e) {}
    })();
    """

    // MARK: - 加载与会话桥接

    func load(base: String, path: String) {
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let url = URL(string: trimmed + path) else { return }
        adoptSessionCookies(for: url)
        DispatchQueue.main.async { self.webView.load(URLRequest(url: url)) }
    }

    /// 原生登录的会话 Cookie 同步进 WKWebView（xl_session httpOnly，无法反向读取，必须正向注入）
    func adoptSessionCookies(for url: URL) {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        for cookie in HTTPCookieStorage.shared.cookies(for: url) ?? [] {
            store.setCookie(cookie)
        }
    }

    /// 断网恢复后的重载（会话保持，免登录，对齐桌面/安卓壳）
    func reloadIfWorkbench() {
        DispatchQueue.main.async {
            if let host = self.webView.url?.host, host.contains(Constants.workbenchHostSuffix) {
                self.webView.reload()
            }
        }
    }

    /// 路由到接待页（通知/深链入口）
    func goToReception() {
        Task { @MainActor in
            guard let base = self.model?.baseURL?.absoluteString else { return }
            self.load(base: base, path: "/reception")
        }
    }

    func evaluateJS(_ js: String) {
        DispatchQueue.main.async { self.webView.evaluateJavaScript(js, completionHandler: nil) }
    }

    /// 清空网页数据（Cookie/缓存/存储）—— 退出登录用
    func clearWebData() {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            store.removeData(ofTypes: types, for: records, completionHandler: {})
        }
    }

    // MARK: - 呈现辅助

    private func topViewController() -> UIViewController? {
        var root = webView.window?.rootViewController
        while let presented = root?.presentedViewController {
            root = presented
        }
        return root
    }

    private func openExternal(_ url: URL) {
        DispatchQueue.main.async {
            if let vc = self.topViewController() {
                let safari = SFSafariViewController(url: url)
                safari.modalPresentationStyle = .pageSheet
                vc.present(safari, animated: true)
            } else {
                UIApplication.shared.open(url)
            }
        }
    }

    private func showToastOnMain(_ text: String) {
        Task { @MainActor in self.model?.showToast(text) }
    }
}

// MARK: - JS 消息桥

extension WorkbenchController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        switch message.name {
        case "torch":
            let n = (message.body as? NSNumber)?.intValue ?? 2
            TorchBlinker.blink(n)
        case "vibrate":
            guard let json = message.body as? String,
                  let data = json.data(using: .utf8),
                  let pattern = try? JSONSerialization.jsonObject(with: data) as? [Int] else { return }
            DispatchQueue.main.async { HapticEngine.vibrate(pattern) }
        default:
            break
        }
    }
}

// MARK: - 导航策略

extension WorkbenchController: WKNavigationDelegate {

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        let prefs = preferences
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel, prefs)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if ["tel", "mailto", "sms", "itms-apps"].contains(scheme) {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
            decisionHandler(.cancel, prefs)
            return
        }
        if scheme == "starlink" {
            Task { @MainActor in self.model?.handleOpenURL(url) }
            decisionHandler(.cancel, prefs)
            return
        }

        let isWorkbench = url.host?.contains(Constants.workbenchHostSuffix) ?? false

        // 新窗口：本域同窗口加载（对齐安卓/桌面单窗口策略），外域应用内浏览器
        if navigationAction.targetFrame == nil {
            if isWorkbench {
                DispatchQueue.main.async { webView.load(URLRequest(url: url)) }
                decisionHandler(.cancel, prefs)
            } else {
                openExternal(url)
                decisionHandler(.cancel, prefs)
            }
            return
        }
        // 链接点击跳外域 → 应用内浏览器（对齐「聊天外链走系统浏览器」策略）
        if !isWorkbench && navigationAction.navigationType == .linkActivated {
            openExternal(url)
            decisionHandler(.cancel, prefs)
            return
        }
        decisionHandler(.allow, prefs)
    }

    // MARK: 下载（对齐安卓 DownloadManager +「已开始下载」提示）

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
        showToastOnMain("已开始下载")
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
        showToastOnMain("已开始下载")
    }
}

// MARK: - 下载委托

extension WorkbenchController: WKDownloadDelegate {
    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let safeName = suggestedFilename.isEmpty ? "download.bin" : suggestedFilename
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString.prefix(6))_\(safeName)")
        downloadDestinations[download] = dest
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = downloadDestinations.removeValue(forKey: download) else { return }
        DispatchQueue.main.async {
            Task { @MainActor in self.model?.showToast("下载完成，可分享保存") }
            guard let vc = self.topViewController() else { return }
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            vc.present(activity, animated: true)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: download)
        showToastOnMain("下载失败：\(error.localizedDescription)")
    }
}

// MARK: - UI 委托（弹窗/文件选择/权限）

extension WorkbenchController: WKUIDelegate {

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            let isWorkbench = url.host?.contains(Constants.workbenchHostSuffix) ?? false
            if isWorkbench {
                webView.load(URLRequest(url: url))
            } else {
                openExternal(url)
            }
        }
        return nil
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            guard let vc = self.topViewController() else { completionHandler(); return }
            let alert = UIAlertController(title: webView.title ?? "提示", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
            vc.present(alert, animated: true)
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            guard let vc = self.topViewController() else { completionHandler(false); return }
            let alert = UIAlertController(title: webView.title ?? "确认", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
            vc.present(alert, animated: true)
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        DispatchQueue.main.async {
            guard let vc = self.topViewController() else { completionHandler(nil); return }
            let alert = UIAlertController(title: "", message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
            vc.present(alert, animated: true)
        }
    }

    /// 相机/麦克风（网页需要时直接放行，与安卓 WebView 同等能力）
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }

    /// 文件选择：拍照 / 相册 / 文件（对齐安卓 onShowFileChooser）
    func webView(_ webView: WKWebView,
                 runFileChooserWith parameters: WKFileChooserParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        DispatchQueue.main.async {
            guard let vc = self.topViewController() else {
                completionHandler(nil)
                return
            }
            let coordinator = FilePickerCoordinator(completion: completionHandler)
            coordinator.owner = self
            self.filePickerCoordinator = coordinator
            coordinator.presentActionSheet(from: vc, allowMultiple: parameters.allowsMultipleSelection)
        }
    }
}

// MARK: - 文件选择协调器

final class FilePickerCoordinator: NSObject,
                                   PHPickerViewControllerDelegate,
                                   UIImagePickerControllerDelegate,
                                   UINavigationControllerDelegate,
                                   UIDocumentPickerDelegate {

    var owner: WorkbenchController?
    private let completion: ([URL]?) -> Void
    private var multiple = false

    init(completion: @escaping ([URL]?) -> Void) {
        self.completion = completion
    }

    func presentActionSheet(from vc: UIViewController, allowMultiple: Bool) {
        multiple = allowMultiple
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "拍照", style: .default) { [weak self] _ in
            self?.openCamera(from: vc)
        })
        sheet.addAction(UIAlertAction(title: "从相册选择", style: .default) { [weak self] _ in
            self?.openPhotos(from: vc)
        })
        sheet.addAction(UIAlertAction(title: "从文件选择", style: .default) { [weak self] _ in
            self?.openDocuments(from: vc)
        })
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            self?.finish(nil)
        })
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = vc.view
        }
        vc.present(sheet, animated: true)
    }

    private func openCamera(from vc: UIViewController) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            openPhotos(from: vc)
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        vc.present(picker, animated: true)
    }

    private func openPhotos(from vc: UIViewController) {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = multiple ? 9 : 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        vc.present(picker, animated: true)
    }

    private func openDocuments(from vc: UIViewController) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image, .data], asCopy: true)
        picker.delegate = self
        vc.present(picker, animated: true)
    }

    // MARK: PHPicker

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { finish(nil); return }
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for result in results {
            group.enter()
            result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                defer { group.leave() }
                guard let url else { return }
                let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "." + ext)
                try? FileManager.default.copyItem(at: url, to: dest)
                lock.lock()
                urls.append(dest)
                lock.unlock()
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.finish(urls.isEmpty ? nil : urls)
        }
    }

    // MARK: 相机

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        if let image = info[.originalImage] as? UIImage,
           let data = image.jpegData(compressionQuality: 0.9) {
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".jpg")
            try? data.write(to: dest)
            finish([dest])
        } else {
            finish(nil)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        finish(nil)
    }

    // MARK: 文件

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finish(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(nil)
    }

    private func finish(_ urls: [URL]?) {
        let callback = completion
        owner?.filePickerCoordinator = nil
        callback(urls)
    }
}
