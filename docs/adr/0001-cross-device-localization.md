# ADR 0001: Separate discovery location from AR localization

- Status: accepted for prototype validation
- Date: 2026-08-08

## Context

A hider can place a character on a specific real-world surface. A hunter on another phone must see it at that same surface. A stored latitude, longitude, altitude, and compass heading do not provide reliable room-scale alignment, especially indoors.

The experience must eventually cover rooms and outdoor areas, but ARKit does not offer one universal anchor that precisely covers both.

## Decision

Use a two-stage system:

1. PostGIS coordinates discover a coarse nearby hunt zone.
2. A method-specific spatial payload restores the precise AR anchor:
   - `ARWorldMap` for a previously scanned indoor or controlled space;
   - `ARGeoAnchor` outdoors only when device and geographic availability checks pass.

Never render a shared placement by translating a raw GPS delta into the current AR world coordinate system.

## Consequences

- The data model carries an `anchorMethod` and versioned payload reference.
- Indoor hunters must visually relocalize the mapped space.
- World maps are sensitive spatial data and require private storage, consent, short retention, and deletion.
- Some outdoor placements are unavailable on unsupported devices or locations.
- The team must field-test both paths before investing in a large backend or scoring system.
- If reliability targets fail, a visual-positioning service becomes a deliberate product/cost decision rather than a late rewrite.

