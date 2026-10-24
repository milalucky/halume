# HaluMe — paycheck planner

Brand: Halu (same as the Halu notch app). Swift Package, no dependencies. Mac app first, then iPhone, Apple Watch, and a glance in Halu's notch. Built for anyone (aim: a million users), not for one household. Ships in English and Russian.

## Language

- Talk to the user in Russian.
- Code and comments are English. UI strings are English keys, translated in `Resources/ru.lproj/Localizable.strings` (+ `.stringsdict` for plurals). After changing UI text run `scripts/check-strings.sh`; it must say "All UI strings translated". Use `LocalizedStringKey` / `String(localized:)` for every UI string; ternaries of literals need `LocalizedStringKey(...)` or `String(localized:)` per branch, or they silently stay English.

## The idea

Plan money once per payday instead of logging every expense. Few people keep logging spending past a few weeks; decisions made in advance (automatic saving, labelled envelopes) raise savings and stick.

- **Period** = from one payday to the next. Not the calendar month.
- **Incomes**: monthly on given days or every N weeks; weekend paydays move earlier/later. The real amount is entered when it arrives.
- **Bills**: monthly, paid from the payday on or before the due date.
- **Debts** (`Debt`): instalments (Yandex Split / BNPL, 0%), loans, mortgages, credit cards, money owed to a person. Balance "left today" + rate + monthly payment; payments marked done come off it (monthly interest added per payment). Payoff calculator: what if I pay more each month / once now → months and interest saved.
- **Subscriptions**: price, cycle (week/month/3 months/year), next charge, free trial end, category, cancelled list ("saving X a month"). Charges go into the payday plan. Yearly cost is compared with days of spending money.
- **Envelopes** (savings): target by a date (recomputed each payday, so short pays catch up), percent of pay, fixed per payday, yearly expense, or open. Where the money lives (`Holding`): card, cash, savings account, deposit, investments. Savings accounts and deposits have a rate, a payout day and "interest to my card"; interest that stays grows the balance. Tips are plain arithmetic on the user's own rates — never product or investment advice.
- **Withdrawals** from envelopes are recorded and show in stats.
- **Free money** = pay − bills − debts − subscriptions − envelopes → "about N a day until payday" is the main number. Optional balance check (one number) recomputes it.
- **Leftover**: the pay sheet asks (optionally) what was left from the last pay; stats use it to show overspending without logging expenses.
- **Stats**: month / 6 months / year / 5 years; income vs expected, where pay went, saved vs taken out, "worth noticing" moments; CSV export.
- **Reminders** (Settings, ⌘,): payday, the day before bills/debt payments, subscription charges, two days before a trial ends. Local notifications only.
- **No** expense logging and no bank connections.

## Households

One model for a single person, a fully shared or a partly shared budget. Every income belongs to a member; bills, debts, subscriptions and envelopes are owned by a member or shared and split equally, by income, by weights, or paid by one member. The UI shows one member for now; sharing comes with CloudKit.

## Code

- `HaluMeCore`: Codable models (`Model.swift`; newer fields decode with defaults so old files load), the pure engine (`Planner.swift`) and `Stats.swift`. No UI, no storage. Shared by every platform.
- `HaluMe`: the Mac app (SwiftUI). `BudgetStore` keeps the budget in `~/Library/Application Support/HaluMe/budget.json` (an unreadable file is moved aside, never overwritten). Sidebar sections: Today, Savings, Debts, Subscriptions, Stats.
- `swift run money-check`: assert-based checks of the engine (no XCTest without full Xcode). Run after every engine change.
- `scripts/build.sh [--install]` builds `build/HaluMe.app`. `scripts/icon/main.swift` renders the icon.
- Demo mode for design checks and screenshots (nothing is saved): `HaluMe --demo [--dark|--light] [--section today|savings|debts|subscriptions|stats] [--sheet pay|balance|plan|debt|payoff|subscription|withdraw] [--step 0-4]`; add `-AppleLanguages "(ru)" -AppleLocale ru_RU` for Russian.
- Design: native macOS (system font, semantic colours, light/dark), Halu orange only for the main action and status, cards separated by fill (no borders/shadows), radius 20, 8-pt spacing, big numbers in SF Rounded with monospaced digits, labels always visible above fields, every icon button has a tooltip and an accessibility label, every action is in the menu bar too.
- Sync later via CloudKit (private DB for personal, shared zone + CKShare for the household). Needs the paid Apple Developer account, bought when something is ready to ship.

## Next

- CloudKit sync and partner sharing → iPhone app + widget → Watch → Halu notch glance.
- Irregular income ("live on last month's money" buffer).
- Debts paid every two weeks (Split's default schedule); now monthly only.
- Holidays when shifting paydays (now weekends only); subscription prices in other currencies.
