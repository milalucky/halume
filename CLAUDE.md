# Halu Money — paycheck planner

Brand: Halu (same as the Halu notch app). Swift Package, no dependencies. Mac app first, then iPhone, Apple Watch, and a glance in Halu's notch. Built for anyone (aim: a million users), not for one household.

## Language

- Talk to the user in Russian.
- Code, comments and UI text are English (localization RU/EN comes later).

## The idea

Plan money once per payday instead of logging every expense. Research behind it: few people keep logging spending past a few weeks, while decisions made in advance (automatic saving, labelled envelopes) raise savings and stick.

- **Period** = from one payday to the next. Not the calendar month.
- **Incomes**: monthly on given days (e.g. 10 and 25), or every N weeks. A payday on a weekend moves earlier or later (per income). The actual amount is entered when it arrives; the expected one is only the forecast.
- **Bills**: monthly, due on a day. A bill is paid from the payday that falls on or before its due date (the period that contains the due date).
- **Envelopes** (savings): target by a date (contribution recomputed every payday, so a short payday catches up later), percent of each pay, fixed per payday, yearly expense spread over the year's paydays, or open (leftovers only).
- **Free money** = pay − bills − envelopes → "about N a day until payday" is the main number.
- Short pay: bills first (earliest due first), then envelopes by priority, then free money.
- Between paydays the user does nothing. Optional: enter the card balance (one number) and the daily figure is recomputed as (balance − allocations not yet done) / days left.
- **No** expense logging, no categories, no bank connections in v1.

## Households

One model for a single person, a fully shared budget, or a partly shared one (shared bills, own savings, some shared savings). Every income belongs to a member; every bill and envelope is owned by a member or shared. Shared items are split equally, by income, by weights, or paid by one member. Each member gets their own payday plan with their share. Personal envelopes may later be hidden from the partner.

## Code

- `HaluMoneyCore`: Codable models (`Model.swift`) and the pure calculation engine (`Planner.swift`). No UI, no storage. Shared by every platform.
- `swift run money-check`: assert-based checks of the engine. Run after every engine change.
- Sync later via CloudKit (private DB for personal, shared zone + CKShare for the household). Needs the paid Apple Developer account, bought when something is ready to ship. Keep every model Codable with UUID ids.

## Roadmap (v1, Mac, one user in the UI)

1. Core + checks. Done.
2. Onboarding: incomes → bills → goals.
3. Home: days to payday, per-day number, envelopes.
4. Payday screen: enter the amount, checklist of transfers.
5. Plan editor.
6. Balance check.
7. History + income CSV import.

Then CloudKit and partner sharing → iPhone + widget → Watch → Halu notch glance. Irregular income ("live on last month's money" buffer) is planned, not built.
