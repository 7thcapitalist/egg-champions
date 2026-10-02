# Agent 2: Economy tuner

## Job
Check the spec's numbers against its own pacing targets, and set the gym
leader stats. This agent simulates battles and player progression, reports
which targets are met, and proposes new numbers. It never edits the spec or
the config. The human decides which proposals go into the spec.

## Input
`config/*.json` from agent 1. The simulator never reads the spec.
Optional: `tuning/proposal.json`, the numbers this agent wants to try.

## Output
- `tuning/gyms.json`: per world, the leader team stats, the tuned power, the
  reference team, and its win rate at 0 to target + 2 rebirths.
- `tuning/report.md`: targets met and missed, design gaps, the proposal
  table, the predicted result, and every assumption.
Both files are generated. Never edit them by hand.

## Steps
1. Run `python factory/tools/simulate_economy.py config tuning`.
   Options: `--players N` (default 300), `--seed S` (default 1),
   `--proposal FILE`, `--max-hours H` (default 40).
   A `TUNER ERROR` means the config is inconsistent. Rerun agent 1.
2. Read "Current numbers against the targets" in the report. Each row says
   MET or MISSED and by how much.
3. Read "Design gaps found". These need a spec change by the human, for
   example a missing Rare pet of a gym's counter type.
4. If a target is missed, write `tuning/proposal.json` and rerun. Change few
   numbers at a time. Keep going until the predicted result meets the
   targets or you can explain why it cannot.
5. Report: tuned gym powers, targets met and missed, the proposal table,
   and open gaps. Ask the human to approve the proposals. After they edit
   the spec, rerun agent 1 and then this agent with no proposal file.

## Done when
The command exits with code 0, the report states every target as MET or
MISSED, and every missed target has a proposal or a reported gap.

## Proposal file format
Only the keys you want to change. Notes are copied into the report.

    {
      "constants": {"rebirth_first_cost": 2000000},
      "eggs": {"forest": {"price": 5000, "base_click_power": 5}},
      "worlds": {"green_meadow": {"fee": 50000, "target_rebirths": 0}},
      "notes": {"Egg prices": "Why this change."}
    }

Pet stats are recomputed from egg base stats, rarity, and role, so a change
to an egg's base stats reaches its pets. Gyms are tuned again for the
proposal.

## How gyms are tuned
A leader pet has the base HP and Attack of the world's most expensive egg,
times the strength rarity's battle multiplier, times a per-gym `power`.
The tool searches for the `power` at which the reference team wins about
80% of battles at the gym's target rebirths. The reference team is the 3
best Rare pets a player can hatch by that world, with no variants.

## What the simulator models
- Battles: the spec's rules, with a simple player policy.
- Progression: players who click at 4, 2, and 8 clicks per second, hatch
  with the real odds, keep one team for clicking and battling, pay gym
  fees, retry gyms, and rebirth when stuck.
- Not modeled: game passes, pet storage, team swapping, idle time.
The exact policies and every number the spec does not define are listed at
the end of the report. Tunable simulator settings live in `SIM` at the top
of the tool.

## Reading the results
- The main verdict uses the median player at 4 clicks per second.
- Brackets show the 10th to 90th percentile.
- "Finished" is the share of players who beat the last gym before the run
  stops. A low share means some players stall, usually saving for a
  rebirth or a gym fee.
- Results depend on the player policy. Treat them as a first check, then
  confirm with real playtests (agent 7).
