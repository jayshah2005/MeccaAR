# Mecca Hunt

Mecca Hunt is the working title for an iPhone AR hide-and-hunt game. One player places a small character in a real location; other players discover the area on a map, relocalize the character through the camera, and score for finding it.

This branch contains the foundation plus the first local AR capability:

- a cloneable SwiftUI iPhone project;
- a camera placement screen with horizontal and vertical plane detection;
- tap-to-place for a temporary procedural white Mecca;
- live color, size, 360-degree rotation, and standing/sleeping pose controls;
- domain contracts for placement, discovery, and claiming;
- product, technical, privacy, and delivery plans.

Placement currently exists only in the active AR session. Controls edit the most recently placed Mecca and set the configuration for the next placement. Nothing is saved, published, placed on the map, or visible to another phone yet.

The earlier working prototype remains preserved on the `codex/mecca-hunt` branch.

## Open the project

1. Open `MeccaHunt.xcodeproj` in Xcode 16 or newer.
2. Select the `MeccaHunt` target.
3. Set your development team and replace the example bundle identifier.
4. Run on iOS 17+.

The home screen works in Simulator. Camera placement requires a physical ARKit-capable iPhone; hunting is not implemented yet.

## Read first

- [Product plan](docs/PRODUCT_PLAN.md)
- [Technical plan](docs/TECHNICAL_PLAN.md)
- [Roadmap](docs/ROADMAP.md)
- [Cross-device AR decision](docs/adr/0001-cross-device-localization.md)

## Working-name note

The inspiration is *MECCHA CHAMELEON*, but this project should use an original name, character, model, animation, audio, and interface before public distribution. The supplied white figure is visual reference only; the app still needs an original, licensed 3D `.usdz` asset.
