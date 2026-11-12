#if os(iOS) || os(watchOS)
import Foundation
import ImageIO

/// Bundled Wikimedia Commons sail emblems. Images are decoded once and remain available offline.
enum SignalClassLogoAssets {
    static let availableClassNames: [String] = {
        let resources = ["signal-class-logos"] + (1...7).map { "signal-class-logos-extra-\($0)" }
        var names = Set<String>()
        for resource in resources {
            guard let url = resourceURL(for: resource),
                  let data = try? Data(contentsOf: url),
                  let catalog = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { continue }
            names.formUnion(catalog.keys)
        }
        names.insert("420")
        names.insert("Optimist")
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }()

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
            guard let url = resourceURL(for: name),
                  let json = try? Data(contentsOf: url),
                  let encoded = try? JSONSerialization.jsonObject(with: json) as? [String: String] else {
                continue
            }
            for (key, value) in encoded {
                if let data = Data(base64Encoded: value),
                   CGImageSourceCreateWithData(data as CFData, nil) != nil {
                    images[normalizedKey(key)] = data
                }
            }
        }
        return images
    }()

    private static let imageCache = NSCache<NSString, CGImageBox>()
    private static let internationalImages: [String: Data] = {
        guard let url = resourceURL(for: "signal-international-flags"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return catalog.reduce(into: [:]) { result, item in
            if let bytes = Data(base64Encoded: item.value),
               CGImageSourceCreateWithData(bytes as CFData, nil) != nil {
                result[normalizedKey(item.key)] = bytes
            }
        }
    }()

    static func internationalImage(for name: String) -> CGImage? {
        let normalized = normalizedKey(name)
        guard let data = internationalImages[normalized],
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func image(for className: String) -> CGImage? {
        let key = assetKey(for: className)
        let normalized = normalizedKey(key)
        if let cached = imageCache.object(forKey: normalized as NSString) { return cached.image }

        // Generated image files are bundled separately so every class mark is
        // loaded as a normal PNG instead of decoded from the large JSON catalog.
        if let url = Bundle.main.url(
            forResource: "class-logo-\(normalized)",
            withExtension: "png"
        ), let data = try? Data(contentsOf: url),
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            imageCache.setObject(CGImageBox(image), forKey: normalized as NSString)
            return image
        }

        if normalized == "420",
           let url = Bundle.main.url(forResource: "signal-class-420", withExtension: "png"),
           let data = try? Data(contentsOf: url),
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            imageCache.setObject(CGImageBox(image), forKey: normalized as NSString)
            return image
        }

        guard let data = imageData[normalized],
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        imageCache.setObject(CGImageBox(image), forKey: normalized as NSString)
        return image
    }

    private static func resourceURL(for name: String) -> URL? {
        let fileName = "\(name).json"
        var bundles = Bundle.allBundles + Bundle.allFrameworks
        if !bundles.contains(where: { $0.bundleURL == Bundle.main.bundleURL }) {
            bundles.insert(Bundle.main, at: 0)
        }

        for bundle in bundles {
            if let url = bundle.url(forResource: name, withExtension: "json")
                ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Shared") {
                return url
            }
            guard let root = bundle.resourceURL else { continue }
            if let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                for case let url as URL in enumerator where url.lastPathComponent == fileName {
                    return url
                }
            }
        }
        return nil
    }

    private static func normalizedKey(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func assetKey(for className: String) -> String {
        let value = className
            .replacingOccurrences(of: "class-", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

