import Cocoa

struct MEReleaseAsset {
    let name: String
    let url: URL
    let size: Int
}

struct UpdateCheckResult {
    var ok = false
    var hasUpdate = false
    var latestVersion = ""
    var releaseNotes = ""
    var assets: [MEReleaseAsset] = []
    var releasePage: URL?
    var error: String?
}

/// GitHub Releases 更新检查。
/// - 启动后静默检查一次，之后每小时检查一次；
/// - 自动检查失败重试 5 次后静默放弃，手动检查失败重试 3 次后提示错误；
/// - 发现新版本时提供「下载更新 / 忽略这个版本 / 忽略一次」。
final class UpdateService {
    static let shared = UpdateService()

    static let repoOwner = "MaoRM93"
    static let repoName = "EverythinginMac"
    static let repoURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)")!

    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
    private static let skippedVersionKey = "SkippedUpdateVersion"
    private static let checkInterval: TimeInterval = 3600

    private let timeout: TimeInterval = 20
    private let retryDelay: TimeInterval = 2

    private var timer: Timer?
    private var checking = false
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        // 与 Grade Monitor 一致：启动后静默检查一次，此后每小时一次。
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.check(manual: false)
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            self?.check(manual: false)
        }
    }

    func checkManually() {
        check(manual: true)
    }

    // MARK: - Checking

    private func check(manual: Bool) {
        guard !checking else {
            if manual {
                showInfo("正在检查更新", "请稍候，检查完成后会给出结果。")
            }
            return
        }
        checking = true

        let retries = manual ? 3 : 5
        fetch(attempt: 0, retries: retries) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.checking = false
                self.handle(result, manual: manual)
            }
        }
    }

    private func fetch(attempt: Int, retries: Int, completion: @escaping (UpdateCheckResult) -> Void) {
        var request = URLRequest(url: Self.latestReleaseAPI, timeoutInterval: timeout)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacEverything-UpdateCheck", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            var result = UpdateCheckResult()

            guard let http = response as? HTTPURLResponse else {
                result.error = error?.localizedDescription ?? "网络异常"
                self.retryOrFinish(attempt: attempt, retries: retries, result: result, completion: completion)
                return
            }

            // 仓库还没有任何 Release，重试也没有意义。
            if http.statusCode == 404 {
                result.error = "仓库暂未发布任何版本"
                completion(result)
                return
            }

            guard http.statusCode == 200, let data else {
                result.error = "GitHub API 返回 \(http.statusCode)"
                self.retryOrFinish(attempt: attempt, retries: retries, result: result, completion: completion)
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                result.error = "GitHub 返回了非预期的数据格式"
                self.retryOrFinish(attempt: attempt, retries: retries, result: result, completion: completion)
                return
            }

            let tag = (json["tag_name"] as? String) ?? ""
            guard !tag.isEmpty else {
                result.error = "未获取到版本号"
                completion(result)
                return
            }

            result.ok = true
            result.latestVersion = Self.normalize(tag)
            result.releaseNotes = ((json["body"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let page = json["html_url"] as? String {
                result.releasePage = URL(string: page)
            }
            result.assets = (json["assets"] as? [[String: Any]] ?? []).compactMap { raw in
                guard let name = raw["name"] as? String,
                      let urlString = raw["browser_download_url"] as? String,
                      let url = URL(string: urlString) else { return nil }
                return MEReleaseAsset(name: name, url: url, size: raw["size"] as? Int ?? 0)
            }
            result.hasUpdate = Self.isNewer(result.latestVersion, than: AppInfo.version)
            completion(result)
        }.resume()
    }

    private func retryOrFinish(attempt: Int,
                               retries: Int,
                               result: UpdateCheckResult,
                               completion: @escaping (UpdateCheckResult) -> Void) {
        guard attempt < retries else {
            var final = result
            if attempt > 0 {
                final.error = (result.error ?? "网络异常") + "（已重试 \(attempt) 次）"
            }
            completion(final)
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + retryDelay) { [weak self] in
            self?.fetch(attempt: attempt + 1, retries: retries, completion: completion)
        }
    }

    // MARK: - Result handling

    private func handle(_ result: UpdateCheckResult, manual: Bool) {
        guard result.ok else {
            if manual {
                showInfo("检查更新失败", result.error ?? "未知错误")
            }
            return
        }

        guard result.hasUpdate else {
            if manual {
                showInfo("已是最新版本", "当前版本 \(AppInfo.version) 已是最新版本。")
            }
            return
        }

        let skipped = UserDefaults.standard.string(forKey: Self.skippedVersionKey)
        if !manual && skipped == result.latestVersion {
            return
        }

        presentUpdate(result)
    }

    private func presentUpdate(_ result: UpdateCheckResult) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "发现新版本 \(result.latestVersion)"
        var details = "当前版本：\(AppInfo.version)"
        if !result.releaseNotes.isEmpty {
            let notes = result.releaseNotes.count > 1200
                ? String(result.releaseNotes.prefix(1200)) + "…"
                : result.releaseNotes
            details += "\n\n\(notes)"
        }
        alert.informativeText = details
        alert.addButton(withTitle: "下载更新")
        alert.addButton(withTitle: "忽略这个版本")
        alert.addButton(withTitle: "忽略一次")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openDownload(result)
        case .alertSecondButtonReturn:
            UserDefaults.standard.set(result.latestVersion, forKey: Self.skippedVersionKey)
        default:
            break
        }
    }

    private func openDownload(_ result: UpdateCheckResult) {
        let asset = result.assets.first { $0.name.lowercased().contains("mac") }
        let target = asset?.url
            ?? result.releasePage
            ?? Self.repoURL.appendingPathComponent("releases")
        NSWorkspace.shared.open(target)
    }

    private func showInfo(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    // MARK: - Version comparison

    static func normalize(_ tag: String) -> String {
        var value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("v") {
            value.removeFirst()
        }
        return value
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = numericComponents(candidate)
        let rhs = numericComponents(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right {
                return left > right
            }
        }
        return false
    }

    private static func numericComponents(_ version: String) -> [Int] {
        version.split(separator: ".").map { part in
            Int(part.prefix(while: { $0.isNumber })) ?? 0
        }
    }
}
