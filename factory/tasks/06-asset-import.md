# Factory task 06: Asset import

## Goal
The approved pet and egg models reach the built game with nobody dragging
them into Studio. The build stays a pure Rojo build from files, and the
`assets` stage has a gate that passes only when every pet and egg in config
has a working model.

## Chosen approach
The repo keeps only asset ids. The server builds each model at startup with
`AssetService:CreateMeshPartAsync(meshId)`, sets `TextureID`, scales it to its
target height, and stores the result as a template in ReplicatedStorage.
`PetVisual` (game task 14) clones the template, and falls back to the
placeholder block if a template is missing.

Why: `MeshId` cannot be set by scripts, and a Rojo `.model.json` cannot carry
a MeshPart's collision and size data (it is stored in hidden SharedString
properties, which Rojo's JSON format does not implement), so a JSON MeshPart
is not trustworthy. A `.rbxm` exported from Studio would carry that data, but
no tool we have can write a file out of Studio without a person.
`CreateMeshPartAsync` has no special security level, runs in a live server,
and computes collision itself, so the whole path runs from files and ids.

## Fallback
If `CreateMeshPartAsync` fails in a live server (permissions, throttling):
1. Run an Open Cloud Luau Execution task against the test place that builds
   the 36 models with `CreateMeshPartAsync` and uploads them as one Model
   asset with `AssetService:CreateAssetAsync` (this context is allowed, with
   `CreatorId` and `CreatorType` set).
2. Download that asset as a `.rbxm` (Open Cloud asset delivery), check it in
   at `games/egg-champions/assets/models.rbxm`, and map it in
   `default.project.json`. A `.rbxm` made by Roblox carries the hidden mesh
   data, so the Rojo build gets correct size and physics.
3. Last resort: the owner exports the models once with Save to File. This is
   the only step in this brief that needs a person.

## Build
1. Model table. `factory/tools/build_models.py <game-dir>` (standard library
   only) reads `<game-dir>/assets/manifest.json` and the game config, and
   writes `<game-dir>/assets/models.json`:
   - one entry per pet id and per egg id from config:
     `{"kind": "pet", "mesh_id": 123, "texture_id": 456, "height": 5.0}`
   - a `manifest_sha256` field, so a stale table can be detected.
   - It exits 1 and names the id when a pet or egg has no model, a mesh or
     texture id is not a positive integer, or the manifest names an id that
     is not in config.
   Map the file in `default.project.json` next to `gyms`:
   `"models": {"$path": "assets/models.json"}` under `GameConfig`. Do not
   write into `config/`; agent 1 owns that folder.
2. Runtime loader. `src/server/ModelLibrary.luau` (a game file, so the coder
   agent writes it as a game brief, not this factory brief):
   - At server start, for each entry in `GameConfig.models`, call
     `CreateMeshPartAsync` in a `pcall`, one at a time, with up to 3 tries
     and a short wait between tries.
   - Set `TextureID`, `Anchored = true`, `CanCollide = false`,
     `CanQuery = false`, `CanTouch = false`, `CastShadow = true`, then scale
     `Size` so the height matches the entry.
   - Wrap it in a Model named by id, with the elemental attachment from task
     14, and parent it to `ReplicatedStorage.PetModels`.
   - Log every failure with the id. A failure leaves the placeholder, never
     an error for the player.
   - Fill the task 14 seam table from the templates that loaded.
3. Remote check. `factory/tools/verify_assets.py <game-dir>`:
   - Reads the API key from the environment variable named in
     `roblox.json` (`api_key_secret`). Never print it, log it, or read `.env`
     as text into any output.
   - Starts an Open Cloud Luau Execution task on the test place (ids from
     `roblox.json`). The script calls `CreateMeshPartAsync` for every entry
     and returns, per id, ok or the error, `MeshSize`, and whether the
     texture loaded (`ContentProvider:PreloadAsync`).
   - Writes `<game-dir>/assets/verify.json` with the results, the time, and
     the `sha256` of `models.json` it checked.
   - Find the endpoint, the scope the API key needs, the time limit and the
     output size limit in the Open Cloud docs. Do not guess them.
4. Gate. Add `assets` to `factory/tools/gate.py`. It passes when:
   - every pet and every egg in config has an entry in `models.json`,
   - `models.json` is current (its `manifest_sha256` matches the manifest),
   - `default.project.json` maps `models.json`, and `rojo build` succeeds,
   - `verify.json` exists, its hash matches the current `models.json`, and
     every entry is ok with a `MeshSize` above zero on every axis.
   Like the other gates, it only reads files. It never calls Roblox.
5. Moranguete texture. Her repainted texture lives only as an EditableImage
   in the open Studio session, so it has no asset id yet.
   - `factory/studio/SaveEditableImages.server.luau`: a small local Studio
     plugin. Plugins may call `AssetService:CreateAssetAsync`; the Studio MCP
     `execute_luau` sandbox may not (it lacks that capability).
   - The plugin watches for MeshParts with the attribute
     `SaveTexture = true`. For each, it reads the EditableImage from
     `TextureContent`, calls `CreateAssetAsync(image, Enum.AssetType.Image,
     {Name = <part name>})`, sets `TextureID` to the new id, sets the
     attribute `SavedTextureId`, and clears `SaveTexture`. On failure it sets
     `SaveTextureError` with the message.
   - An agent then uses `execute_luau` only to set `SaveTexture` and read
     `SavedTextureId` back. The id goes into the manifest.
   - Installing the plugin means copying the file into the Studio local
     Plugins folder. Document the path in the README.
6. Studio camera rule. Any step that takes a Studio screenshot must set
   `workspace.CurrentCamera.CameraType = Enum.CameraType.Fixed` when it is
   done, so the owner's view does not drift. Add this rule to the asset
   maker agent file when that agent is built, and follow it in this brief.
7. Document in `factory/README.md`: the three asset files, how to rerun
   `build_models.py` and `verify_assets.py`, the plugin install, and the new
   `assets` row in the gate table.

## Done when
- [x] `python factory/tools/build_models.py games/egg-champions` exits 0 and
      `games/egg-champions/assets/models.json` has 36 entries: 30 with kind
      `pet` and 6 with kind `egg`.
- [x] Removing one pet from a scratch copy of the manifest makes
      `build_models.py` exit 1 and name that pet.
- [ ] Moranguete's entry has a positive integer `texture_id` that came from
      the plugin, and `execute_luau` reads her MeshPart's `SavedTextureId`
      as the same number.
- [ ] `python factory/tools/verify_assets.py games/egg-champions` exits 0
      and `verify.json` shows 36 ok entries.
- [ ] `python factory/tools/gate.py games/egg-champions assets` exits 0.
- [ ] Editing one `mesh_id` in `models.json` by hand makes the gate exit 1
      (stale `verify.json`); restore the file afterwards.
- [x] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl`
      succeeds.
- [ ] After every screenshot taken for this brief, `execute_luau` returns
      `Enum.CameraType.Fixed` for `workspace.CurrentCamera.CameraType`.
- [ ] `grep -rn "\.env" factory/tools/verify_assets.py` shows no file read
      of `.env`, and no API key appears in `verify.json` or any log.
- [ ] Committed and pushed.

## Needs human or playtester
- [ ] In the published test place, pets look the same size and color as in
      the Studio test place.

## Out of scope
Making or choosing models (agent 5). Rigging and animation. Egg hatch
effects. The `ModelLibrary.luau` game code itself, which goes in a game
brief after task 14. Publishing to production.
