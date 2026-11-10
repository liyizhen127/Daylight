import Foundation

public struct HarvestTomato: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let count: Int
    public init(id: UUID, count: Int) { self.id = id; self.count = count }
}
public struct MonthlyHarvest: Equatable, Sendable {
    public let monthKey: String
    public let total: Int
    public let tomatoes: [HarvestTomato]
    public let perTomato: Int
    public init(monthKey: String, sessions: [FocusSession], calendar: Calendar = .planner) {
        self.monthKey = monthKey
        let completed = sessions.filter { $0.outcome == .completed && Day($0.endedAt, calendar: calendar).monthKey == monthKey }
            .sorted { $0.endedAt == $1.endedAt ? $0.id.uuidString < $1.id.uuidString : $0.endedAt < $1.endedAt }
        total = completed.count
        // Bound the number of live physics bodies while preserving the exact total in large months.
        let units = max(1, (completed.count + 239) / 240)
        perTomato = units
        tomatoes = stride(from: 0, to: completed.count, by: units).map { index in
            HarvestTomato(id: completed[index].id, count: min(units, completed.count - index))
        }
    }
}
public extension Planner {
    func monthlyHarvest(on day: Day, calendar: Calendar = .planner) -> MonthlyHarvest {
        MonthlyHarvest(monthKey: day.monthKey, sessions: sessions, calendar: calendar)
    }
}
