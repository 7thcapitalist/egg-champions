# Progression policy review

The current generated tuning report meets its three time targets but misses
the last gym's median rebirth target: seven versus five. The factory previously
ignored that row. Task factory/07 now requires all configured gym rebirth rows
and records economy_tuned as failed. No spec, config, leader strength or profile
data was changed in this review.

## Mechanism found in the simulator

`Game.reference_team` in factory/tools/simulate_economy.py chooses a Rare team
for combat, while `simulate_player` reselects coin earners during farming and
uses greedy battle training after consecutive losses. They answer different
questions. The checked-in report already exposes that distinction: the final
Rare reference team wins about 79% at five rebirths, while the progression
cohort reaches a median seven.

A separate read-only analysis supplied from the task workspace on 2026-10-17
ran 300 simulated players and explored leader strength and equipment policy.
It reported that reducing final leader power from 1.324 to 1.10 reaches median
five, but lets the Rare reference team win at four; selecting a battle team
before every fight instead makes the early gyms too fast. Those are sensitivity
results from that analysis, not new published-client observations or a validated
full simulator/Luau combat parity audit. They do not justify accepting a single
number change as a complete fix.

Next economy work must specify the expected equipment policy, reconcile it
with the actual BEST BATTLE UI (generic HP/Attack score, not automatic opponent
counter-selection), and jointly check all gym times, rebirth counts and reference
win rates. Keep natural playtests separate from simulations. Current save/rejoin
and pass-purchase validation also remain separate release requirements.
