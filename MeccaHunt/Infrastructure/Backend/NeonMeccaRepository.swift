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
                extract(epoch from m.created_at) as created_at_epoch,
                count(c.id)::int as claim_count,
                coalesce(bool_or(c.hunter_id = $1::uuid), false)::int as claimed_by_me
            from meccas m
            join users u on u.id = m.owner_id
            left join hunt_claims c on c.mecca_id = m.id
            where m.state = 'active'
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
        notBefore: Date
    ) async throws -> Mecca {
        // The insert only fires when no Mecca by this owner exists since
        // `notBefore`, so an empty result means the daily limit was hit.
        let rows = try await client.execute(
            """
            with inserted as (
                insert into meccas (owner_id, name, latitude, longitude, altitude)
                select $1::uuid, $2, $3::double precision, $4::double precision, $5::double precision
                where not exists (
                    select 1 from meccas
                    where owner_id = $1::uuid and created_at >= $6::timestamptz
                )
                returning id, owner_id, name, latitude, longitude, altitude, created_at
            )
            select
                i.id as id,
                i.owner_id as owner_id,
                u.username as owner_username,
                i.name as name,
                i.latitude as latitude,
                i.longitude as longitude,
                i.altitude as altitude,
                extract(epoch from i.created_at) as created_at_epoch,
                0 as claim_count,
                0 as claimed_by_me
            from inserted i
            join users u on u.id = i.owner_id;
            """,
            [
                .uuid(ownerID),
                .text(name),
                .double(coordinate.latitude),
                .double(coordinate.longitude),
                .optionalDouble(coordinate.altitude),
                .timestamp(notBefore)
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
        hunterID: UUID,
        awardedPoints: Int
    ) async throws -> HuntClaim {
        // `target` only matches an active Mecca owned by someone else, so an
        // empty result means it's your own, already found, or missing. The
        // Mecca is flagged `claimed` so it disappears from everyone's map, while
        // the claim row is kept for the leaderboard.
        let rows = try await client.execute(
            """
            with target as (
                select id from meccas
                where id = $1::uuid and owner_id <> $2::uuid and state = 'active'
            ),
            ins as (
                insert into hunt_claims (mecca_id, hunter_id, awarded_points)
                select id, $2::uuid, $3::int from target
                on conflict (mecca_id, hunter_id) do update set claimed_at = now()
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
            [.uuid(meccaID), .uuid(hunterID), .int(awardedPoints)]
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
            awardedPoints: row.int("awarded_points") ?? awardedPoints
        )
    }

    func leaderboard() async throws -> [LeaderboardEntry] {
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
                extract(epoch from m.created_at) as created_at_epoch,
                0 as claim_count,
                0 as claimed_by_me
            from meccas m
            join users u on u.id = m.owner_id
            where m.owner_id = $1::uuid and m.state = 'active'
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
            createdAt: createdAt,
            claimCount: row.int("claim_count") ?? 0,
            claimedByMe: row.bool("claimed_by_me")
        )
    }
}
