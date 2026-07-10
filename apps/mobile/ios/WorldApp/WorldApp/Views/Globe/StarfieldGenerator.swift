import UIKit

enum StarfieldGenerator {
    private static var cachedImage: UIImage?

    static func image(size: CGSize = CGSize(width: 4096, height: 4096)) -> UIImage {
        if let cachedImage { return cachedImage }

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(origin: .zero, size: size)

            let colors = [
                UIColor(red: 0.01, green: 0.02, blue: 0.06, alpha: 1).cgColor,
                UIColor(red: 0.02, green: 0.04, blue: 0.10, alpha: 1).cgColor,
                UIColor(red: 0.00, green: 0.01, blue: 0.03, alpha: 1).cgColor,
            ] as CFArray
            let locations: [CGFloat] = [0, 0.55, 1]
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: locations
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: size.width * 0.2, y: 0),
                    end: CGPoint(x: size.width * 0.8, y: size.height),
                    options: []
                )
            }

            cg.setFillColor(UIColor(white: 1, alpha: 0.9).cgColor)
            for _ in 0..<14_000 {
                let x = CGFloat.random(in: 0...size.width)
                let y = CGFloat.random(in: 0...size.height)
                let brightness = CGFloat.random(in: 0.15...1.0)
                let radius = CGFloat.random(in: 0.35...1.1)
                cg.setFillColor(UIColor(white: 1, alpha: brightness).cgColor)
                cg.fillEllipse(in: CGRect(x: x, y: y, width: radius, height: radius))
            }

            cg.setBlendMode(.plusLighter)
            for _ in 0..<180 {
                let x = CGFloat.random(in: 0...size.width)
                let y = CGFloat.random(in: 0...size.height)
                let radius = CGFloat.random(in: 1.2...2.8)
                let alpha = CGFloat.random(in: 0.35...0.85)
                cg.setFillColor(UIColor(red: 0.82, green: 0.90, blue: 1.0, alpha: alpha).cgColor)
                cg.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            }
            cg.setBlendMode(.normal)

            cg.setFillColor(UIColor(white: 1, alpha: 0.04).cgColor)
            cg.fillEllipse(in: rect.insetBy(dx: -size.width * 0.1, dy: -size.height * 0.1))
        }

        cachedImage = image
        return image
    }
}