# Egg Champions and the game factory

Two things in one repo: a pipeline of AI agents that turns a written game spec into a Roblox game, and the first game it built, **Egg Champions: Pet Clicker Simulator**.

## Why

A Roblox game is mostly numbers: drop rates, prices, battle stats, pacing. If those numbers live in a spec and everything else is generated or checked against it, an AI agent can build and change a game without drifting. The bet is that a very small studio can run on that loop: spec, tuning, plan, code, gates, publish.

## The game

Pet clicker plus turn-based gyms. You train in themed rings to earn coins, buy eggs, hatch pets, equip a team of 3, and beat a gym leader in a 3v3 battle to open the next world. Rebirths reset progress for a permanent bonus. The v1 spec has 3 worlds, 3 gyms, 6 eggs, 30 original pets, 4 types, 5 rarities, shiny and golden variants and a pet index. The server decides coins, hatches and battles; the client only sends requests and shows results. The source of truth is `games/egg-champions/spec.md`.

## Status

Early, not launched. Last recorded state (`games/egg-champions/state.json`, 2026-10-22):

| Stage | Status |
|---|---|
| spec parsed, plan (57 task briefs), assets (36 models) | passed |
| economy tuned | **failed**: simulated pacing misses the gym and rebirth targets |
| built | running: Luau tests, Selene, StyLua and Rojo pass; Studio playtests done |
| worlds, playtested, published to test place | pending |

A test place exists on Roblox and has been published to. Publishing to production is gated on my approval. The CI workflow (`.github/workflows/roblox.yml`) is manual-only, because a push once overwrote a newer test build.

## How it works

```
spec.md -> parse_spec -> config/*.json -> simulate_economy -> tuning/
        -> planner -> tasks/*.md -> coder agent (one task at a time) -> src/ (Luau)
        -> gate.py <stage> -> state.py (the only writer of state.json)
```

- `factory/tools/`: the agents' scripts, Python standard library only (spec parser, config validator, economy simulator, gates, test runner, asset and texture jobs, Open Cloud publisher, orchestrator `run_factory.py`).
- `factory/tasks/` and `factory/holding/`: briefs for the factory itself, and a guard that limits agent quota use.
- `games/<game>/`: one folder per game. `config/` is generated from the spec and never edited by hand; `src/` is Luau synced into Studio with Rojo.
- A stage counts as passed only when its gate exits 0. Game code reads every number from config.
- Agent role prompts are in `.claude/agents/`. The orchestrator can run them through Codex CLI (`factory/executor.json`); see `RUN-CODEX.md`.

## Run it

Needs Python 3.12+, Rokit (installs Rojo, Selene and StyLua from `rokit.toml`) and Roblox Studio.

```sh
python factory/tools/validate_config.py games/egg-champions/config
python factory/tools/run_tests.py games/egg-champions
python factory/tools/gate.py games/egg-champions built
```

Publishing needs a Roblox Open Cloud key in a gitignored `.env` (`ROBLOX_API_KEY`) and targets the test place only. Many reports and notes here are working logs, written in Portuguese or English as the work happened, not polished docs.

## What's next

1. Fix the economy so gym pacing and rebirth targets pass.
2. Finish the worlds and a real-device playtest (phone, slow network), then a confirmed test-place publish.
3. Ask for a production publish only after those gates pass.
4. Build a second game in a new `games/<name>/` folder to prove the factory is generic.

## License

MIT, see [LICENSE](LICENSE). Pets and characters are original designs.
