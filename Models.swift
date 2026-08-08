import Foundation
import SwiftUI

struct StrokePoint: Codable, Hashable {
    var x: Float
    var y: Float
}

struct Drawing: Codable, Hashable {
    var strokes: [[StrokePoint]] = []
    var color: CodableColor = .orange

    var isEmpty: Bool { strokes.allSatisfy { $0.count < 2 } }
}

struct CodableColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double

    static let orange = CodableColor(red: 1, green: 0.35, blue: 0.05)
    static let blue = CodableColor(red: 0.05, green: 0.55, blue: 1)
    static let pink = CodableColor(red: 1, green: 0.1, blue: 0.5)
    static let green = CodableColor(red: 0.15, green: 0.8, blue: 0.35)

    var swiftUIColor: Color { Color(red: red, green: green, blue: blue) }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var drawing = Drawing()
    @Published var mode: AppMode = .draw
    @Published var status = "Draw something with your finger"

    enum AppMode { case draw, place }

    func startPlacing() {
        guard !drawing.isEmpty else {
            status = "Add at least one line first"
            return
        }
        mode = .place
        status = "Move your phone, then tap a surface"
    }

    func startOver() {
        drawing = Drawing()
        mode = .draw
        status = "Draw something with your finger"
    }
}
