import Foundation

/// Polls the GitHub Releases API for the latest tagged release of IconPing and
/// compares its semantic version with the running build.
///
/// We use this minimal flow instead of Sparkle for v1.x — no signing infra
/// required, no auto-install, just a one-shot version check that opens the
/// Releases page in the user's browser when an update is available.
public struct UpdateChecker: Sendable {

    public struct LatestRelease: Sendable, Equatable {
        public let tagName: String        // e.g. "v1.0.12"
        public let semver: Semver?        // parsed
        public let htmlURL: URL           // releases page for this version
        public let publishedAt: Date?
        public let body: String           // release notes (used by alert)
    }

    public struct Semver: Sendable, Equatable, Comparable {
        public let major: Int, minor: Int, patch: Int
        public init?(_ s: String) {
            let cleaned = s.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let parts = cleaned.split(separator: ".").map(String.init)
            guard parts.count >= 2 else { return nil }
            guard let M = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            self.major = M
            self.minor = m
            self.patch = parts.count >= 3 ? (Int(parts[2]) ?? 0) : 0
        }
        public static func < (l: Semver, r: Semver) -> Bool {
            if l.major != r.major { return l.major < r.major }
            if l.minor != r.minor { return l.minor < r.minor }
            return l.patch < r.patch
        }
    }

    public enum CheckResult: Sendable, Equatable {
        case upToDate(current: Semver)
        case updateAvailable(current: Semver, latest: LatestRelease)
        case error(message: String)
    }

    public let owner: String
    public let repo: String

    public init(owner: String = "opensubtitles", repo: String = "iconping") {
        self.owner = owner
        self.repo = repo
    }

    /// Convenience that reads the running app's CFBundleShortVersionString.
    public func check() async -> CheckResult {
        let info = Bundle.main.infoDictionary
        let short = (info?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
        return await check(currentVersion: short)
    }

    public func check(currentVersion: String) async -> CheckResult {
        guard let current = Semver(currentVersion) else {
            return .error(message: "Can't parse current version '\(currentVersion)'")
        }
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("IconPing/1.0 update-checker", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                return .error(message: "GitHub returned HTTP \(code)")
            }
            let release = try parse(data: data)
            guard let latest = release.semver else {
                return .error(message: "Latest release tag '\(release.tagName)' is not semver")
            }
            if latest > current {
                return .updateAvailable(current: current, latest: release)
            }
            return .upToDate(current: current)
        } catch {
            return .error(message: error.localizedDescription)
        }
    }

    private func parse(data: Data) throws -> LatestRelease {
        struct Payload: Decodable {
            let tag_name: String
            let html_url: String
            let published_at: String?
            let body: String?
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let url = URL(string: payload.html_url)
            ?? URL(string: "https://github.com/opensubtitles/iconping/releases")!
        let date: Date? = payload.published_at.flatMap { ISO8601DateFormatter().date(from: $0) }
        return LatestRelease(
            tagName: payload.tag_name,
            semver: Semver(payload.tag_name),
            htmlURL: url,
            publishedAt: date,
            body: payload.body ?? ""
        )
    }
}
