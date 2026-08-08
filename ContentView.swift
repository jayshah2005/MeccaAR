import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            if model.mode == .draw {
                DrawingScreen()
            } else {
                ARPlacementScreen()
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct DrawingScreen: View {
    @EnvironmentObject private var model: AppModel

    private let colors: [CodableColor] = [.orange, .blue, .pink, .green]

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(red: 0.08, green: 0.09, blue: 0.13)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text("STREET SKETCH")
                        .font(.caption.bold())
                        .tracking(4)
                        .foregroundStyle(.orange)
                    Text("Draw it. Drop it.\nLeave it in the world.")
                        .font(.system(size: 31, weight: .black, design: .rounded))
                        .multilineTextAlignment(.center)
                }

                DrawingCanvas(drawing: $model.drawing)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.15), lineWidth: 1))
                    .shadow(color: model.drawing.color.swiftUIColor.opacity(0.2), radius: 30)
                    .aspectRatio(1, contentMode: .fit)

                HStack {
                    ForEach(colors, id: \.self) { color in
                        Button {
                            model.drawing.color = color
                        } label: {
                            Circle()
                                .fill(color.swiftUIColor)
                                .frame(width: 34, height: 34)
                                .overlay(Circle().stroke(.white, lineWidth: model.drawing.color == color ? 3 : 0))
                        }
                    }

                    Spacer()

                    Button("Clear", systemImage: "trash") {
                        model.drawing.strokes.removeAll()
                    }
                    .buttonStyle(.bordered)
                }

                Text(model.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button(action: model.startPlacing) {
                    Label("Place in AR", systemImage: "arkit")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding()
        }
    }
}

private struct DrawingCanvas: View {
    @Binding var drawing: Drawing
    @State private var currentStroke: [StrokePoint] = []

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                for stroke in drawing.strokes + (currentStroke.isEmpty ? [] : [currentStroke]) {
                    guard let first = stroke.first else { continue }
                    var path = Path()
                    path.move(to: CGPoint(x: CGFloat(first.x) * size.width, y: CGFloat(first.y) * size.height))
                    for point in stroke.dropFirst() {
                        path.addLine(to: CGPoint(x: CGFloat(point.x) * size.width, y: CGFloat(point.y) * size.height))
                    }
                    context.stroke(path, with: .color(drawing.color.swiftUIColor), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let width = max(proxy.size.width, 1)
                        let height = max(proxy.size.height, 1)
                        currentStroke.append(StrokePoint(
                            x: Float(min(max(value.location.x / width, 0), 1)),
                            y: Float(min(max(value.location.y / height, 0), 1))
                        ))
                    }
                    .onEnded { _ in
                        if currentStroke.count > 1 { drawing.strokes.append(currentStroke) }
                        currentStroke = []
                    }
            )
        }
    }
}
