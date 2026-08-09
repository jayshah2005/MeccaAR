import ARKit
import Foundation

/// Serializes an `ARWorldMap` to compact bytes (and back) so it can be stored in
/// the backend and shared between devices for centimeter-accurate relocalization.
///
/// The map is keyed-archived, then zlib-compressed to keep the payload small
/// enough to move over Neon's SQL-over-HTTP endpoint. Callers base64-encode the
/// compressed bytes for the text column.
enum ARWorldMapArchiver {
    /// Soft floor on how dense a captured map must be before we accept it.
    /// Sparse maps often only relocalize from the exact placement viewpoint.
    static let minimumFeaturePoints = 120

    enum ArchiveError: LocalizedError {
        case compressionFailed
        case decompressionFailed
        case notAWorldMap
        case tooSparse(featurePoints: Int)

        var errorDescription: String? {
            switch self {
            case .compressionFailed: return "Couldn't compress the AR map."
            case .decompressionFailed: return "Couldn't read the stored AR map."
            case .notAWorldMap: return "Stored AR data was not a valid world map."
            case .tooSparse(let count):
                return "AR map is too thin (\(count) features). Keep scanning the area from more angles, then try again."
            }
        }
    }

    /// Returns the number of raw feature points in the map, or 0 if unknown.
    static func featurePointCount(of map: ARWorldMap) -> Int {
        map.rawFeaturePoints.points.count
    }

    /// True when the map has enough geometry for reliable multi-angle relocalization.
    static func isDenseEnough(_ map: ARWorldMap) -> Bool {
        featurePointCount(of: map) >= minimumFeaturePoints
    }

    /// True when the named Mecca placement anchor was captured into the map.
    static func containsMeccaAnchor(_ map: ARWorldMap) -> Bool {
        map.anchors.contains { $0.name == "mecca" }
    }

    /// Archive + zlib-compress a world map into transportable bytes.
    /// Rejects maps that are too sparse to find later from a different angle.
    static func encode(
        _ map: ARWorldMap,
        minimumFeaturePoints: Int = minimumFeaturePoints
    ) throws -> Data {
        let points = featurePointCount(of: map)
        guard points >= minimumFeaturePoints else {
            throw ArchiveError.tooSparse(featurePoints: points)
        }

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
