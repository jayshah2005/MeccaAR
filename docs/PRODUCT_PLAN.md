# Product plan

## Product promise

Turn familiar places into an asynchronous AR hide-and-hunt game: hide a small original character in the real world, leave a clue on the map, and reward the next player who finds it through their camera.

The creative inspiration is the paint-and-camouflage tension of *MECCHA CHAMELEON*. Mecca Hunt changes the format to location-based, asynchronous play and must use original art and branding.

## Core loop

### Hider

1. Sign in and choose **Hide**.
2. Scan enough of the space for reliable tracking.
3. Place and orient the character on a detected surface.
4. Optionally choose a simple color/camouflage treatment.
5. Confirm a map clue, expiry, and public-space safety statement.
6. Publish the coarse discovery location and private spatial anchor.

### Hunter

1. Open the map and choose a nearby hunt zone.
2. Walk into the unlock radius.
3. Scan the environment until the saved anchor relocalizes.
4. Find and tap the character.
5. Receive points once the server validates a unique claim.

## MVP rules

- One character type and one simple placement interaction.
- One public hunt feed within a small pilot area.
- A placement expires after 24 hours by default.
- A hunter earns 100 points for the first valid claim on a placement.
- A player cannot claim their own placement or claim the same placement twice.
- Exact coordinates and anchor payloads stay private until the player is close.
- The first pilot targets controlled, well-mapped rooms and a small set of tested outdoor areas.

## Map behavior

- The public map shows a coarse hunt zone, not a pin on a chair, apartment, or exact doorway.
- Selecting a zone shows distance, expiry, difficulty, and whether the device/location supports the required anchor method.
- The AR payload unlocks only inside a configurable radius, initially 50 metres.
- A hunter must still relocalize visually; the map is discovery, not the final positioning system.

## MVP success criteria

- At least 8 of 10 hunters in a pilot space can relocalize a placement without help.
- Median time from entering the unlock radius to seeing the character is under 45 seconds.
- A placement appears within 30 cm of its intended indoor position after relocalization.
- Duplicate claims never award points twice.
- No exact private-place coordinate is exposed by the public map/API.
- A two-hour field test completes without a crash or unrecoverable AR session.

## Explicit non-goals for MVP

- Real-time team matches, chat, trading, inventory, or paid items.
- User-generated 3D models.
- Weapon simulation; “kill” is a simple tap/find interaction for the first version.
- Guaranteed precise placement everywhere in the world.
- Background location tracking.
- A global leaderboard before anti-cheat and moderation exist.

## Safety, privacy, and trust

- Do not permit placements while driving or on roads, railways, restricted land, schools, hospitals, or obviously private residences.
- Require a hider confirmation that they have permission to place content in the space.
- Provide report, block, removal, expiry, and rate-limit systems before public testing.
- Keep exact coordinates, spatial maps, and any guidance imagery private and short-lived.
- Never store a continuous location trail; retain only the placement coordinate and short-lived claim evidence.
- Add age gating and a legal/privacy review before TestFlight leaves a controlled group.

## Open product decisions

1. Is the first field test one known indoor venue, outdoor-only, or both?
2. Does the first hunter remove a Mecca, or can every hunter claim it once until expiry?
3. Should hiders receive points when their Mecca survives or gets discovered?
4. What original product and character name replaces the working “Mecca” name?

