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
}
