import AppKit
import Foundation

enum AttachmentError: Equatable, Error {
    case tooMany
    case tooLarge
    case binary
    case unsupported
    case unreadableImage
}

enum AttachmentPolicy {
    static let maxFiles = 4
    static let maxBytes = 4 * 1024 * 1024

    private static let textExtensions: Set<String> = [
        "txt", "md", "json", "swift", "csv", "html", "css", "js", "ts", "py", "xml", "yaml", "yml", "log", "sh"
    ]
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff"
    ]

    static func prepare(data: Data, filename: String, existingCount: Int) -> Result<Chip, AttachmentError> {
        if existingCount >= maxFiles {
            return .failure(.tooMany)
        }
        if data.count > maxBytes {
            return .failure(.tooLarge)
        }
        let ext = (filename as NSString).pathExtension.lowercased()
        if textExtensions.contains(ext) {
            if data.contains(0) {
                return .failure(.binary)
            }
            guard let text = String(data: data, encoding: .utf8) else {
                return .failure(.binary)
            }
            return .success(Chip(id: UUID(), name: filename, payload: .text(text)))
        }
        if imageExtensions.contains(ext) {
            guard let jpeg = jpegData(from: data) else {
                return .failure(.unreadableImage)
            }
            if jpeg.count > maxBytes {
                return .failure(.tooLarge)
            }
            return .success(Chip(id: UUID(), name: filename, payload: .jpeg(jpeg)))
        }
        return .failure(.unsupported)
    }

    private static func jpegData(from data: Data) -> Data? {
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
