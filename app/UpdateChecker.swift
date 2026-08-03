import Foundation

/// Asks GitHub whether a newer release exists.
///
/// This is the only outbound request the app can ever make, and it is off until
/// the user answers the prompt on first launch. The privacy policy is specific
/// about what leaves the machine, so this file deliberately keeps that surface
/// as small as it can be: one GET, no body, no identifiers, no redirect
/// following beyond what URLSession does for the release API itself.
///
/// Nothing here uses UNUserNotificationCenter. A system notification would ask
/// the user to grant a permission purely so the app can tell them about itself,
/// which is a poor trade. The result surfaces as a banner in the window instead.
enum UpdateConsent: String {
    case unasked, granted, declined
}

/// Comparison of two dotted version strings, kept pure so it can be tested
/// without a network or a bundle.
enum Version {
    /// Splits on dots and compares numerically, so 1.10.0 correctly beats 1.9.0
    /// where a string compare would not. Non numeric components sort as 0, and a
    /// shorter version is padded, so 1.2 and 1.2.0 are equal.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func parts(_ s: String) -> [Int] {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            .split(separator: ".")
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
}

struct UpdateCheck {
    /// The releases API rather than the HTML page: it answers with the tag alone,
    /// so nothing has to be scraped and a redesign upstream cannot break it.
    static let endpoint = URL(string:
        "https://api.github.com/repos/nicglazkov/pixel-audio-bridge/releases/latest")!

    static let releasesPage = URL(string:
        "https://github.com/nicglazkov/pixel-audio-bridge/releases/latest")!

    /// Once a day at most. A launch loop should not turn into a request loop.
    static let interval: TimeInterval = 24 * 60 * 60

    private struct Release: Decodable { let tag_name: String }

    /// Returns the newer version string, or nil for "nothing newer" and for every
    /// failure. A silent no is correct here: an update check that cannot reach
    /// the network is not a problem the user needs to hear about.
    static func latestVersion(timeout: TimeInterval = 10,
                              completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // Identifies the app and its version only. GitHub requires a User-Agent,
        // and this says no more than the request already implies.
        request.setValue("PixelAudioBridge/\(Bundle.appVersion)", forHTTPHeaderField: "User-Agent")

        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.httpShouldSetCookies = false

        URLSession(configuration: config).dataTask(with: request) { data, _, _ in
            guard let data,
                  let release = try? JSONDecoder().decode(Release.self, from: data)
            else { return completion(nil) }
            let tag = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            completion(Version.isNewer(tag, than: Bundle.appVersion) ? tag : nil)
        }.resume()
    }
}

extension Bundle {
    static var appVersion: String {
        (main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }
}
