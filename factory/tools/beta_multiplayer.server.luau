--!strict
-- Local QA fixture only. Two client drivers send real InvokeServer requests.
-- This does not certify disconnect/rejoin, internet latency or persistence.
local RunService = game:GetService("RunService")
assert(RunService:IsStudio() and game.PlaceId == 0, "local unpublished QA only")
assert(game.ServerScriptService:GetAttribute("BetaQA") == true, "QA project guard missing")
assert(game.ServerScriptService:GetAttribute("PlaytestNoPasses") == true, "passes guard missing")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game.ServerScriptService:WaitForChild("Server")
local Profiles = require(Server:WaitForChild("Profiles"))
local Guard = require(Server:WaitForChild("Guard"))
local GymService = require(Server.Services:WaitForChild("GymService"))
local Config = require(ReplicatedStorage.Shared.Config)
local Profile = require(ReplicatedStorage.Shared.rules.Profile)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Requests = require(ReplicatedStorage.Shared.net.Requests)
local driver = Instance.new("RemoteFunction")
driver.Name = "BetaDriver"
driver.Parent = ReplicatedStorage
local readyRemote = Instance.new("RemoteEvent")
readyRemote.Name = "BetaReady"
local ready: { [Player]: boolean } = {}
readyRemote.OnServerEvent:Connect(function(player: Player)
	ready[player] = true
end)
readyRemote.Parent = ReplicatedStorage
local report: any = {
	mode = "real-clients",
	environment = "local-studio",
	cases = {},
	subjects = { "qa-a", "qa-b" },
	build_sha256 = game.ServerScriptService:GetAttribute("BetaBuildSha256") or "unknown",
}
local function check(id: string, condition: boolean)
	table.insert(report.cases, { id = id, status = if condition then "passed" else "failed" })
	assert(condition, "beta fixture failed: " .. id)
end
local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, inner in value do
		result[key] = copy(inner)
	end
	return result
end
local function equal(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for key, value in a do
		if not equal(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end
local ok, err = pcall(function()
	local deadline = os.clock() + 60
	local players: { Player } = {}
	repeat
		players = Players:GetPlayers()
		if
			#players >= 2
			and Profiles.get(players[1])
			and Profiles.get(players[2])
			and ready[players[1]]
			and ready[players[2]]
		then
			break
		end
		task.wait(0.2)
	until os.clock() >= deadline
	assert(#players >= 2, "start a local server with at least two clients")
	table.sort(players, function(a, b)
		return a.UserId < b.UserId
	end)
	local a, b = players[1], players[2]
	assert(ready[a] and ready[b], "both client drivers must be ready")
	-- Refuse seeding if either profile could be written to a real save store.
	assert(
		Profiles.persistenceMode(a) == "temporary" and Profiles.persistenceMode(b) == "temporary",
		"fixture requires temporary profiles; no persistent profiles may be seeded"
	)
	local pa, pb = Profiles.get(a), Profiles.get(b)
	assert(pa ~= nil and pb ~= nil, "profiles unavailable")
	assert(
		#pa.pets == 0 and #pb.pets == 0 and pa.coins == 0 and pb.coins == 0,
		"fresh local profiles required; existing progress will not be overwritten"
	)
	local world = Config.worlds[1]
	local worldId = world.id
	for i, player in { a, b } do
		local profile = Profiles.get(player)
		assert(profile ~= nil, "profile missing")
		profile.coins = world.gym.fee * 2
		for slot = 1, Config.constants.team_size do
			local uid = "beta-" .. i .. "-" .. slot
			table.insert(profile.pets, { uid = uid, petId = Config.pets[1].id })
			table.insert(profile.team, uid)
		end
		assert(#Profile.validate(profile) == 0, "invalid fixture profile")
		Guard.push(player)
	end
	local function invoke(player: Player, name: string, ...: any): any
		local args = { ... }
		local finished, succeeded, result = false, false, nil
		task.spawn(function()
			succeeded, result = pcall(function()
				return driver:InvokeClient(player, name, args)
			end)
			finished = true
		end)
		local untilTime = os.clock() + 8
		repeat
			task.wait(0.05)
		until finished or os.clock() >= untilTime
		assert(
			finished and succeeded and type(result) == "table",
			"client request failed/timed out: " .. name
		)
		return result
	end
	local beforeB = copy(pb)
	assert(invoke(a, Remotes.names.PayGymFee, worldId).ok, "A fee failed")
	local secondFee = invoke(a, Remotes.names.PayGymFee, worldId)
	check(
		"fee-once",
		secondFee.ok == false
			and secondFee.reason == "fee_already_paid"
			and pa.coins == world.gym.fee
	)
	local sa = invoke(a, Remotes.names.StartBattle, worldId)
	assert(sa.ok, "A start failed")
	check("profile-isolation", equal(pb, beforeB))
	local duplicate = invoke(a, Remotes.names.StartBattle, worldId)
	check("duplicate-start", duplicate.ok == false and duplicate.reason == "already_in_battle")
	assert(invoke(b, Remotes.names.PayGymFee, worldId).ok, "B fee failed")
	local foreignPet = invoke(b, Remotes.names.Equip, pa.pets[1].uid)
	check("foreign-pet", foreignPet.ok == false and foreignPet.reason == "not_owned")
	local sb = invoke(b, Remotes.names.StartBattle, worldId)
	check(
		"parallel-battles",
		sb.ok == true
			and sa.sessionId ~= sb.sessionId
			and GymService.inBattle(a)
			and GymService.inBattle(b)
	)
	check("remote-transport", sa.ok == true and sb.ok == true)
	local foreign = invoke(b, Remotes.names.BattleMove, sa.sessionId, 1)
	check("foreign-session", foreign.ok == false and foreign.reason == Requests.reasons.notOwner)
	assert(invoke(a, Remotes.names.GiveUp, sa.sessionId).ok, "A give up failed")
	local refused = invoke(a, Remotes.names.StartBattle, worldId)
	check(
		"retry-isolation",
		refused.ok == false
			and refused.reason == "retry_wait"
			and pb.gymRetryAt[worldId] == nil
			and GymService.inBattle(b)
	)
	local limited = false
	for _ = 1, 25 do
		local result = invoke(a, Remotes.names.BattleMove, sa.sessionId, 99)
		limited = limited or result.reason == Requests.reasons.rateLimited
	end
	local moveB = invoke(b, Remotes.names.BattleMove, sb.sessionId, 1)
	check("rate-limit-isolation", limited and moveB.ok == true)
	table.insert(report.cases, { id = "disconnect-rejoin", status = "unknown" })
end)
report.status = if ok then "fixture-passed-beta-pending" else "blocked"
report.error = if ok then nil else tostring(err)
print("[Beta multiplayer] " .. HttpService:JSONEncode(report))
if not ok then
	warn("[Beta multiplayer] blocked: " .. tostring(err))
end
