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
- **Work calendar** (`WorkCalendar`): weekends only, or a country's holidays. Russia 2025–2027 is built in (xmlcalendar.ru: moved days off, working Saturdays); Russia/Belarus/Kazakhstan/Uzbekistan production calendars and other countries' public holidays (date.nager.at) download for the current and next year. Paydays on a day off move to the working day before (Labour Code art. 136); the advance counts working days.
- **Pay**: monthly salary split between two paydays by working days (default), equally or with a fixed advance; per payday for weekly pay; per day for daily pay (planned by the week from Monday). The late-month payday pays the first half of that month, the early one the rest of the month before.
- **Time off** (`Absence`): vacation, sick leave (60/80/100%), unpaid. Paydays shrink by missed working days. Vacation pay arrives 3 days ahead (month / 29.3 × calendar days, public holidays excluded); sick pay: 3 days from the employer with the next payday, the rest from the Social Fund ~14 days after. Shortcuts: average earnings from the current salary, no caps.
- **Kept money** (`Target.carry`): a period with extra money (vacation pay) keeps what the next up to three paydays will lack and passes it on, so "a day" stays even.
- **Wishlist** (`Wish`): wishes are shared with the household; "Save for it" creates a target envelope; "I'll gift this" (`Reservation`) stays with the giver only.
- **Taxes** (`TaxSetup`, HaluMeCore/Taxes.swift, 2026): pay entered before tax. Russia: progressive NDFL 13–22%, cumulative from January. Canada: federal + all 13 provinces/territories (TaxTips.ca tables; Ontario surtax + health premium, B.C. tax reduction, Quebec: QPP/QPIP/EI 1.30% + 16.5% abatement), CPP/CPP2/EI capped per year. US: federal with the standard deduction, Social Security/Medicare, no-tax states; other states and other countries use a % from a payslip. Canada/US income tax is spread evenly, contributions counted payday by payday. The country (asked first in onboarding) sets currency, holidays, taxes and whether salary is yearly (CA/US) or monthly. Rates must be updated every January; checks hold reference values.
- **Projects** (`Project` → `Stage` → `ProjectTask`, HaluMeCore/Project.swift): big goals that are a plan and a budget (moving abroad, a wedding). Tasks have a due date, a cost in any currency (project `rates`, fetched from open.er-api.com or typed), an assignee, "after" another task (moving a date can move the tasks that wait for it), notes and links. Each project has a fund envelope with `Goal.project`: every payday it saves enough for the strictest milestone (money needed by each due date). Marking a task done pays its cost (or the actual amount) out of the fund as a withdrawal, so stats show it; undoing removes it. Template "Move to another country" lays out documents → visa → before the move → first month without amounts.
- **Accounts** (`Account`): cards, savings accounts, deposits, cash, investments — names only, never numbers. Envelopes live in an account and take its terms (`Budget.terms(of:)`: rate, payout day, interest to another account, withdrawable, maturity). Bills/debts/subscriptions say which account pays (`payFrom`).
- **Currencies**: bills, debts, subscriptions, wishes, project steps and incomes carry an optional `currency`; `Budget.rates` (value of one unit in the budget currency) is shared, auto-updated from open.er-api.com twice a day and editable in Settings; plan lines are in the budget currency.
- **Which payday pays** (`PaySlot`): a bill/debt/subscription can come from a chosen payday of the month or half from each; shared costs can be split `.turns` (month by month).
- **Outside the plan**: `Inflow` (money came in, spread into envelopes, the rest is spending money of its period), `Outflow` (unplanned spending from spending money; from a saving it's a `Withdrawal`), `Transfer` between envelopes. `Planner.adjustment` feeds them into "a day".
- **Yearly costs on a date** (`Goal.annual`): an estimate saved for by the next occurrence of a day and month.
- The plan on Today is grouped into envelopes (bills, subscriptions, debts, kept for later, savings, projects); subscriptions start folded.
- Display: thousands separator chosen in Settings (`NumberStyle`: space, dot, comma), theme (system/light/dark).
- **Irregular income** (`Income.irregular`): earnings are recorded as inflows tied to the income; the 1st of each month pays last month's earnings (an estimate until any are recorded).
- **Pay ahead** (`Payday.keep`): part of a bigger-than-usual pay is kept for the next payday.
- **Insights** (HaluMeCore/Insights.swift): runway (savings ÷ a month's costs + usual spending), net worth (savings + `Asset`s − debts, monthly history), who owes whom (shared costs paid from one person's account; `Settlement` marks), subscription review every 3 months (`Subscription.reviewed`), payday recap, what-if scenarios (a changed copy of the budget).
- **Calendar** section: the country's production calendar (holiday names: Russia built in, others from date.nager.at), paydays, time off; pick days to plan a vacation or sick leave. History section: everything outside the plan, editable. Net worth section. Menu bar extra shows the amount a day.
- Interest accrues daily and is paid on the payout day; debt interest is added on each due date up to the last payment marked done; debts can be paid every two weeks (`Debt.biweeklyFrom`). Russian sick pay is capped (2026: 6 827,40 a day).
- **No** expense logging and no bank connections.

## Households

One model for a single person, a fully shared or a partly shared budget. Every income belongs to a member; bills, debts, subscriptions and envelopes are owned by a member or shared and split equally, by income, by weights, or paid by one member. Settings → Household adds a partner (name, optional monthly income for "by income"). The member using a device is remembered per budget (`me.<budget id>` in UserDefaults). An envelope can be hidden from the partner, optionally until a date (a gift).

`Budget.sharedPart(at:)` / `privatePart(of:at:)` / `merged(shared:private:)` (HaluMeCore/Household.swift) define sync: hidden envelopes, money moved in and out of them, and gift reservations live only in their owner's private store; everything else is shared. Sync itself (CloudKit: private DB + shared zone with CKShare, no sign-in screen — the iCloud account is the identity) needs the paid Apple Developer account. Android/Windows later means a Google sign-in and our own server (note: Russian personal data law 152-FZ wants Russian citizens' data stored in Russia; App Store requires Sign in with Apple next to Google).

## Code

- `HaluMeCore`: Codable models (`Model.swift`; newer fields decode with defaults so old files load), the pure engine (`Planner.swift`) and `Stats.swift`. No UI, no storage. Shared by every platform.
- `HaluMe`: the Mac app (SwiftUI). `BudgetStore` keeps the budget in `~/Library/Application Support/HaluMe/budget.json` (an unreadable file is moved aside, never overwritten). Sidebar sections: Today, Savings, Debts, Subscriptions, Stats.
- Tests drive the real app too: `--data <folder>` keeps a test budget apart; key events posted to the process (CGEvent.postToPid) type like a person, accessibility clicks press buttons. Money fields must be checked by typing, not by setting AX values (SwiftUI ignores those).
- `swift run money-check`: assert-based checks of the engine (no XCTest without full Xcode). Run after every engine change.
- `scripts/build.sh [--install]` builds `build/HaluMe.app`. `scripts/icon/main.swift` renders the icon.
- Demo mode for design checks and screenshots (nothing is saved): `HaluMe --demo [--dark|--light] [--section today|savings|debts|subscriptions|stats] [--sheet pay|balance|plan|debt|payoff|subscription|withdraw] [--step 0-4]`; add `-AppleLanguages "(ru)" -AppleLocale ru_RU` for Russian.
- Design: native macOS (system font, semantic colours, light/dark), Halu orange only for the main action and status, cards separated by fill (no borders/shadows), radius 20, 8-pt spacing, big numbers in SF Rounded with monospaced digits, labels always visible above fields, every icon button has a tooltip and an accessibility label, every action is in the menu bar too.
- Sync later via CloudKit (private DB for personal, shared zone + CKShare for the household). Needs the paid Apple Developer account, bought when something is ready to ship.

## Next

- Work lists: `docs/feedback-2026-10-27.md`, `docs/work-2026-10-27b.md` (with status).

- CloudKit sync and partner sharing → iPhone app + widget → Watch → Halu notch glance.
- Irregular income ("live on last month's money" buffer).
- Debts paid every two weeks (Split's default schedule); now monthly only.
- Holidays when shifting paydays (now weekends only); subscription prices in other currencies.
