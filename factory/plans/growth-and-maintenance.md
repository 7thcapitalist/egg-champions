# Phase 2 plan: growth and maintenance machine

Goal: keep each launched game alive with as little human work as possible.
Agents read the numbers, ship small safe changes, and ask the owner for the
rest. Nothing here names a game; every tool takes `<game-dir>`.

Researched 2026-10-12 from create.roblox.com docs (list at the end).
Items marked UNVERIFIED could not be confirmed in the docs read.

## 1. Data in

| Data | API (an agent can read it alone) | Dashboard only |
| --- | --- | --- |
| Retention, engagement, monetization | Yes. Analytics Query API | |
| Custom events, funnels, economy events | Yes. Same API, once the game logs them | |
| Thumbnail test results | Yes. `ThumbnailWinningSegments`, `ThumbnailQualifiedPTR` | Starting or changing the test |
| Home recommendation signals | Partly. `RFYPlayThroughRate`, `RFYQualifiedPTR` | Quality banners, benchmarks |
| Player save data | Yes. Open Cloud data stores | |
| Ads campaign reports | | Yes. Ads Manager |
| Experiments (A/B of configs) | Results as metrics: UNVERIFIED | Setup and readout |

**Analytics Query API.** `POST https://apis.roblox.com/analytics-query-api/v1/universes/{universeId}/metrics`.
API key scope `universe.analytics:read`. Metrics include `ForwardD1Retention`,
`ForwardD7Retention`, `AverageSessionLengthMinutes`, `PayingUsersCVR`,
`AverageRevenuePerUser`, `DailyRevenue`, `CustomEvent*`, `FunnelStep*`,
`Economy*`, crash and frame rate metrics, and `TotalAbuseReports`. Daily
granularity works for all metrics. Big queries return 202 and must be polled.
Some points come back `Projected` or `NotStatisticallySignificant`, so the
agent must not act on those. Beta or GA status: UNVERIFIED (a DevForum post
calls it beta). Data delay: UNVERIFIED.

**Logging in game.** The game sends `AnalyticsService:LogCustomEvent`,
`LogFunnelStepEvent`, `LogOnboardingFunnelStepEvent` and `LogEconomyEvent`.
Limits: 10 funnels, 5 currencies, 20 transaction types, 100 item SKUs, 8,000
custom field combinations. Egg Champions should log: onboarding funnel (first
click, first hatch, first equip, gym 1 entered, gym 1 won), coin economy
events, egg hatches by egg SKU, rebirths.

**Data stores.** Open Cloud reads player saves
(`/v1/universes/{id}/standard-datastores/...`). Use only for aggregate checks
and support, read only, never bulk export.

## 2. The weekly loop

A scheduled agent, the **Analyst**, runs once a week (Monday, UTC):

1. Pull last 7 and 28 days from the Analytics Query API into
   `<game-dir>/reports/metrics/<date>.json`.
2. Compare against `<game-dir>/targets.json`. Starting targets are owner
   choices, not Roblox numbers: D1 retention, D7 retention, average session
   length, payer conversion, revenue per DAU, crash rate, and onboarding
   funnel step churn.
3. Find the weakest metric and its funnel step. Write at most 3 proposals,
   each as a spec diff with a reason and the metric it should move.
4. Ship allowed proposals through the existing pipeline: spec edit, agent 1,
   agent 2 gate, build, publish to the **test** place, playtester. Then ask
   the owner for the production publish.
5. Write `<game-dir>/reports/weekly-<date>.md`: numbers vs targets, what
   changed last week and what it did, proposals, and what needs the owner.

One change per metric per week, so effects can be read. Roblox notes a short
drop in play through rate is normal when impressions grow; the agent waits
two weeks before calling a change a failure.

| Agent may ship to test alone | Needs the owner |
| --- | --- |
| Balance numbers that keep agent 2 pacing targets met | Any production publish |
| A new event egg from the approved template | Prices, passes, developer products, anything sold for Robux |
| Bug and crash fixes | Title, description, icon, thumbnails, event pages, update notes |
| New analytics events | Ad spend (every time) |
| | Changes that touch the maturity questionnaire answers |

Roblox Configs can change values live without a publish, but values are set
only in the Creator Hub or Studio per the docs. No Open Cloud write API is
documented, so configs are an owner tool for now. Experiments (A/B tests on
configs) run 14 to 60 days and are set up in the dashboard only.

## 3. Live content: limited event eggs

- Cadence: one limited egg every 2 weeks to start. Roblox LiveOps guidance
  puts content releases between weekly and monthly, and says scarcity drives
  engagement.
- Source: an `events` table in the spec (name, dates, egg price, 5 pets, theme).
  Agent 1 turns it into config. Game code reads dates from config, so an egg
  appears and disappears without new code.
- The Planner writes a calendar 6 weeks ahead. The Asset maker gets the pet
  list plus the style guide (round chunky bodies, big eyes, flat colors, under
  2,000 triangles). All pets original; meme style only as original characters.
- The event page on Roblox (Events section, notifications) is dashboard only
  and public facing, so the agent drafts title, subtitle, times and thumbnail;
  the owner posts it. Limit: 10 ongoing or upcoming events.
- Update announcements: 60 characters, once every 3 days, dashboard only.
  The agent drafts; the owner sends.

## 4. Growth

What Roblox says drives Home recommendations: play through rate, first play
bounce rate, play days and playtime per user (D1, D2 to 7, D8 to 28), then
co-play, spend days and Robux per user. Signals are averages per user, so a
small game is not penalized. Users acquired from ads do not count toward
ranking. So retention work in section 2 is the main growth lever.

| Lever | Agent can automate | Must stay manual |
| --- | --- | --- |
| Thumbnails (up to 10; 2 to 5 in personalization test) | Make variants, read winners via API, propose swaps | Upload and start the test (dashboard) |
| Icon | Make variants | Upload |
| Title, description | Draft. `PATCH /cloud/v2/universes/{id}` exists, but fields for text: UNVERIFIED | Approve every change |
| Sponsored ads (Ads Manager) | Draft campaign, creatives, budget; read reports by hand-off | Create, fund, publish. No API documented. Owner approves every spend |
| Events and updates | Draft | Post |

Thumbnail personalization picks winners automatically by qualified play
through rate; keep several active. Thumbnails must match real gameplay or
exposure drops. Ad campaigns go live after Roblox moderation; reports can lag
48 hours and earnings count up to 30 days after serving.

## 5. Safety

- **Production gate.** No production publish without the owner's OK, every
  time. The place publish API (`.../places/{placeId}/versions?versionType=Published`)
  needs a key with `universe-places` write. Keep the production key out of
  the agent's environment; the owner runs the final publish.
- **Moderation.** Every image, video and event asset is reviewed by Roblox.
  Before any upload, a checker scans names and text for franchise names and
  unsafe words. Keep the maturity questionnaire accurate and resubmit when an
  update changes the answers, or the game can be restricted. Watch
  `TotalAbuseReports` weekly.
- **Rollback.** Every published build is tagged in git with its place version
  number. Rollback = republish the previous tagged `.rbxl` to the same place,
  then `:restartServers` (restarts only old version servers by default).
  Dashboard "Restore" alone does not publish. Note the publish API skips some
  instance types (EditableMesh, SurfaceAppearance, unions); those need Studio.
- **Auto stop.** If crash rate or D1 drops sharply after a release, the agent
  stops shipping and asks the owner to roll back.
- **Secrets.** Keys live in `.env`; agents never print them. Separate keys
  per scope (analytics read; test place write).

## 6. Build order after Egg Champions launches

| Step | Build | Done when |
| --- | --- | --- |
| 1 | Analytics events in game + `targets.json` | Funnel and economy events show up in the API |
| 2 | `factory/tools/pull_metrics.py` | Weekly JSON written with a read-only key |
| 3 | Analyst agent + weekly report | First report written with no person |
| 4 | Proposal to test place path | A balance change reaches test through the gates |
| 5 | Event egg table in spec + config | One event egg runs on test from config dates |
| 6 | Event calendar + asset hand-off | 3 eggs planned, pets made, checker passes |
| 7 | Thumbnail and icon variant maker | 5 variants ready for owner upload |
| 8 | Release tags + rollback script + auto stop | Rollback rehearsed on test |
| 9 | Ad and event drafts for the owner | Owner approves or edits in one pass |

## Sources read

- https://create.roblox.com/docs/llms.txt
- https://create.roblox.com/docs/en-us/production/game-design/analytics-essentials.md
- https://create.roblox.com/docs/en-us/production/analytics/get-started.md
- https://create.roblox.com/docs/en-us/cloud/guides/analytics.md
- https://create.roblox.com/docs/en-us/cloud/guides/analytics/metrics.md
- https://create.roblox.com/docs/en-us/reference/engine/classes/AnalyticsService.md
- https://create.roblox.com/docs/en-us/production/configs.md
- https://create.roblox.com/docs/en-us/production/experiments.md
- https://create.roblox.com/docs/en-us/cloud.md
- https://create.roblox.com/docs/en-us/cloud/reference/domains/apis.md
- https://create.roblox.com/docs/en-us/cloud/reference/features/universes.md
- https://create.roblox.com/docs/en-us/cloud/guides/usage-place-publishing.md
- https://create.roblox.com/docs/en-us/cloud-services/data-stores.md
- https://create.roblox.com/docs/en-us/production/publishing/thumbnails.md
- https://create.roblox.com/docs/en-us/production/promotion/ads-manager.md
- https://create.roblox.com/docs/en-us/discovery.md
- https://create.roblox.com/docs/en-us/production/game-design/liveops-essentials.md
- https://create.roblox.com/docs/en-us/production/promotion/experience-events.md
- https://create.roblox.com/docs/en-us/projects/version-history.md
- https://create.roblox.com/docs/en-us/production/promotion/content-maturity.md
