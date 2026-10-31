#if os(iOS)
import Foundation
import UIKit

/// Bundled Wikimedia Commons sail emblems. Images are decoded once and remain available offline.
enum SignalClassLogoAssets {
    private static let imageData: [String: Data] = {
        guard let url = Bundle.main.url(forResource: "signal-class-logos", withExtension: "json"),
              let json = try? Data(contentsOf: url),
              let encoded = try? JSONSerialization.jsonObject(with: json) as? [String: String] else {
            return [:]
        }
        return encoded.compactMapValues { Data(base64Encoded: $0) }
    }()

    private static let imageCache = NSCache<NSString, UIImage>()

    static func image(for className: String) -> UIImage? {
        let key = assetKey(for: className)
        guard let data = imageData[key] else { return nil }
        if let cached = imageCache.object(forKey: key as NSString) { return cached }
        guard let image = UIImage(data: data) else { return nil }
        imageCache.setObject(image, forKey: key as NSString)
        return image
    }

    private static func assetKey(for className: String) -> String {
        let value = className.replacingOccurrences(of: "class-", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch value.lowercased() {
        case "a-cat": return "A-Cat"
        case "29er": return "29er"
        case "420": return "420"
        case "470": return "470"
        case "49er": return "49er"
        case "finn": return "Finn"
        case "optimist": return "Optimist"
        case "tornado": return "Tornado"
        case "star": return "Star_red"
        case "laser": return "Sailing_laser"
        case "snipe": return "Sailing_snipe"
        default: return value
        }
    }
}
#endif
