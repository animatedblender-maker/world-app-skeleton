import UIKit

enum PhotorealGlobeTextures {
    private static var earthCache: UIImage?
    private static var cloudCache: UIImage?
    private static var starsCache: UIImage?

    static var earthDaymap: UIImage? {
        if let earthCache { return earthCache }
        earthCache = load("EarthDaymap", bundleName: "earth_daymap")
        return earthCache
    }

    static var earthClouds: UIImage? {
        if let cloudCache { return cloudCache }
        cloudCache = load("EarthClouds", bundleName: "earth_clouds")
        return cloudCache
    }

    static var stars: UIImage? {
        if let starsCache { return starsCache }
        starsCache = load("Stars", bundleName: "stars")
        return starsCache
    }

    private static func load(_ assetName: String, bundleName: String) -> UIImage? {
        if let asset = UIImage(named: assetName, in: Bundle.main, compatibleWith: nil) {
            return normalize(asset)
        }
        if let asset = UIImage(named: assetName) {
            return normalize(asset)
        }

        for ext in ["png", "jpg"] {
            if let path = Bundle.main.path(forResource: bundleName, ofType: ext),
               let fileImage = UIImage(contentsOfFile: path) {
                return normalize(fileImage)
            }

            for subdirectory in ["GlobeTextures", "Resources/GlobeTextures"] {
                if let path = Bundle.main.path(forResource: bundleName, ofType: ext, inDirectory: subdirectory),
                   let fileImage = UIImage(contentsOfFile: path) {
                    return normalize(fileImage)
                }
            }
        }

        for ext in ["png", "jpg"] {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                for url in urls where url.deletingPathExtension().lastPathComponent == bundleName {
                    if let fileImage = UIImage(contentsOfFile: url.path) {
                        return normalize(fileImage)
                    }
                }
            }
        }

        return nil
    }

    /// SceneKit is happiest with standard 8-bit sRGB bitmaps.
    private static func normalize(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return image }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let output = context.makeImage() else { return image }
        return UIImage(cgImage: output)
    }
}