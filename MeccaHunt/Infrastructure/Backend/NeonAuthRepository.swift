import Foundation

struct NeonAuthRepository: AuthRepository {
    let client: NeonClient

    func signIn(username: String) async throws -> User {
        let normalized = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let rows = try await client.execute(
            """
            insert into users (username)
            values ($1)
            on conflict (username) do update set username = excluded.username
            returning id, username, extract(epoch from created_at) as created_at_epoch;
            """,
            [.text(normalized)]
        )

        guard
            let row = rows.first,
            let id = row.uuid("id"),
            let name = row.string("username"),
            let createdAt = row.date(epochColumn: "created_at_epoch")
        else {
            throw NeonError.decoding
        }

        return User(id: id, username: name, createdAt: createdAt)
    }

    func deleteAccount(userID: UUID) async throws {
        // A single statement so every dependent row is removed before the FK
        // checks at statement end. Deletes: world maps for this user's Meccas,
        // claims against those Meccas, claims made by this user, the Meccas
        // themselves, then the user.
        _ = try await client.execute(
            """
            with del_maps as (
                delete from mecca_world_maps
                where mecca_id in (select id from meccas where owner_id = $1::uuid)
            ),
            del_claims_on_mine as (
                delete from hunt_claims
                where mecca_id in (select id from meccas where owner_id = $1::uuid)
            ),
            del_my_claims as (
                delete from hunt_claims where hunter_id = $1::uuid
            ),
            del_meccas as (
                delete from meccas where owner_id = $1::uuid
            )
            delete from users where id = $1::uuid;
            """,
            [.uuid(userID)]
        )
    }
}
