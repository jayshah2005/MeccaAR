# Delivery roadmap

Each phase ends with a go/no-go check. Avoid building progression systems until cross-device relocalization is proven.

## Phase 0 — foundation (this branch)

- [x] Preserve earlier prototype work on its existing branch.
- [x] Create a cloneable iOS project and folder boundaries.
- [x] Define product scope, data contracts, privacy constraints, and AR strategy.
- [x] Add the supplied licensed USDZ with attribution and a procedural fallback.
- [ ] Choose an original product/character name and obtain an original `.usdz` model.
- [ ] Decide the first controlled field-test venue.

Exit: the team agrees on MVP scope and can launch the setup shell in Xcode.

## Phase 1 — local placement spike

- [x] Camera-based AR screen with coaching and horizontal/vertical plane detection.
- [x] Tap-to-place using the supplied USDZ model.
- [x] Live color, size, and X/Y-axis rotation controls for the latest placement.
- [ ] Camera/location permission education and denial states.
- [x] Licensed USDZ loading, validation, bounds normalization, and fallback.
- [ ] Polished placement preview.
- Local anchor save/restore on the same phone only.
- Structured AR session state and OSLog diagnostics.

Exit: 9/10 same-device restores are within 15 cm in the pilot space.

## Phase 2 — cross-device localization spike

- Archive/share ARWorldMap for the controlled indoor venue.
- Add ARGeoAnchor path and availability gating for an outdoor test route.
- Relocalization coaching, timeout, and recovery UX.
- Measure success rate, median time, and positional error on at least three iPhones.

Exit: meet the relocalization targets in `PRODUCT_PLAN.md`. If not, evaluate a visual-positioning provider before backend/game work.

## Phase 3 — backend and map

- Supabase project, migrations, private storage, RLS, Sign in with Apple.
- Coarse PostGIS hunt-zone query and exact-payload unlock RPC.
- Map list/pins, proximity state, expiry cleanup.
- Staging environment and seed placements.

Exit: two accounts can publish and retrieve a private anchor without exposing exact coordinates publicly.

## Phase 4 — hunt and score

- Render a restored placement, hit test it, and submit an idempotent claim.
- Server-authoritative score, profile history, haptics and simple feedback.
- Self-claim and duplicate-claim tests.

Exit: a complete two-phone loop works repeatedly in the pilot area.

## Phase 5 — safety and private beta

- Report/block/remove, restricted zones, rate limits, moderation console.
- Accessibility, privacy manifest/policy, retention job, account deletion.
- Field telemetry with consent, crash reporting, TestFlight checklist.

Exit: controlled beta approval. Global rollout remains a separate decision.
