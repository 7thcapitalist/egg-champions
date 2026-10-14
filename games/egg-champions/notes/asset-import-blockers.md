# Asset import: what is blocked (2026-10-14)

Factory task 06, build steps 1 to 4. The offline parts are done and committed:
`factory/tools/build_models.py`, `assets/models.json`, `src/server/ModelLibrary.luau`
(with `src/shared/visual/ModelTemplates.luau` and its spec), `factory/tools/verify_assets.py`,
`factory/tools/opencloud.py` and the `assets` gate in `factory/tools/gate.py`.

`verify_assets.py` has not run against Roblox, so `assets/verify.json` does not exist
and `python factory/tools/gate.py games/egg-champions assets` exits 1. The Moranguete
face upload was not attempted.

## Blocker 1: the device cannot reach Open Cloud

- Endpoint: `POST https://apis.roblox.com/cloud/v2/universes/10769019206/places/101737317546942/luau-execution-session-tasks`
- Error: `curl: (56) Received HTTP code 403 from proxy after CONNECT`. The same for
  `https://apis.roblox.com/` and `https://create.roblox.com/`.
- Fix: add `apis.roblox.com` to the network allowlist of the Claude desktop (Cowork)
  workspace on the owner's computer. Nothing was done to get around the proxy.

## Blocker 2: no API key in the agent's environment

- `.env` is not visible in the repo folder the agent works in
  (`C:\Users\joaov\egg-champions`), so `ROBLOX_API_KEY` (the `api_key_secret` in
  `roblox.json`) is not set.
- Fix: put `.env` at the repo root with `ROBLOX_API_KEY=<key>`. Run the tool with
  `set -a; . ./.env; set +a; python factory/tools/verify_assets.py games/egg-champions`.
  The tool reads the key only from the environment and never opens `.env`.

## Scopes the API key needs (test universe 10769019206 only)

From create.roblox.com/docs/cloud/reference/features/luau-execution:
- `universe.place.luau-execution-session:write`: create a task, read it back, read its
  logs. This is all `verify_assets.py` needs.

For the Moranguete face upload (`AssetService:CreateAssetAsync` inside a Luau
Execution task):
- The AssetService reference says `CreatorId` and `CreatorType` are required "for Open
  Cloud Luau Execution context", so the call is meant to work there, but it names no
  API key scope, only the engine capability `AssetCreateUpdate`.
- The Open Cloud assets guide says to add the `assets` API system to the key with Read
  and Write (OAuth scope names `asset:read` and `asset:write`). Add `asset:write`
  (Assets, Write) to the key as well, in case the upload checks it.

## Limits to keep in mind (same doc)

5 minute task run time (the tool asks for `300s`), 4 MB script, 4 MB of returned JSON,
5 task creations per minute per key owner, 10 unfinished tasks per place, task kept
24 hours. `verify_assets.py --wait N` stops waiting after N seconds (exit 2) and
resumes the same task on the next run.

## Not started

- `factory/tools/upload_editable_texture.py` for Moranguete (needs blockers 1 and 2
  fixed). Plan: one task reads `workspace.MorangueteFix.RepaintNewface_source.Value`,
  the tool swaps the snippet's last line for `return imgB` wrapped with a
  `CreateAssetAsync(imgB, Enum.AssetType.Image, {Name = "Moranguete face texture",
  CreatorId = game.CreatorId, CreatorType = Enum.AssetCreatorType.User})` call, and
  runs it as a second task on the TEST place. The new id goes into the manifest's
  moranguete `texture_asset_id`.
- Brief step 5 (the Studio plugin route) and step 6 (camera rule).

## Update: the Roblox steps move to GitHub Actions

The owner chose to run them in his own repo's Actions with the repo secret
`ROBLOX_API_KEY` (see "CI" in `factory/README.md`). Blockers 1 and 2 then do
not apply. What is left: give the key the three scopes listed there, then run
the `roblox` workflow. `factory/tools/texture_jobs.py` replaces the
`upload_editable_texture` plan above.
