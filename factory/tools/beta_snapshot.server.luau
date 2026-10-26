--!strict
-- Optional read-only capture script. Not mapped into the shipping project.
-- Set BuildSha256 and player BetaSubject aliases before explicitly running.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Profiles = require(game.ServerScriptService.Server.Profiles)
local build = script:GetAttribute("BuildSha256")
assert(type(build) == "string" and #build == 64, "set the exact reviewed build SHA-256")
local session = if game.JobId ~= "" then game.JobId else script:GetAttribute("SessionId")
assert(type(session) == "string" and #session > 0, "session identity unavailable")
local subjects: { [string]: boolean } = {}
for _, player in Players:GetPlayers() do
	local subject = player:GetAttribute("BetaSubject")
	assert(type(subject) == "string" and #subject > 0, "assign a stable private BetaSubject alias")
	assert(not subjects[subject], "duplicate subject alias")
	subjects[subject] = true
	local profile = Profiles.get(player)
	assert(profile ~= nil, "profile not loaded; capture is unknown")
	print("[Beta snapshot] " .. HttpService:JSONEncode({
		capture_kind = "server",
		captured_at = DateTime.now():ToIsoDate(),
		subject = subject,
		build_sha256 = build,
		place_id = game.PlaceId,
		place_version = game.PlaceVersion,
		session_id = session,
		storage_mode = Profiles.persistenceMode(player),
		release_confirmed = false,
		profile = profile,
        offline_reward = Profiles.offlineReward(player),
        offline_max_seconds = require(game.ReplicatedStorage.Shared.Config).constants.offline_max_seconds,
	}))
end
-- This script does not request a save, release a lock, seed a profile or add
-- remotes. release_confirmed stays false until independent release evidence.
