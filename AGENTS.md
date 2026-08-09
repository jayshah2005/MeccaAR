# Repository instructions for ChatGPT and Codex

## Feature boundaries are mandatory

Keep the three user flows physically and logically separate:

- `MeccaHunt/Features/Home/` owns only the main menu and home-screen UI.
- `MeccaHunt/Features/Placement/` owns placing and editing a Mecca through AR.
- `MeccaHunt/Features/Hunt/` owns discovery, hunt AR, targeting, claiming, and scoring UI.

Do not add placement or hunt implementation to `HomeView`, do not add home or
hunt implementation to `PlacementView`, and do not add home or placement
implementation to `HuntView`. A feature may not import or instantiate another
feature's private views, view models, or coordinators.

`MeccaHunt/App/` is composition only: app launch, navigation routes, and shared
dependency wiring. Route between feature entry views there rather than embedding
one feature screen inside another.

Put genuinely cross-feature business types and protocols in `Domain/`, shared
platform implementations in `Infrastructure/`, and reusable presentation code
in a future `Shared/UI/` folder only after at least two features need it. Do not
move feature-specific code into a shared folder merely to shorten a file.

When implementing a new capability:

1. Identify whether it belongs to Home, Placement, or Hunt before editing.
2. Create files inside that feature's directory for its views and feature-only logic.
3. Keep navigation in `AppState.Route` and `MeccaHuntApp`.
4. Check the changed-file list before finishing and correct any boundary violation.
5. Parse or build the Swift project after structural changes.

These boundaries take precedence over convenience and must remain intact during
refactors and generated-code changes.
