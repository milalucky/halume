import HaluMeCore
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
            .lineLimit(1)
            .fixedSize()
            .accessibilityElement(children: .combine)
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
            content.controlSize(.large)
            if let hint { Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// The app's text field: a soft box with an orange ring while typing (amounts and dates match it).
struct BoxTextField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    @FocusState private var focused: Bool

    init(_ placeholder: LocalizedStringKey, text: Binding<String>) {
        self.placeholder = placeholder
        _text = text
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.background.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(focused ? AnyShapeStyle(Palette.orange.opacity(0.7)) : AnyShapeStyle(.primary.opacity(0.12)),
                              lineWidth: focused ? 1.5 : 1))
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
    }
}

/// A money field that keeps every keystroke: the value updates as you type, in any format.
struct AmountField: View {
    @Binding var amount: Decimal?
    let currency: String
    var placeholder: LocalizedStringKey = "0"

    init(amount: Binding<Decimal>, currency: String) {
        _amount = Binding(get: { amount.wrappedValue }, set: { amount.wrappedValue = $0 ?? 0 })
        self.currency = currency
    }

    /// An optional amount: empty means "not said".
    init(optional amount: Binding<Decimal?>, currency: String, placeholder: LocalizedStringKey) {
        _amount = amount
        self.currency = currency
        self.placeholder = placeholder
    }

    var body: some View {
        NumberText(value: $amount, placeholder: placeholder, suffix: Self.symbol(currency))
    }

    /// "₽", "$", "€": the narrow symbol for the code.
    static func symbol(_ currency: String) -> String {
        let sample = Decimal(0).formatted(.currency(code: currency).presentation(.narrow).precision(.fractionLength(0)))
        let symbol = sample.filter { !$0.isNumber && !$0.isWhitespace && $0 != "\u{00A0}" && $0 != "\u{202F}" }
        return symbol.isEmpty ? currency : symbol
    }
}

/// A percent field that keeps every keystroke.
struct PercentField: View {
    @Binding var value: Decimal

    var body: some View {
        NumberText(value: Binding(get: { value }, set: { value = $0 ?? 0 }), placeholder: "0", suffix: "%")
    }
}

/// The shared text field behind amounts and percents: parses as you type, tidies up when you leave it.
private struct NumberText: View {
    @Binding var value: Decimal?
    let placeholder: LocalizedStringKey
    let suffix: String
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .monospacedDigit()
            Text(suffix).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.background.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(focused ? AnyShapeStyle(Palette.orange.opacity(0.7)) : AnyShapeStyle(.primary.opacity(0.12)),
                          lineWidth: focused ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
            .onAppear { text = Self.display(value) }
            .onChange(of: text) { _, new in
                let parsed = Amount.parse(new)
                if parsed != value { value = parsed }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { text = Self.display(value) }
            }
            .onChange(of: value) { _, new in
                // Changed from outside (a suggestion, a reset): show it unless the user is typing.
                if !focused, Amount.parse(text) != new { text = Self.display(new) }
            }
    }

    static func display(_ value: Decimal?) -> String {
        guard let value, value != 0 else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)))
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

/// A date as readable text ("25 October 2026") that opens a calendar when clicked.
struct DateField: View {
    @Binding var date: Date
    var range: ClosedRange<Date> = .distantPast ... .distantFuture
    @State private var open = false
    @State private var hovering = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                Text(date.formatted(.dateTime.day().month(.wide).year()))
                    .monospacedDigit()
                Spacer(minLength: 4)
                Image(systemName: "calendar").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.background.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(.primary.opacity(hovering || open ? 0.25 : 0.12)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityValue(Text(date.formatted(date: .long, time: .omitted)))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            DatePicker("", selection: $date, in: range, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(12)
                .onChange(of: date) { open = false }
        }
    }
}

/// Picks a currency: popular ones first, search by code or name in English and the app's language.
struct CurrencyField: View {
    @Binding var code: String
    @State private var open = false
    @State private var query = ""

    private static let popular = ["RUB", "USD", "EUR", "KZT", "BYN", "UAH", "GEL", "AMD", "UZS", "KGS", "AZN", "TRY",
                                  "GBP", "CNY", "AED", "THB", "RSD", "ILS", "PLN", "CHF", "JPY", "INR", "CAD", "AUD"]

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                Text(Self.title(code))
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.background.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.primary.opacity(0.12)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(Self.title(code)))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                BoxTextField("Search currency", text: $query)
                List(matches, id: \.self) { item in
                    Button { code = item; open = false; query = "" } label: {
                        HStack {
                            Text(item).monospaced().foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
                            Text(Self.name(item))
                            Spacer()
                            Text(AmountField.symbol(item)).foregroundStyle(.secondary)
                            if item == code { Image(systemName: "checkmark").foregroundStyle(Palette.orange) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .padding(12)
            .frame(width: 340, height: 380)
        }
    }

    private var matches: [String] {
        let local = Locale.current.currency?.identifier
        let all = Array(Set(Locale.commonISOCurrencyCodes + [code])).sorted()
        let ordered = [local].compactMap { $0 } + Self.popular + all
        var seen = Set<String>()
        let unique = ordered.filter { all.contains($0) && seen.insert($0).inserted }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return unique }
        return unique.filter { c in
            c.lowercased().contains(q) || Self.name(c).lowercased().contains(q)
                || (Locale(identifier: "en").localizedString(forCurrencyCode: c) ?? "").lowercased().contains(q)
        }
    }

    static func name(_ code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }

    static func title(_ code: String) -> String { "\(code) — \(name(code))" }
}
