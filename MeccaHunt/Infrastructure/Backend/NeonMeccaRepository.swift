import Foundation

struct NeonMeccaRepository: MeccaRepository {
    let client: NeonClient

    func allMeccas(hunterID: UUID) async throws -> [Mecca] {
        let rows = try await client.execute(
            """
            select
                m.id as id,
                m.owner_id as owner_id,
                u.username as owner_username,
                m.name as name,
                m.latitude as latitude,
                m.longitude as longitude,
                m.altitude as altitude,
                m.size_mm as size_mm,
                m.x_rotation as x_rotation,
                m.y_rotation as y_rotation,
                m.tint_red as tint_red,
                m.tint_green as tint_green,
                m.tint_blue as tint_blue,
                coalesce(m.placement_mode, 'world_map') as placement_mode,
                extract(epoch from m.created_at) as created_at_epoch,
                count(c.id)::int as claim_count,
                coalesce(bool_or(c.hunter_id = $1::uuid), false)::int as claimed_by_me,
                (exists (select 1 from mecca_world_maps w where w.mecca_id = m.id))::int as has_world_map,
                (exists (select 1 from mecca_face_photos f where f.mecca_id = m.id))::int as has_face_photo
            from meccas m
            join users u on u.id = m.owner_id
            left join hunt_claims c on c.mecca_id = m.id
            where m.state = 'active'
              and m.created_at >= now() - interval '30 days'
            group by m.id, u.username
            order by m.created_at desc;
            """,
            [.uuid(hunterID)]
        )

        return rows.compactMap(Self.mecca(from:))
    }

    func createMecca(
        ownerID: UUID,
        name: String,
        coordinate: GeoCoordinate,
        appearance: MeccaAppearance,
        placementMode: MeccaPlacementMode,
        notBefore: Date
    ) async throws -> Mecca {
        // The insert only fires when no Mecca by this owner exists since
        // `notBefore`, so an empty result means the daily limit was hit.
        let rows = try await client.execute(
            """
            with inserted as (
                insert into meccas (
                    owner_id, name, latitude, longitude, altitude,
                    size_mm, x_rotation, y_rotation, tint_red, tint_green, tint_blue,
                    placement_mode
                )
                select
                    $1::uuid, $2, $3::double precision, $4::double precision, $5::double precision,
                    $7::double precision, $8::double precision, $9::double precision,
                    $10::double precision, $11::double precision, $12::double precision,
                    $13
                where not exists (
                    select 1 from meccas
                    where owner_id = $1::uuid and created_at >= $6::timestamptz
                )
                returning id, owner_id, name, latitude, longitude, altitude,
                    size_mm, x_rotation, y_rotation, tint_red, tint_green, tint_blue,
                    placement_mode, created_at
            )
            select
                i.id as id,
                i.owner_id as owner_id,
                u.username as owner_username,
                i.name as name,
                i.latitude as latitude,
                i.longitude as longitude,
                i.altitude as altitude,
                i.size_mm as size_mm,
                i.x_rotation as x_rotation,
                i.y_rotation as y_rotation,
                i.tint_red as tint_red,
                i.tint_green as tint_green,
                i.tint_blue as tint_blue,
                coalesce(i.placement_mode, 'world_map') as placement_mode,
                extract(epoch from i.created_at) as created_at_epoch,
                0 as claim_count,
                0 as claimed_by_me,
                0 as has_world_map,
                0 as has_face_photo
            from inserted i
            join users u on u.id = i.owner_id;
            """,
            [
                .uuid(ownerID),
                .text(name),
                .double(coordinate.latitude),
                .double(coordinate.longitude),
                .optionalDouble(coordinate.altitude),
                .timestamp(notBefore),
                .double(appearance.sizeMillimeters),
                .double(appearance.xRotationDegrees),
                .double(appearance.yRotationDegrees),
                .double(appearance.red),
                .double(appearance.green),
                .double(appearance.blue),
                .text(placementMode.rawValue)
            ]
        )

        guard let mecca = rows.first.flatMap(Self.mecca(from:)) else {
            throw MeccaRepositoryError.dailyLimitReached
        }
        return mecca
    }

    func createMappedMecca(
        ownerID: UUID,
        name: String,
        coordinate: GeoCoordinate,
        appearance: MeccaAppearance,
        notBefore: Date,
        worldMapData: Data
    ) async throws -> Mecca {
        let rows = try await client.execute(
            """
            with inserted as (
                insert into meccas (
                    owner_id, name, latitude, longitude, altitude,
                    size_mm, x_rotation, y_rotation, tint_red, tint_green, tint_blue,
                    placement_mode
                )
                select
                    $1::uuid, $2, $3::double precision, $4::double precision, $5::double precision,
                    $7::double precision, $8::double precision, $9::double precision,
                    $10::double precision, $11::double precision, $12::double precision,
                    'world_map'
                where not exists (
                    select 1 from meccas
                    where owner_id = $1::uuid and created_at >= $6::timestamptz
                )
                returning id, owner_id, name, latitude, longitude, altitude,
                    size_mm, x_rotation, y_rotation, tint_red, tint_green, tint_blue,
                    placement_mode, created_at
            ),
            mapped as (
                insert into mecca_world_maps (mecca_id, data)
                select id, $13 from inserted
                returning mecca_id
            )
            select
                i.id as id,
                i.owner_id as owner_id,
                u.username as owner_username,
                i.name as name,
                i.latitude as latitude,
                i.longitude as longitude,
                i.altitude as altitude,
                i.size_mm as size_mm,
                i.x_rotation as x_rotation,
                i.y_rotation as y_rotation,
                i.tint_red as tint_red,
                i.tint_green as tint_green,
                i.tint_blue as tint_blue,
                coalesce(i.placement_mode, 'world_map') as placement_mode,
                extract(epoch from i.created_at) as created_at_epoch,
                0 as claim_count,
                0 as claimed_by_me,
                1 as has_world_map,
                0 as has_face_photo
            from inserted i
            join mapped w on w.mecca_id = i.id
            join users u on u.id = i.owner_id;
            """,
            [
                .uuid(ownerID),
                .text(name),
                .double(coordinate.latitude),
                .double(coordinate.longitude),
                .optionalDouble(coordinate.altitude),
                .timestamp(notBefore),
                .double(appearance.sizeMillimeters),
                .double(appearance.xRotationDegrees),
                .double(appearance.yRotationDegrees),
                .double(appearance.red),
                .double(appearance.green),
                .double(appearance.blue),
                .text(worldMapData.base64EncodedString())
            ]
        )

        guard let mecca = rows.first.flatMap(Self.mecca(from:)) else {
            throw MeccaRepositoryError.dailyLimitReached
        }
        return mecca
    }

    func lastPlacement(ownerID: UUID) async throws -> Date? {
        let rows = try await client.execute(
            """
            select extract(epoch from max(created_at)) as last_epoch
            from meccas
            where owner_id = $1::uuid;
            """,
            [.uuid(ownerID)]
        )
        return rows.first?.date(epochColumn: "last_epoch")
    }

    func claim(
        meccaID: UUID,
        hunterID: UUID
    ) async throws -> HuntClaim {
        // `target` only matches an active, non-expired Mecca owned by someone
        // else, so an empty result means it's your own, already found, expired,
        // or missing. The awarded points are the Mecca's current age-based value.
        // The Mecca is flagged `claimed` so it disappears from everyone's map,
        // while the claim row is kept for the leaderboard.
        let rows = try await client.execute(
            """
            with target as (
                select id, created_at from meccas
                where id = $1::uuid and owner_id <> $2::uuid and state = 'active'
                  and created_at >= now() - interval '30 days'
            ),
            scored as (
                select id,
                    case
                        when now() - created_at >= interval '30 days' then 500
                        when now() - created_at >= interval '20 days' then 300
                        when now() - created_at >= interval '10 days' then 200
                        else 100
                    end as points
                from target
            ),
            ins as (
                insert into hunt_claims (mecca_id, hunter_id, awarded_points)
                select id, $2::uuid, points from scored
                on conflict (mecca_id, hunter_id) do update
                    set claimed_at = now(), awarded_points = excluded.awarded_points
                returning mecca_id, hunter_id,
                    extract(epoch from claimed_at) as claimed_at_epoch, awarded_points
            ),
            upd as (
                update meccas set state = 'claimed'
                where id in (select id from target)
                returning id
            )
            select mecca_id, hunter_id, claimed_at_epoch, awarded_points from ins;
            """,
            [.uuid(meccaID), .uuid(hunterID)]
        )

        guard
            let row = rows.first,
            let meccaID = row.uuid("mecca_id"),
            let hunterID = row.uuid("hunter_id"),
            let claimedAt = row.date(epochColumn: "claimed_at_epoch")
        else {
            throw MeccaRepositoryError.unavailable
        }

        return HuntClaim(
            meccaID: meccaID,
            hunterID: hunterID,
            claimedAt: claimedAt,
            awardedPoints: row.int("awarded_points") ?? 0
        )
    }

    func hunterLeaderboard(period: LeaderboardPeriod) async throws -> [LeaderboardEntry] {
        // `period.sqlInterval` is a fixed, enum-controlled literal (never user
        // input), so interpolating it here is safe.
        let rows = try await client.execute(
            """
            select
                u.id as id,
                u.username as username,
                sum(c.awarded_points)::int as points,
                count(c.id)::int as finds
            from hunt_claims c
            join users u on u.id = c.hunter_id
            where c.claimed_at >= now() - interval '\(period.sqlInterval)'
            group by u.id, u.username
            order by points desc, u.username asc;
            """
        )

        return rows.compactMap { row in
            guard
                let id = row.uuid("id"),
                let username = row.string("username")
            else { return nil }
            return LeaderboardEntry(
                id: id,
                username: username,
                points: row.int("points") ?? 0,
                finds: row.int("finds") ?? 0
            )
        }
    }

    func overallLeaderboard() async throws -> [LeaderboardEntry] {
        let rows = try await client.execute(
            """
            select
                u.id as id,
                u.username as username,
                coalesce(sum(c.awarded_points), 0)::int as points,
                count(c.id)::int as finds
            from users u
            left join hunt_claims c on c.hunter_id = u.id
            group by u.id, u.username
            order by points desc, u.username asc;
            """
        )

        return rows.compactMap { row in
            guard
                let id = row.uuid("id"),
                let username = row.string("username")
            else { return nil }
            return LeaderboardEntry(
                id: id,
                username: username,
                points: row.int("points") ?? 0,
                finds: row.int("finds") ?? 0
            )
        }
    }

    func meccasOwned(by ownerID: UUID) async throws -> [Mecca] {
        let rows = try await client.execute(
            """
            select
                m.id as id,
                m.owner_id as owner_id,
                u.username as owner_username,
                m.name as name,
                m.latitude as latitude,
                m.longitude as longitude,
                m.altitude as altitude,
                m.size_mm as size_mm,
                m.x_rotation as x_rotation,
                m.y_rotation as y_rotation,
                m.tint_red as tint_red,
                m.tint_green as tint_green,
                m.tint_blue as tint_blue,
                coalesce(m.placement_mode, 'world_map') as placement_mode,
                extract(epoch from m.created_at) as created_at_epoch,
                0 as claim_count,
                0 as claimed_by_me,
                (exists (select 1 from mecca_world_maps w where w.mecca_id = m.id))::int as has_world_map,
                (exists (select 1 from mecca_face_photos f where f.mecca_id = m.id))::int as has_face_photo
            from meccas m
            join users u on u.id = m.owner_id
            where m.owner_id = $1::uuid and m.state = 'active'
              and m.created_at >= now() - interval '30 days'
            order by m.created_at desc;
            """,
            [.uuid(ownerID)]
        )
        return rows.compactMap(Self.mecca(from:))
    }

    func deleteMecca(id: UUID, ownerID: UUID) async throws {
        // Only the owner can delete, and only while it's still active (unfound).
        // An empty result means it wasn't theirs, was already found, or is gone.
        let rows = try await client.execute(
            """
            delete from meccas
            where id = $1::uuid and owner_id = $2::uuid and state = 'active'
            returning id;
            """,
            [.uuid(id), .uuid(ownerID)]
        )

        guard rows.first?.uuid("id") != nil else {
            throw MeccaRepositoryError.notFound
        }
    }

    func uploadWorldMap(meccaID: UUID, compressedData: Data) async throws {
        let base64 = compressedData.base64EncodedString()
        _ = try await client.execute(
            """
            insert into mecca_world_maps (mecca_id, data)
            values ($1::uuid, $2)
            on conflict (mecca_id) do update
                set data = excluded.data, created_at = now();
            """,
            [.uuid(meccaID), .text(base64)]
        )
    }

    func worldMap(for meccaID: UUID) async throws -> Data? {
        let rows = try await client.execute(
            """
            select data from mecca_world_maps where mecca_id = $1::uuid;
            """,
            [.uuid(meccaID)]
        )
        guard let base64 = rows.first?.string("data") else { return nil }
        return Data(base64Encoded: base64)
    }

    func uploadFacePhoto(meccaID: UUID, jpegData: Data) async throws {
        let base64 = jpegData.base64EncodedString()
        _ = try await client.execute(
            """
            insert into mecca_face_photos (mecca_id, data)
            values ($1::uuid, $2)
            on conflict (mecca_id) do update
                set data = excluded.data, created_at = now();
            """,
            [.uuid(meccaID), .text(base64)]
        )
    }

    func facePhoto(for meccaID: UUID) async throws -> Data? {
        let rows = try await client.execute(
            """
            select data from mecca_face_photos where mecca_id = $1::uuid;
            """,
            [.uuid(meccaID)]
        )
        guard let base64 = rows.first?.string("data") else { return nil }
        return Data(base64Encoded: base64)
    }

    private static func mecca(from row: NeonRow) -> Mecca? {
        guard
            let id = row.uuid("id"),
            let ownerID = row.uuid("owner_id"),
            let ownerUsername = row.string("owner_username"),
            let name = row.string("name"),
            let latitude = row.double("latitude"),
            let longitude = row.double("longitude"),
            let createdAt = row.date(epochColumn: "created_at_epoch")
        else {
            return nil
        }

        return Mecca(
            id: id,
            ownerID: ownerID,
            ownerUsername: ownerUsername,
            name: name,
            coordinate: GeoCoordinate(
                latitude: latitude,
                longitude: longitude,
                altitude: row.double("altitude")
            ),
            appearance: MeccaAppearance(
                sizeMillimeters: row.double("size_mm") ?? MeccaAppearance.default.sizeMillimeters,
                xRotationDegrees: row.double("x_rotation") ?? 0,
                yRotationDegrees: row.double("y_rotation") ?? 0,
                red: row.double("tint_red") ?? 1,
                green: row.double("tint_green") ?? 1,
                blue: row.double("tint_blue") ?? 1
            ),
            createdAt: createdAt,
            claimCount: row.int("claim_count") ?? 0,
            claimedByMe: row.bool("claimed_by_me"),
            hasWorldMap: row.bool("has_world_map"),
            hasFacePhoto: row.bool("has_face_photo"),
            placementMode: MeccaPlacementMode(
                rawValue: row.string("placement_mode") ?? ""
            ) ?? .worldMap
        )
    }
}
