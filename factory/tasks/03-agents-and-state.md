# Factory task 03: Agents as files, shared state, and gates

## Goal
Agents coordinate through files in the repo, not through a person. Each agent
is a Claude Code subagent, each game has a state file, and each stage has a
check a machine can run.

## Build
1. Subagent definitions in `.claude/agents/`, one file each, with frontmatter
   (name, description, tools) and the instructions as the body:
   - `spec-parser` (from `factory/agents/01-spec-parser.md`)
   - `economy-tuner` (from `factory/agents/02-economy-tuner.md`)
   - `coder`: does exactly one task brief, runs its Done-when checks, commits.
     Never edits generated folders, the spec, or `.env`.
   Check Claude Code's own documentation for the current subagent file format.
   Keep `factory/agents/` as the human-readable index, or remove the
   duplicates and link to `.claude/agents/`. Do not keep two copies of the text.
2. `games/<game>/state.json`: the single record of progress. Shape:
   a `game` name and a list of `stages`, each with `id`, `status`
   (pending, running, passed, failed, blocked), `attempts`, `note`, `updated`.
   Stages, in order: `spec_parsed`, `economy_tuned`, `planned`, `built`,
   `assets`, `worlds`, `playtested`, `published_test`.
3. `factory/tools/state.py` (standard library only):
   `show <game-dir>`, `set <game-dir> <stage> <status> [--note TEXT]`,
   `next <game-dir>` (prints the first stage that is not passed).
4. `factory/tools/gate.py <game-dir> <stage>`: runs that stage's check and
   exits 0 or 1 with a short reason. Implement the gates that can exist today:
   - `spec_parsed`: the validator passes and `manifest.json` matches the
     spec's current hash.
   - `economy_tuned`: the simulator's report shows the time pacing targets met.
   - `built`: every task in the game's task index is done, `rojo build`
     succeeds, and selene and stylua pass.
   Other stages return "no gate yet" and exit 1.
5. Initialize `games/egg-champions/state.json`: `spec_parsed` and
   `economy_tuned` passed (verify with the gates, do not assume).

## Done when
- [ ] `python factory/tools/gate.py games/egg-champions spec_parsed` exits 0.
- [ ] Editing a number in the spec without rerunning agent 1 makes that gate
      exit 1 (then revert the edit).
- [ ] `python factory/tools/gate.py games/egg-champions economy_tuned` exits 0.
- [ ] `python factory/tools/state.py next games/egg-champions` prints `planned`.
- [ ] The three subagents are listed by Claude Code.
- [ ] Committed and pushed.
