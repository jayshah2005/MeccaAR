import ImageIO
import UIKit

/// Packs the owner's face-photo UV into JPEG EXIF so hunters can restore the
/// same placement without a schema migration. Trailing metadata survives the
/// base64 round-trip through Neon.
enum MeccaFacePhotoCodec {
    private static let marker = "meccahunt-face-placement:"

    static func encode(
        jpegData: Data,
        placement: MeccaPhotoPlacement
    ) -> Data {
        let clamped = placement.clamped
        guard
            let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
            let type = CGImageSourceGetType(source),
            let destinationData = CFDataCreateMutable(nil, 0),
            let destination = CGImageDestinationCreateWithData(
                destinationData,
                type,
                1,
                nil
            )
        else {
            return jpegData
        }

        var properties =
            (CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]) ?? [:]
        var exif =
            (properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
            ?? [:]
        exif[kCGImagePropertyExifUserComment] =
            "\(marker)\(clamped.horizontal),\(clamped.vertical)"
        properties[kCGImagePropertyExifDictionary] = exif

        CGImageDestinationAddImageFromSource(
            destination,
            source,
            0,
            properties as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return jpegData }
        return destinationData as Data
    }

    static func decode(_ data: Data) -> (image: UIImage, placement: MeccaPhotoPlacement)? {
        guard let image = UIImage(data: data) else { return nil }
        return (image, readPlacement(from: data) ?? .faceDefault)
    }

    static func readPlacement(from data: Data) -> MeccaPhotoPlacement? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
            let exif = properties[kCGImagePropertyExifDictionary]
                as? [CFString: Any],
            let comment = exif[kCGImagePropertyExifUserComment] as? String,
            comment.hasPrefix(marker)
        else {
            return nil
        }

        let payload = comment.dropFirst(marker.count)
        let parts = payload.split(separator: ",")
        guard
            parts.count == 2,
            let horizontal = Float(parts[0]),
            let vertical = Float(parts[1])
        else {
            return nil
        }

        return MeccaPhotoPlacement(
            horizontal: horizontal,
            vertical: vertical
        ).clamped
    }
}
