import ARKit
import Foundation

/// Serializes an `ARWorldMap` to compact bytes (and back) so it can be stored in
/// the backend and shared between devices for centimeter-accurate relocalization.
///
/// The map is keyed-archived, then zlib-compressed to keep the payload small
/// enough to move over Neon's SQL-over-HTTP endpoint. Callers base64-encode the
/// compressed bytes for the text column.
enum ARWorldMapArchiver {
    enum ArchiveError: LocalizedError {
        case compressionFailed
        case decompressionFailed
        case notAWorldMap

        var errorDescription: String? {
            switch self {
            case .compressionFailed: return "Couldn't compress the AR map."
            case .decompressionFailed: return "Couldn't read the stored AR map."
            case .notAWorldMap: return "Stored AR data was not a valid world map."
            }
        }
    }

    /// Archive + zlib-compress a world map into transportable bytes.
    static func encode(_ map: ARWorldMap) throws -> Data {
        let archived = try NSKeyedArchiver.archivedData(
            withRootObject: map,
            requiringSecureCoding: true
        )
        guard let compressed = try? (archived as NSData).compressed(using: .zlib) else {
            throw ArchiveError.compressionFailed
        }
        return compressed as Data
    }

    /// Inverse of `encode`: decompress + unarchive back into an `ARWorldMap`.
    static func decode(_ data: Data) throws -> ARWorldMap {
        guard let decompressed = try? (data as NSData).decompressed(using: .zlib) else {
            throw ArchiveError.decompressionFailed
        }
        guard
            let map = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: ARWorldMap.self,
                from: decompressed as Data
            )
        else {
            throw ArchiveError.notAWorldMap
        }
        return map
    }
}
