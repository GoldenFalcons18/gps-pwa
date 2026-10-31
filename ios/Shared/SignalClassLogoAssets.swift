#if os(iOS) || os(watchOS)
import Foundation
import ImageIO

/// Bundled Wikimedia Commons sail emblems. Images are decoded once and remain available offline.
enum SignalClassLogoAssets {
    private static let imageData: [String: Data] = {
        var images: [String: Data] = [:]
        let resourceNames = [
            "signal-class-logos",
            "signal-class-logos-extra-1",
            "signal-class-logos-extra-2",
            "signal-class-logos-extra-3",
            "signal-class-logos-extra-4",
            "signal-class-logos-extra-5",
            "signal-class-logos-extra-6",
            "signal-class-logos-extra-7"
        ]
        for name in resourceNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
                  let json = try? Data(contentsOf: url),
                  let encoded = try? JSONSerialization.jsonObject(with: json) as? [String: String] else {
                continue
            }
            for (key, value) in encoded {
                if let data = Data(base64Encoded: value) {
                    images[key] = data
                }
            }
        }
        return images
    }()

    private static let imageCache = NSCache<NSString, CGImageBox>()

    static func image(for className: String) -> CGImage? {
        let key = assetKey(for: className)
        guard let data = imageData[key] else { return nil }
        if let cached = imageCache.object(forKey: key as NSString) { return cached.image }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        imageCache.setObject(CGImageBox(image), forKey: key as NSString)
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

private final class CGImageBox: NSObject {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}
#endif
