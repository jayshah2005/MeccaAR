import Foundation

/// Central rules for how much a Mecca is worth and when it expires. A Mecca is
/// worth more the longer it survives unfound, making long-lived Meccas rarer and
/// more valuable, and it vanishes once it passes the expiry age.
///
/// - Day 0–9:  100 points (common)
/// - Day 10–19: 200 points (uncommon)
/// - Day 20–29: 300 points (rare)
/// - Day 30:    500 points (legendary)
/// - After 30 days: expired (removed from the map/hunts)
enum MeccaScoring {
    static let expiryDays = 30
    static let secondsPerDay: TimeInterval = 86_400

    /// Rarity tier used for display (map markers, badges).
    enum Tier: Int, CaseIterable, Sendable {
        case common
        case uncommon
        case rare
        case legendary

        var label: String {
            switch self {
            case .common: return "Common"
            case .uncommon: return "Uncommon"
            case .rare: return "Rare"
            case .legendary: return "Legendary"
            }
        }
    }

    /// Whole days a Mecca has been hidden.
    static func daysHidden(since createdAt: Date, now: Date = Date()) -> Int {
        max(0, Int(now.timeIntervalSince(createdAt) / secondsPerDay))
    }

    static func points(forDaysHidden days: Int) -> Int {
        switch days {
        case ..<10: return 100
        case 10..<20: return 200
        case 20..<30: return 300
        default: return 500
        }
    }

    static func points(since createdAt: Date, now: Date = Date()) -> Int {
        points(forDaysHidden: daysHidden(since: createdAt, now: now))
    }

    static func tier(forDaysHidden days: Int) -> Tier {
        switch days {
        case ..<10: return .common
        case 10..<20: return .uncommon
        case 20..<30: return .rare
        default: return .legendary
        }
    }

    static func tier(since createdAt: Date, now: Date = Date()) -> Tier {
        tier(forDaysHidden: daysHidden(since: createdAt, now: now))
    }

    /// A Mecca disappears once it has been hidden for more than `expiryDays`.
    static func isExpired(createdAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(createdAt) > Double(expiryDays) * secondsPerDay
    }
}
