# Analytics events

What the server sends to Roblox analytics, and what each event is for. The
playtester and the economy tuner both read this. The list in code is
`src/shared/analytics/Events.luau`; a test fails when an event there has no
row here, when a row here names an event the code does not have, or when a row
does not name every field the event carries.

## Rules

- Every event fires on the server, through `src/server/Analytics.luau`. The
  client never fires one: the numbers here retune the economy, so the client
  cannot be trusted with them.
- An event name that is not in the list is an error, and so is a missing,
  extra or wrongly typed field.
- Every event also carries the player's stage: `rebirths` (the rebirth count)
  and `world` (the highest world open in the current run). In Roblox it is
  custom field 01, written as "rebirths N, world N".
- No personal data beyond the Roblox user id, which Roblox attaches itself.
- Events are batched and flushed on an interval and when a player leaves.
  A failed send is logged and dropped, never retried.
- `secondsSinceJoin` counts from when this session's profile loaded. A tuner
  target is total play time, so for a player who needed several sessions,
  add up `session_end.lengthSeconds` of the earlier sessions.

## How events reach Roblox

- Custom events: `AnalyticsService:LogCustomEvent`. The value is the field
  marked "value" below; custom field 02 and 03 are the fields marked
  "dimension".
- `egg_bought` is an economy event: `LogEconomyEvent` with flow Sink, currency
  Coins, amount `price`, ending balance `coinsAfter`, transaction type Shop
  and item `eggId`.
- `first_hatch` is also onboarding funnel step 1 (`LogOnboardingStepEvent`).

## Events

| Event | Fields | Sent as | Tuner target or spec question |
| --- | --- | --- | --- |
| `session_start` | `coinsPerClick` (value) | custom | Where players stand when a session starts: coins per click and stage. |
| `session_end` | `lengthSeconds` (value), `coinsPerClick` | custom | Session length and how far a session moved coins per click and rebirths. Needed to add up play time across sessions. |
| `first_hatch` | `secondsSinceJoin` (value) | custom and onboarding step 1 | Tuner target "First hatch", `pacing_first_hatch_minutes`. Fires once, on a player's first hatch ever (empty pet index). |
| `egg_bought` | `eggId` (item, dimension), `count` (dimension), `price` (amount), `coinsAfter` (balance) | economy | Which eggs players buy at which stage, and the coin balance they keep. Checks the egg prices in the spec. |
| `pet_hatched` | `petId`, `rarity` (dimension), `variant` (dimension, "normal" for none) | custom | The real rarity and variant distribution, to check against `config/rarities.json` and `config/variants.json`. |
| `pet_equipped` | `petId` (dimension), `team` (the team after, as pet ids) | custom | Which pets players actually field, to check the tuner's reference teams. |
| `gym_attempt` | `worldIndex` (dimension), `secondsSinceJoin` (value) | custom | How many tries each gym takes, at which rebirth count. |
| `gym_result` | `worldIndex` (dimension), `outcome` (dimension: win, loss, gave_up), `secondsSinceJoin` (value) | custom | Tuner targets "Gym N beaten" (`pacing_gym1_minutes_min`, `pacing_gym1_minutes_max`), "Final gym beaten" (`pacing_final_gym_hours_min`, `pacing_final_gym_hours_max`) and "Rebirths at gym N" (the stage's rebirth count on a win). Win rates by rebirths check the tuned gym power and the "hard wall" gaps the report names. |
| `rebirth` | `count` (the new count, dimension), `secondsSinceJoin` (value) | custom | When players rebirth, against the report's rebirth timing table. |
| `world_unlocked` | `worldIndex` (the world that opened, dimension), `secondsSinceJoin` (value) | custom | When each world opens in a run. Fires again after each rebirth, with the new rebirth count. |
| `pass_purchased` | `passId` (dimension) | custom | Which passes sell, and at what stage. |
