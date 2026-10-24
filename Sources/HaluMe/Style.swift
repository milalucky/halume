import SwiftUI

enum Palette {
    static let orange = Color(red: 1.00, green: 0.58, blue: 0.24)
    static let green = Color(red: 0.24, green: 0.72, blue: 0.47)
    static let red = Color(red: 0.90, green: 0.33, blue: 0.33)
}

extension Decimal {
    func money(_ currency: String) -> String {
        formatted(.currency(code: currency).presentation(.narrow).precision(.fractionLength(0)))
    }

    var double: Double { NSDecimalNumber(decimal: self).doubleValue }
}

extension View {
    func card(padding: CGFloat = 18) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// The window backdrop: the system background with a soft brand glow at the top.
    func backdrop() -> some View {
        background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                RadialGradient(colors: [Palette.orange.opacity(0.16), .clear],
                               center: .init(x: 0.25, y: 0), startRadius: 0, endRadius: 520)
            }
            .ignoresSafeArea()
        }
    }
}

/// The one main action on a screen: an orange capsule, coloured even when the window is inactive.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Capsulized(configuration: configuration, prominent: true)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Capsulized(configuration: configuration, prominent: false)
    }
}

private struct Capsulized: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.body.weight(prominent ? .semibold : .medium))
            .foregroundStyle(prominent ? AnyShapeStyle(Color.black.opacity(0.85)) : AnyShapeStyle(.primary))
            .padding(.horizontal, 20)
            .frame(minHeight: 36)
            .background {
                Capsule().fill(prominent ? AnyShapeStyle(Palette.orange) : AnyShapeStyle(.quaternary))
                    .brightness(hovering ? 0.05 : 0)
            }
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
    }
}

/// A thin capsule progress bar in the brand colour.
struct Bar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Palette.orange).frame(width: max(6, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 6)
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

/// A round icon button with a tooltip and a spoken label.
struct IconButton: View {
    let icon: String
    let label: LocalizedStringKey
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32)
                .background(Circle().fill(.quaternary.opacity(hovering ? 0.9 : 0.5)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }
}

/// The Halu mark at rest: an open ring with a dot in its gap (same drawing as in Halu).
struct HaluMark: View {
    var size: CGFloat = 18
    var color: Color = Palette.orange

    var body: some View {
        let stroke = size * 0.15, dot = size * 0.21, radius = (size - stroke) / 2
        Canvas { context, canvas in
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            var ring = Path()
            ring.addArc(center: center, radius: radius, startAngle: .radians(-0.264 * 2 * .pi),
                        endAngle: .radians(-0.958 * 2 * .pi), clockwise: true)
            context.stroke(ring, with: .color(color), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            let angle = -0.11 * 2 * .pi, orbit = radius * 0.98
            let p = CGPoint(x: center.x + orbit * cos(angle), y: center.y + orbit * sin(angle))
            context.fill(Path(ellipseIn: CGRect(x: p.x - dot / 2, y: p.y - dot / 2, width: dot, height: dot)), with: .color(color))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct Brand: View {
    var body: some View {
        HStack(spacing: 8) {
            HaluMark(size: 18)
            Text("HaluMe").font(.headline)
        }
    }
}

/// A label that stays visible above its control.
struct Field<Content: View>: View {
    let label: LocalizedStringKey
    var hint: LocalizedStringKey?
    @ViewBuilder let content: Content

    init(_ label: LocalizedStringKey, hint: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.label = label; self.hint = hint; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            content.textFieldStyle(.roundedBorder).controlSize(.large)
            if let hint { Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

struct AmountField: View {
    @Binding var amount: Decimal
    let currency: String

    var body: some View {
        TextField("0", value: $amount, format: .currency(code: currency).presentation(.narrow).precision(.fractionLength(0)))
            .monospacedDigit()
    }
}

struct DayPicker: View {
    @Binding var day: Int

    var body: some View {
        Picker("Day", selection: $day) {
            ForEach(1...31, id: \.self) { Text($0 == 31 ? String(localized: "Last") : "\($0)").tag($0) }
        }
        .labelsHidden()
    }
}

struct RemoveButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: "minus.circle.fill").font(.title3) }
            .buttonStyle(.borderless)
            .foregroundStyle(.tertiary)
            .accessibilityLabel("Remove")
            .help("Remove")
            .padding(.bottom, 6)
    }
}

/// Capsule chips that add a suggested row.
struct Suggestions: View {
    let names: [String]
    let add: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(names + ["Other"], id: \.self) { name in
                Button { add(name == "Other" ? "" : String(localized: String.LocalizationValue(name))) } label: {
                    Label(LocalizedStringKey(name), systemImage: "plus")
                }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

/// Wraps its children onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (items: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.items.isEmpty {
                rows.append(current)
                current = ([i], size.width, size.height)
            } else {
                current = (current.items + [i], needed, max(current.height, size.height))
            }
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
