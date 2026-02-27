import Foundation

struct UpdateInfo {
    let version: String
    let tag: String
    let releaseURL: URL
    let downloadURL: URL
}

enum UpdateCheckResult {
    case updateAvailable(UpdateInfo)
    case upToDate(String)
    case failed(String)
}

final class UpdateChecker {
    private let latestReleaseAPI = URL(string: "https://api.github.com/repos/serhiiboreiko/asiair-sync/releases/latest")!

    func checkForUpdate(currentVersion: String) async -> UpdateCheckResult {
        var request = URLRequest(url: latestReleaseAPI)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ASIAIRSync", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed("Invalid response")
            }

            guard (200...299).contains(http.statusCode) else {
                return .failed("HTTP \(http.statusCode)")
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestVersion = normalizeVersion(release.tagName)
            let current = normalizeVersion(currentVersion)

            if latestVersion.compare(current, options: .numeric) == .orderedDescending {
                let downloadURL = release.assets.first { asset in
                    asset.name.lowercased().hasSuffix(".dmg")
                }?.browserDownloadURL ?? release.htmlURL

                return .updateAvailable(
                    UpdateInfo(
                        version: latestVersion,
                        tag: release.tagName,
                        releaseURL: release.htmlURL,
                        downloadURL: downloadURL
                    )
                )
            }

            return .upToDate(latestVersion)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func normalizeVersion(_ raw: String) -> String {
        var normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("v") || normalized.hasPrefix("V") {
            normalized.removeFirst()
        }
        return normalized
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
