# Task 01: Project skeleton

## Goal
A Rojo project that builds into a Roblox place and loads the generated config,
so every later task has somewhere to put code.

## Build
1. `default.project.json` for Rojo with this mapping:
   - `src/shared` to `ReplicatedStorage.Shared`
   - `src/server` to `ServerScriptService.Server`
   - `src/client` to `StarterPlayer.StarterPlayerScripts.Client`
   - `config` to `ReplicatedStorage.GameConfig` (Rojo turns each `.json` file
     into a ModuleScript that returns a table)
   - `tuning/gyms.json` to `ReplicatedStorage.GameConfig.gyms`
   Include a Baseplate and a SpawnLocation in Workspace so the place is playable.
2. `selene.toml` (std = "roblox") and `stylua.toml`.
3. `src/shared/Config.luau`: one module that requires every GameConfig module
   and exposes typed lookups: `Config.constants`, `Config.pets`,
   `Config.petById`, `Config.eggById`, `Config.worldByIndex`,
   `Config.rarityById`, `Config.typeById`, `Config.specialById`,
   `Config.gymByWorld`. Error loudly if an id is missing.
4. `src/server/init.server.luau`: on start, load Config and print one line:
   game name, number of pets, eggs, and worlds.
5. `src/client/init.client.luau`: empty placeholder that prints "client ready".
6. Add `build/` to `.gitignore`.

## Done when
- [ ] `rojo build -o build/egg-champions.rbxl` succeeds.
- [ ] `selene src` reports no errors and `stylua --check src` passes.
- [ ] Opening the built file in Studio and pressing Play prints the server
      line with 30 pets, 6 eggs, and 3 worlds, with no errors in the Output.
- [ ] Changes are committed and pushed.

## Out of scope
Gameplay, UI, saving, tests, and publishing. Those are later tasks.
