import HaluMeCore
import SwiftUI

/// Before or after tax, the province or state, and what that leaves on payday.
struct TaxFields: View {
    @Binding var pay: PaySettings
    let currency: String
    var calendar: WorkCalendar?

    var body: some View {
        Field("The amount is") {
            Picker("The amount is", selection: $pay.beforeTax) {
                Text("Before tax").tag(true)
                Text("After tax").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
        }
        if pay.beforeTax {
            switch pay.taxSystem {
            case .russia:
                Text("Personal income tax 13%, 15% on the part of the year's income above 2.4 million, and so on up to 22%. Counted from January, like payroll does.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            case .canada:
                HStack(alignment: .top, spacing: 12) {
                    Field("Province") {
                        Picker("Province", selection: $pay.region) {
                            ForEach(Regions.canada, id: \.code) { Text(LocalizedStringKey($0.name)).tag($0.code) }
                        }
                        .labelsHidden()
                    }
                    .frame(width: 240, alignment: .leading)
                    if !TaxRules.canadaProvinces.contains(pay.region) {
                        Field("Provincial tax, % of pay", hint: "Not built in yet: take it from a payslip") { PercentField(value: $pay.regionalRate) }
                            .frame(width: 220, alignment: .leading)
                    }
                }
                Text("Federal and provincial tax, CPP and EI, 2026 rates.").font(.caption).foregroundStyle(.secondary)
            case .unitedStates:
                HStack(alignment: .top, spacing: 12) {
                    Field("State") {
                        Picker("State", selection: $pay.region) {
                            ForEach(Regions.unitedStates, id: \.code) { Text(LocalizedStringKey($0.name)).tag($0.code) }
                        }
                        .labelsHidden()
                    }
                    .frame(width: 220, alignment: .leading)
                    Field("Filing") {
                        Picker("Filing", selection: $pay.married) {
                            Text("Single").tag(false)
                            Text("Married, jointly").tag(true)
                        }
                        .labelsHidden()
                    }
                    .frame(width: 180, alignment: .leading)
                }
                if !TaxRules.usNoIncomeTax.contains(pay.region) {
                    Field("State tax, % of pay", hint: "Not built in yet: take it from a pay stub") { PercentField(value: $pay.regionalRate) }
                        .frame(width: 220, alignment: .leading)
                }
                Text("Federal tax with the standard deduction, Social Security and Medicare, 2026 rates.").font(.caption).foregroundStyle(.secondary)
            case .flat:
                Field("Withheld, % of pay", hint: "Taxes and contributions together, from a payslip") { PercentField(value: $pay.flatRate) }
                    .frame(width: 240, alignment: .leading)
            }
            if let preview { Label(preview, systemImage: "equal.circle").font(.callout.weight(.medium)) }
        }
    }

    /// "About 3,103 after tax on 15 November, ~25.5% withheld".
    private var preview: String? {
        guard pay.amount > 0 else { return nil }
        let member = UUID()
        var income = Income(member: member, name: "", schedule: .monthly(days: [10]), expected: 0)
        pay.apply(to: &income)
        var budget = Budget(name: "", currency: currency, members: [Member(id: member, name: "")], incomes: [income])
        budget.workCalendar = calendar
        let planner = Planner(budget)
        guard let next = planner.paydays(of: member, from: Date(), to: Calendar.current.date(byAdding: .month, value: 2, to: Date())!).first
        else { return nil }
        let net = planner.expected(of: income, on: next)
        let gross = planner.pay(grossOf: income, on: next)
        guard gross > 0 else { return nil }
        let share = (1 - net / gross).double.formatted(.percent.precision(.fractionLength(1)))
        return String(localized: "About \(net.money(currency)) after tax on \(next.formatted(.dateTime.day().month(.wide))), \(share) withheld")
    }
}

/// Picks a country, searchable, with its name in the app's language.
struct CountryField: View {
    @Binding var code: String
    @State private var open = false
    @State private var query = ""

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                Text(Self.name(code))
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
        .accessibilityValue(Text(Self.name(code)))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                BoxTextField("Search country", text: $query)
                List(matches, id: \.self) { item in
                    Button { code = item; open = false; query = "" } label: {
                        HStack {
                            Text(Self.name(item))
                            Spacer()
                            if ["RU", "CA", "US"].contains(item) {
                                Text("Taxes built in").font(.caption).foregroundStyle(.secondary)
                            }
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
        let all = Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
        let first = ["RU", "CA", "US"]
        let ordered = first + all.filter { !first.contains($0) }.sorted { Self.name($0) < Self.name($1) }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return ordered }
        return ordered.filter {
            Self.name($0).lowercased().contains(q) || $0.lowercased() == q
                || (Locale(identifier: "en").localizedString(forRegionCode: $0) ?? "").lowercased().contains(q)
        }
    }

    static func name(_ code: String) -> String { Locale.current.localizedString(forRegionCode: code) ?? code }
}

enum Regions {
    struct Region { let code: String; let name: String }

    static let canada: [Region] = [
        ("AB", "Alberta"), ("BC", "British Columbia"), ("MB", "Manitoba"), ("NB", "New Brunswick"),
        ("NL", "Newfoundland and Labrador"), ("NS", "Nova Scotia"), ("NT", "Northwest Territories"), ("NU", "Nunavut"),
        ("ON", "Ontario"), ("PE", "Prince Edward Island"), ("QC", "Quebec"), ("SK", "Saskatchewan"), ("YT", "Yukon"),
    ].map(Region.init)

    static let unitedStates: [Region] = [
        ("AL", "Alabama"), ("AK", "Alaska"), ("AZ", "Arizona"), ("AR", "Arkansas"), ("CA", "California"), ("CO", "Colorado"),
        ("CT", "Connecticut"), ("DE", "Delaware"), ("DC", "District of Columbia"), ("FL", "Florida"), ("GA", "Georgia"),
        ("HI", "Hawaii"), ("ID", "Idaho"), ("IL", "Illinois"), ("IN", "Indiana"), ("IA", "Iowa"), ("KS", "Kansas"),
        ("KY", "Kentucky"), ("LA", "Louisiana"), ("ME", "Maine"), ("MD", "Maryland"), ("MA", "Massachusetts"),
        ("MI", "Michigan"), ("MN", "Minnesota"), ("MS", "Mississippi"), ("MO", "Missouri"), ("MT", "Montana"),
        ("NE", "Nebraska"), ("NV", "Nevada"), ("NH", "New Hampshire"), ("NJ", "New Jersey"), ("NM", "New Mexico"),
        ("NY", "New York"), ("NC", "North Carolina"), ("ND", "North Dakota"), ("OH", "Ohio"), ("OK", "Oklahoma"),
        ("OR", "Oregon"), ("PA", "Pennsylvania"), ("RI", "Rhode Island"), ("SC", "South Carolina"), ("SD", "South Dakota"),
        ("TN", "Tennessee"), ("TX", "Texas"), ("UT", "Utah"), ("VT", "Vermont"), ("VA", "Virginia"), ("WA", "Washington"),
        ("WV", "West Virginia"), ("WI", "Wisconsin"), ("WY", "Wyoming"),
    ].map(Region.init)
}
