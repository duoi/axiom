import AppKit
import CoreGraphics
import Foundation

enum ScreenImage {
    static let budget = 400_000

    static func jpeg(from image: CGImage) -> Data {
        choose { edge, quality in
            encode(image, maxEdge: edge, quality: quality)
        }
    }

    static func choose(encode: (_ edge: Int, _ quality: CGFloat) -> Data) -> Data {
        let first = encode(1536, 0.60)
        if first.count <= budget {
            return first
        }
        let second = encode(1280, 0.50)
        if second.count <= budget {
            return second
        }
        return encode(1280, 0.40)
    }

    private static func encode(_ image: CGImage, maxEdge: Int, quality: CGFloat) -> Data {
        let scaled = scaled(image, maxEdge: maxEdge)
        let rep = NSBitmapImageRep(cgImage: scaled)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) ?? Data()
    }

    private static func scaled(_ image: CGImage, maxEdge: Int) -> CGImage {
        let longEdge = max(image.width, image.height)
        let scale = longEdge > maxEdge ? CGFloat(maxEdge) / CGFloat(longEdge) : 1
        let width = max(1, Int((CGFloat(image.width) * scale).rounded(.down)))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded(.down)))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else {
            return image
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}
