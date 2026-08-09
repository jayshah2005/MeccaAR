import CoreLocation
import Foundation

/// A group of Meccas that sit close enough together (e.g. the same room) to be
/// drawn as a single point on the map.
struct MeccaCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let meccas: [Mecca]

    var count: Int { meccas.count }
    var isGroup: Bool { meccas.count > 1 }
    var representative: Mecca { meccas[0] }
}

enum MeccaClustering {
    /// Greedy distance-based clustering: each Mecca joins the first existing
    /// cluster within `withinMeters`, otherwise it starts a new one.
    static func cluster(_ meccas: [Mecca], withinMeters: Double) -> [MeccaCluster] {
        var buckets: [[Mecca]] = []

        for mecca in meccas {
            let coordinate = CLLocationCoordinate2D(
                latitude: mecca.latitude,
                longitude: mecca.longitude
            )

            if let index = buckets.firstIndex(where: { bucket in
                guard let first = bucket.first else { return false }
                let anchor = CLLocationCoordinate2D(
                    latitude: first.latitude,
                    longitude: first.longitude
                )
                return GeoMath.distanceMeters(from: anchor, to: coordinate) <= withinMeters
            }) {
                buckets[index].append(mecca)
            } else {
                buckets.append([mecca])
            }
        }

        return buckets.map { bucket in
            let latitude = bucket.map(\.latitude).reduce(0, +) / Double(bucket.count)
            let longitude = bucket.map(\.longitude).reduce(0, +) / Double(bucket.count)
            let id = bucket.map { $0.id.uuidString }.sorted().joined(separator: "-")
            return MeccaCluster(
                id: id,
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                meccas: bucket
            )
        }
    }
}
