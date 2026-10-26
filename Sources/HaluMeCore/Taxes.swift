import Foundation

/// How an income is taxed when it's entered before tax.
public struct TaxSetup: Codable, Sendable, Hashable {
    public enum System: String, Codable, Sendable, Hashable, CaseIterable {
        /// Personal income tax, progressive, withheld cumulatively from January.
        case russia
        /// Federal tax + a province, CPP and EI.
        case canada
        /// Federal tax + a state, Social Security and Medicare.
        case unitedStates
        /// Anywhere else: the user's own withholding rate.
        case flat
    }

    public var system: System
    /// Province or state code ("AB", "TX"); one without built-in rules uses `regionalRate`.
    public var region: String
    /// US: married filing jointly (brackets for the couple).
    public var married: Bool
    /// A province's or state's rate, percent of gross, when it isn't built in.
    public var regionalRate: Decimal
    /// `.flat`: everything withheld, percent of gross.
    public var flatRate: Decimal

    public init(system: System, region: String = "", married: Bool = false, regionalRate: Decimal = 0, flatRate: Decimal = 0) {
        self.system = system; self.region = region; self.married = married
        self.regionalRate = regionalRate; self.flatRate = flatRate
    }
}

/// 2026 rules. Shortcuts: no deductions or credits beyond the basic ones, and Canada/US income tax is spread
/// evenly over the year (as payroll does), while capped contributions are counted payday by payday.
public enum TaxRules {
    /// Exact decimals: a fractional literal would go through Double and lose cents.
    static func dec(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }

    struct Bracket { let upTo: Decimal?; let rate: Decimal }

    static func progressive(_ income: Decimal, _ brackets: [Bracket]) -> Decimal {
        var tax: Decimal = 0, lower: Decimal = 0
        for b in brackets {
            let top = b.upTo ?? .greatestFiniteMagnitude
            if income > lower { tax += (min(income, top) - lower) * b.rate }
            lower = top
            if income <= top { break }
        }
        return tax
    }

    // MARK: Russia (Tax Code art. 224, from 2025)

    static let russia: [Bracket] = [
        .init(upTo: 2_400_000, rate: dec("0.13")), .init(upTo: 5_000_000, rate: dec("0.15")), .init(upTo: 20_000_000, rate: dec("0.18")),
        .init(upTo: 50_000_000, rate: dec("0.20")), .init(upTo: nil, rate: dec("0.22")),
    ]

    /// Income tax on income since January.
    public static func russiaTax(yearToDate: Decimal) -> Decimal { progressive(yearToDate, russia) }

    public static func russiaRate(yearToDate: Decimal) -> Decimal {
        russia.first { $0.upTo.map { yearToDate < $0 } ?? true }?.rate ?? dec("0.22")
    }

    // MARK: Canada 2026

    static let canadaFederal: [Bracket] = [
        .init(upTo: 58_523, rate: dec("0.14")), .init(upTo: 117_045, rate: dec("0.205")), .init(upTo: 181_440, rate: dec("0.26")),
        .init(upTo: 258_482, rate: dec("0.29")), .init(upTo: nil, rate: dec("0.33")),
    ]

    /// A province's or territory's tax: brackets, basic personal amount (and its phase-down), credited at the lowest rate.
    struct Province {
        let brackets: [Bracket]
        let bpa: Decimal
        /// The amount shrinks to `low` between `from` and `to` of taxable income.
        var phase: (from: Decimal, to: Decimal, low: Decimal)?
    }

    static func b(_ rows: [(Decimal?, String)]) -> [Bracket] { rows.map { Bracket(upTo: $0.0, rate: dec($0.1)) } }

    // TaxTips.ca 2026 tables (Manitoba froze indexation from 2025).
    static let provinces: [String: Province] = [
        "AB": Province(brackets: b([(61_200, "0.08"), (154_259, "0.10"), (185_111, "0.12"), (246_813, "0.13"), (370_220, "0.14"), (nil, "0.15")]),
                       bpa: 22_769),
        "BC": Province(brackets: b([(50_363, "0.056"), (100_728, "0.077"), (115_648, "0.105"), (140_430, "0.1229"), (190_405, "0.147"),
                                    (265_545, "0.168"), (nil, "0.205")]), bpa: 13_216),
        "MB": Province(brackets: b([(47_000, "0.108"), (100_000, "0.1275"), (nil, "0.174")]), bpa: 15_780,
                       phase: (200_000, 400_000, 0)),
        "NB": Province(brackets: b([(52_333, "0.094"), (104_666, "0.14"), (193_861, "0.16"), (nil, "0.195")]), bpa: 13_664),
        "NL": Province(brackets: b([(44_678, "0.087"), (89_354, "0.145"), (159_528, "0.158"), (223_340, "0.178"), (285_319, "0.198"),
                                    (570_638, "0.208"), (1_141_275, "0.213"), (nil, "0.218")]), bpa: 13_094),
        "NS": Province(brackets: b([(30_995, "0.0879"), (61_991, "0.1495"), (97_417, "0.1667"), (157_124, "0.175"), (nil, "0.21")]),
                       bpa: 11_932),
        "NT": Province(brackets: b([(53_003, "0.059"), (106_009, "0.086"), (172_346, "0.122"), (nil, "0.1405")]), bpa: 18_198),
        "NU": Province(brackets: b([(55_801, "0.04"), (111_602, "0.07"), (181_439, "0.09"), (nil, "0.115")]), bpa: 19_659),
        "ON": Province(brackets: b([(53_891, "0.0505"), (107_785, "0.0915"), (150_000, "0.1116"), (220_000, "0.1216"), (nil, "0.1316")]),
                       bpa: 12_989),
        "PE": Province(brackets: b([(33_928, "0.095"), (65_820, "0.1347"), (106_890, "0.166"), (142_250, "0.1762"), (200_000, "0.19"),
                                    (nil, "0.20")]), bpa: 15_000),
        "QC": Province(brackets: b([(54_345, "0.14"), (108_680, "0.19"), (132_245, "0.24"), (nil, "0.2575")]), bpa: 18_952),
        "SK": Province(brackets: b([(54_532, "0.105"), (155_805, "0.125"), (nil, "0.145")]), bpa: 20_381),
        // Yukon's amount follows the federal one, down to $14,829 between the federal 26% and 33% brackets.
        "YT": Province(brackets: b([(58_523, "0.064"), (117_045, "0.09"), (181_440, "0.109"), (258_482, "0.128"), (500_000, "0.128"),
                                    (nil, "0.15")]), bpa: 16_452, phase: (181_440, 258_482, 14_829)),
    ]
    /// Provinces and territories with built-in rules.
    public static var canadaProvinces: [String] { Array(provinces.keys) }

    public static let cppExemption: Decimal = 3_500, ympe: Decimal = 74_600, yampe: Decimal = 85_000
    public static let cpp2Rate: Decimal = dec("0.04")
    public static let eiMax: Decimal = 68_900
    public static let qpipMax: Decimal = 103_000

    /// Pension plan (CPP, or QPP in Quebec), its second tier, EI and Quebec's parental insurance.
    public struct Contributions {
        public var pension: Decimal, pension2: Decimal, ei: Decimal, qpip: Decimal
        /// The part of `pension` credited against tax (the base plan); the rest is deducted from income.
        public var pensionBase: Decimal
        public var total: Decimal { pension + pension2 + ei + qpip }
    }

    /// Contributions on earnings since January; `exemption` is the share of the $3,500 used so far.
    public static func canadaContributions(yearToDate: Decimal, province: String = "", exemption: Decimal = cppExemption) -> Contributions {
        let quebec = province == "QC"
        let rate = quebec ? dec("0.063") : dec("0.0595"), baseRate = quebec ? dec("0.053") : dec("0.0495")
        // Payroll stops at the year's maximum even while the exemption is still being spread.
        let pension = min(max(0, min(yearToDate, ympe) - exemption) * rate, (ympe - cppExemption) * rate)
        let pension2 = max(0, min(yearToDate, yampe) - ympe) * cpp2Rate
        let ei = min(yearToDate, eiMax) * (quebec ? dec("0.013") : dec("0.0163"))
        let qpip = quebec ? min(yearToDate, qpipMax) * dec("0.0043") : 0
        return Contributions(pension: pension, pension2: pension2, ei: ei, qpip: qpip, pensionBase: pension * baseRate / rate)
    }

    /// Federal + provincial income tax on a year's employment income.
    /// Shortcut: only the basic credits (no dependants, tuition, medical…).
    public static func canadaIncomeTax(annual: Decimal, province: String) -> Decimal {
        let c = canadaContributions(yearToDate: annual, province: province)
        let enhanced = c.pension - c.pensionBase + c.pension2     // deducted from income
        let taxable = max(0, annual - enhanced)
        // The federal basic personal amount shrinks from $16,452 to $14,829 between the 26% and 33% brackets.
        let federalBPA = phased(16_452, (181_440, 258_482, 14_829), taxable)
        var federal = max(0, progressive(taxable, canadaFederal)
            - dec("0.14") * (federalBPA + min(1_501, annual) + c.pensionBase + c.ei + c.qpip))
        if province == "QC" { federal -= federal * dec("0.165") }  // Quebec abatement
        guard let rules = provinces[province] else { return federal }
        let lowest = rules.brackets[0].rate
        let bpa = rules.phase.map { phased(rules.bpa, $0, taxable) } ?? rules.bpa
        // Quebec credits only the basic amount; the others also credit the base pension plan and EI.
        let credits = province == "QC" ? bpa : bpa + c.pensionBase + c.ei
        // Quebec's deduction for workers: 6% of employment income, up to $1,450.
        let provincialTaxable = province == "QC" ? max(0, taxable - min(annual * dec("0.06"), 1_450)) : taxable
        var provincial = max(0, progressive(provincialTaxable, rules.brackets) - lowest * credits)
        switch province {
        case "ON":
            provincial += max(0, provincial - 5_818) * dec("0.20") + max(0, provincial - 7_446) * dec("0.36")
            // Ontario tax reduction (T4127 factor S): twice $300 less the tax, never below zero.
            provincial -= min(provincial, max(0, 2 * 300 - provincial))
            provincial += ontarioHealthPremium(taxable)
        case "BC":
            // B.C. tax reduction: $690, less 3.56% of income over $25,570.
            provincial = max(0, provincial - max(0, 690 - max(0, annual - 25_570) * dec("0.0356")))
        default:
            break
        }
        return federal + provincial
    }

    static func phased(_ amount: Decimal, _ phase: (from: Decimal, to: Decimal, low: Decimal), _ income: Decimal) -> Decimal {
        let share = min(1, max(0, (income - phase.from) / (phase.to - phase.from)))
        return amount - (amount - phase.low) * share
    }

    /// Ontario Health Premium by taxable income (unchanged since 2004).
    static func ontarioHealthPremium(_ income: Decimal) -> Decimal {
        switch income {
        case ..<20_000: 0
        case ..<36_000: min(300, (income - 20_000) * dec("0.06"))
        case ..<48_000: min(450, 300 + (income - 36_000) * dec("0.06"))
        case ..<72_000: min(600, 450 + (income - 48_000) * dec("0.25"))
        case ..<200_000: min(750, 600 + (income - 72_000) * dec("0.25"))
        default: min(900, 750 + (income - 200_000) * dec("0.25"))
        }
    }

    // MARK: United States 2026

    static let usSingle: [Bracket] = [
        .init(upTo: 12_400, rate: dec("0.10")), .init(upTo: 50_400, rate: dec("0.12")), .init(upTo: 105_700, rate: dec("0.22")),
        .init(upTo: 201_775, rate: dec("0.24")), .init(upTo: 256_225, rate: dec("0.32")), .init(upTo: 640_600, rate: dec("0.35")), .init(upTo: nil, rate: dec("0.37")),
    ]
    static let usJoint: [Bracket] = [
        .init(upTo: 24_800, rate: dec("0.10")), .init(upTo: 100_800, rate: dec("0.12")), .init(upTo: 211_400, rate: dec("0.22")),
        .init(upTo: 403_550, rate: dec("0.24")), .init(upTo: 512_450, rate: dec("0.32")), .init(upTo: 768_700, rate: dec("0.35")), .init(upTo: nil, rate: dec("0.37")),
    ]
    /// States without a tax on wages.
    public static let usNoIncomeTax = ["AK", "FL", "NV", "NH", "SD", "TN", "TX", "WA", "WY"]
    public static let socialSecurityMax: Decimal = 184_500

    public static func usFederalTax(annual: Decimal, married: Bool) -> Decimal {
        progressive(max(0, annual - (married ? 32_200 : 16_100)), married ? usJoint : usSingle)
    }

    /// Social Security and Medicare on wages since January (the employer adds dec("0.9")% above $200,000).
    public static func usFICA(yearToDate: Decimal) -> Decimal {
        min(yearToDate, socialSecurityMax) * dec("0.062") + yearToDate * dec("0.0145") + max(0, yearToDate - 200_000) * dec("0.009")
    }
}

extension Planner {
    /// Gross pay of an income's earlier paydays this calendar year.
    func grossBefore(_ income: Income, on date: Date) -> Decimal {
        let start = calendar.date(from: calendar.dateComponents([.year], from: date))!
        return dates(of: income, from: start, to: add(-1, to: date)!).reduce(0) { $0 + pay(of: income, on: $1, absences: true, gross: true) }
    }

    /// Paydays of an income in a year (for annual figures).
    func paydaysPerYear(_ income: Income, around date: Date) -> Int {
        max(1, dates(of: income, from: date, to: add(-1, to: yearLater(date))!).count)
    }

    /// One payday's pay before tax.
    public func pay(grossOf income: Income, on date: Date) -> Decimal {
        pay(of: income, on: date, absences: true, gross: true)
    }

    /// What is withheld from one payday's gross pay.
    public func tax(of income: Income, gross: Decimal, on date: Date) -> Decimal {
        guard let setup = income.tax, gross > 0 else { return 0 }
        let before = grossBefore(income, on: date)
        let annual = income.isMonthly ? income.expected * 12 : income.expected * Decimal(paydaysPerYear(income, around: date))
        switch setup.system {
        case .russia:
            return up(TaxRules.russiaTax(yearToDate: before + gross) - TaxRules.russiaTax(yearToDate: before))
        case .canada:
            let count = Decimal(paydaysPerYear(income, around: date))
            let done = Decimal(dates(of: income, from: calendar.date(from: calendar.dateComponents([.year], from: date))!, to: date).count)
            // The $3,500 CPP exemption is spread over the year's paydays.
            let now = TaxRules.canadaContributions(yearToDate: before + gross, province: setup.region, exemption: TaxRules.cppExemption * done / count)
            let then = TaxRules.canadaContributions(yearToDate: before, province: setup.region, exemption: TaxRules.cppExemption * (done - 1) / count)
            let contributions = now.total - then.total
            let incomeTax = annual > 0 ? TaxRules.canadaIncomeTax(annual: annual, province: setup.region) / annual * gross : 0
            let provincial = TaxRules.canadaProvinces.contains(setup.region) ? 0 : gross * setup.regionalRate / 100
            return up(max(0, contributions) + incomeTax + provincial)
        case .unitedStates:
            let fica = TaxRules.usFICA(yearToDate: before + gross) - TaxRules.usFICA(yearToDate: before)
            let incomeTax = annual > 0 ? TaxRules.usFederalTax(annual: annual, married: setup.married) / annual * gross : 0
            let state = TaxRules.usNoIncomeTax.contains(setup.region) ? 0 : gross * setup.regionalRate / 100
            return up(fica + incomeTax + state)
        case .flat:
            return up(gross * setup.flatRate / 100)
        }
    }

    /// The share of an amount kept after tax around a date, for extras like vacation pay.
    func afterTaxShare(of member: UUID, on date: Date) -> Decimal {
        guard let income = budget.incomes.first(where: { $0.member == member && $0.tax != nil }) else { return 1 }
        let gross = income.expected
        guard gross > 0 else { return 1 }
        return 1 - tax(of: income, gross: gross, on: date) / gross
    }
}

/// A payday where take-home pay changes because of tax (a higher bracket, contributions done for the year, a new year).
public struct TaxChange: Sendable, Hashable {
    public var date: Date
    /// After-tax difference against the paydays before, + more, − less.
    public var delta: Decimal
    public var system: TaxSetup.System
    /// Russia: the rate from this payday.
    public var rate: Decimal
}

extension Planner {
    /// Paydays in [from, to] where the share withheld changes noticeably.
    public func taxChanges(of member: UUID, from: Date, to: Date) -> [TaxChange] {
        guard let income = budget.incomes.first(where: { $0.member == member && $0.tax != nil }), let setup = income.tax else { return [] }
        var out: [TaxChange] = []
        var previous: Decimal?
        for date in dates(of: income, from: add(-40, to: from)!, to: to) {
            let gross = pay(of: income, on: date, absences: false, gross: true)
            guard gross > 0 else { continue }
            let share = tax(of: income, gross: gross, on: date) / gross
            if let previous, abs((share - previous).double) > 0.005, date >= day(from) {
                let rate = setup.system == .russia ? TaxRules.russiaRate(yearToDate: grossBefore(income, on: date) + gross) : 0
                out.append(TaxChange(date: date, delta: down((previous - share) * gross), system: setup.system, rate: rate))
            }
            previous = share
        }
        return out
    }
}

extension Decimal {
    var double: Double { NSDecimalNumber(decimal: self).doubleValue }
}
