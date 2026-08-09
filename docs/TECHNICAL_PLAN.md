# Technical plan

## Recommended stack

| Layer | Choice | Reason |
| --- | --- | --- |
| Client | SwiftUI, ARKit, RealityKit, MapKit, Core Location | Native iPhone AR, rendering, and maps |
| Authentication | Sign in with Apple through Supabase Auth | Stable player identity without custom passwords |
| Database/API | Supabase Postgres with PostGIS and database RPCs | Indexed nearby queries and server-side claim rules |
| Anchor storage | Private Supabase Storage bucket | ARWorldMap payloads must not be public objects |
| Observability | OSLog first; crash/analytics provider after consent review | Keeps setup dependency-light |

CloudKit is attractive for an Apple-only app, but its documented location index resolution is no finer than 10 km. That is a poor match for a street/room discovery feed. PostGIS is the recommended source of truth for metre-scale radius queries.

No third-party SDK is added in the foundation branch. Add `supabase-swift` only when the backend project, keys, and row-level security policies exist.

## Two-stage localization

The app must not convert GPS deltas directly into AR coordinates. Consumer GPS can drift by metres, particularly indoors.

1. **Geographic discovery:** PostGIS answers “which hunt zones are near this phone?”
2. **Spatial relocalization:** ARKit answers “where is this exact chair, wall, or patch of ground in the camera session?”

### Indoor / mapped-space path

- Hider scans until `worldMappingStatus` is `.mapped`.
- App adds a named `ARAnchor`, captures `ARWorldMap`, archives it with secure coding, encrypts/uploads it, and records the storage ID.
- Hunter downloads the map only after entering the unlock radius and runs it as `initialWorldMap`.
- UI coaches the hunter to scan until relocalization succeeds; the restored named anchor renders the model.
- If relocalization times out, return to map guidance instead of rendering at a guessed GPS offset.

### Outdoor path

- Check `ARGeoTrackingConfiguration.isSupported` and runtime geographic availability.
- Where available, store latitude/longitude/altitude and restore an `ARGeoAnchor`.
- Geotracking is outdoor-only, requires supported hardware, network access, and Apple localization imagery.
- Where unavailable, mark that placement incompatible for exact AR in MVP; do not pretend raw GPS is precise.

See [ADR 0001](adr/0001-cross-device-localization.md).

## Proposed module boundaries

```text
MeccaHunt
├── App                  app lifecycle, navigation, dependency assembly
├── Domain
│   ├── Models           placement, coordinate, claim
│   └── Services         repository contracts
├── Features
│   ├── Home
│   ├── Map              discovery zones and proximity state
│   ├── Placement        scan, raycast, orient, publish
│   ├── Hunt             relocalize, render, hit test
│   ├── Profile          score and identity
│   └── Safety           reports and placement guardrails
├── Infrastructure
│   ├── Backend          Supabase adapters
│   ├── Location         authorization and accuracy policy
│   └── Spatial          ARWorldMap / ARGeoAnchor adapters
└── Resources            assets and original USDZ models
```

Feature folders should be added only when their milestone begins; empty architecture folders create noise.

## Proposed backend data

### `profiles`

- `id uuid` matching authenticated user
- `display_name`, `score`, `created_at`, moderation state

### `placements`

- `id`, `owner_id`, `location geography(Point, 4326)`, `altitude_m`
- `anchor_method` (`world_map` or `geo_anchor`)
- private `anchor_object_path`, model/version, state
- `created_at`, `expires_at`, report/removal metadata

### `hunt_claims`

- `id`, `placement_id`, `hunter_id`, `points`, `claimed_at`
- unique constraint on `(placement_id, hunter_id)`

### `reports`

- reporter, placement, reason, timestamp, moderation state

Clients should not directly select exact placement rows. Expose narrow RPCs:

- `nearby_hunt_zones(lat, lon, radius_m)` returns coarse coordinates and public metadata.
- `unlock_placement(id, lat, lon, accuracy_m)` returns exact anchor metadata only inside policy limits.
- `claim_placement(id, lat, lon, accuracy_m, nonce)` atomically checks eligibility and awards points.

Enable row-level security on every exposed table. Use a private storage bucket with short-lived signed downloads for anchor payloads.

## Claim and anti-cheat policy

- Server owns score totals; the app never submits awarded point values.
- Claim RPC is idempotent and protected by a unique database constraint.
- Reject self-claims, expired/removed placements, implausible distance, stale timestamps, and poor reported accuracy.
- Add rate limits and per-account placement limits for the pilot.
- GPS can be spoofed. Before a competitive/global leaderboard, add App Attest/DeviceCheck, replay-resistant nonces, behavioral checks, and manual moderation.
- A camera hit alone is client-reported and is not cryptographic proof. Treat the MVP score as casual, not valuable.

## Permissions

Request permissions only at the moment the related action begins:

- Camera: when entering placement or hunt AR.
- When-in-use location: when opening the map or publishing.
- No background location permission for MVP.
- No local-network/Bonjour permission unless a future nearby-session feature is explicitly chosen.

## Testing strategy

- Pure model and scoring-policy unit tests.
- Repository contract tests against a local/staging Supabase instance.
- AR session state-machine tests with recorded state transitions.
- Physical-device matrix: oldest supported iPhone, one LiDAR device, one non-LiDAR device.
- Repeatable field-test script with measured relocalization rate, time, and position error.
- Test permission denial, weak GPS, no network, expired payload, unsupported geotracking, and changed room lighting/furniture.

## Primary references

- [Apple: Saving and loading world data](https://developer.apple.com/documentation/arkit/saving-and-loading-world-data)
- [Apple: ARWorldMap](https://developer.apple.com/documentation/arkit/arworldmap)
- [Apple: Tracking geographic locations in AR](https://developer.apple.com/documentation/arkit/tracking-geographic-locations-in-ar)
- [Apple: ARGeoTrackingConfiguration](https://developer.apple.com/documentation/arkit/argeotrackingconfiguration)
- [Apple: CKQuery predicate rules](https://developer.apple.com/documentation/cloudkit/ckquery)
- [Supabase: PostGIS geo queries](https://supabase.com/docs/guides/database/extensions/postgis)
- [Supabase: Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase: Swift installation](https://supabase.com/docs/reference/swift/installing)
