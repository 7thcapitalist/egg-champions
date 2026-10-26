--!strict
-- Fixture-only Studio script. build_playtest.py injects this into the QA
-- project; the shipping default.project.json does not map it.
local RunService = game:GetService("RunService")
assert(
	RunService:IsStudio() and game.PlaceId == 0,
	"PlaytestScenario requires a local unpublished Studio place"
)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
assert(ServerScriptService:GetAttribute("PlaytestNoPasses") == true, "QA passes guard is missing")

local data = require(ReplicatedStorage:WaitForChild("PlaytestScenario"))
local Server = ServerScriptService:WaitForChild("Server")
local Profiles = require(Server:WaitForChild("Profiles"))
local Guard = require(Server:WaitForChild("Guard"))
local Profile =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("rules"):WaitForChild("Profile"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Layout = require(Shared:WaitForChild("world"):WaitForChild("Layout"))
local portalResults: { [Player]: { from: string, to: string?, moved: boolean, after: Vector3 } } =
	{}

if data.scenario == "portals" then
	local Portals = require(Server:WaitForChild("World"):WaitForChild("Portals"))
	local originalTryEnter = Portals.tryEnter
	Portals.tryEnter = function(player: Player, site: any, built: any): boolean
		local portal = site.portal
		local profile = Profiles.get(player)
		local character = player.Character
		local before = if character ~= nil then character:GetPivot().Position else Vector3.zero
		print(
			string.format(
				"[Playtest portals] tryEnter from=%s to=%s unlockedPrevious=%s before=%s",
				portal.worldId,
				tostring(portal.toWorldId),
				tostring(profile ~= nil and profile.gymsBeaten[portal.worldId] == true),
				tostring(before)
			)
		)
		local moved = originalTryEnter(player, site, built)
		local after = if character ~= nil then character:GetPivot().Position else Vector3.zero
		portalResults[player] =
			{ from = portal.worldId, to = portal.toWorldId, moved = moved, after = after }
		print(
			string.format(
				"[Playtest portals] tryEnter result from=%s moved=%s after=%s",
				portal.worldId,
				tostring(moved),
				tostring(after)
			)
		)
		return moved
	end
end

local function portalFor(worldId: string): (Model, BasePart)
	for _, tagged in CollectionService:GetTagged("Portal") do
		if tagged:IsA("Model") and tagged:GetAttribute("WorldId") == worldId then
			local trigger = tagged:FindFirstChild("Trigger")
			assert(trigger ~= nil and trigger:IsA("BasePart"), "portal has no Trigger: " .. worldId)
			return tagged, trigger :: BasePart
		end
	end
	error("missing tagged portal for " .. worldId)
end

local function nearArrival(position: Vector3, arrival: Layout.Vec): boolean
	local target = Vector3.new(arrival.x, arrival.y, arrival.z)
	local flat = Vector3.new(position.X - target.X, 0, position.Z - target.Z)
	return flat.Magnitude <= 12 and math.abs(position.Y - target.Y) <= 12
end

local function readyCharacter(player: Player): (Model, Humanoid, BasePart)
	local deadline = os.clock() + 15
	local stableSince: number? = nil
	while os.clock() < deadline do
		local character = player.Character
		local humanoid = if character ~= nil
			then character:FindFirstChildOfClass("Humanoid")
			else nil
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		if
			character ~= nil
			and character:IsDescendantOf(Workspace)
			and humanoid ~= nil
			and humanoid.Health > 0
			and root ~= nil
			and root:IsA("BasePart")
			and root:IsDescendantOf(Workspace)
		then
			if stableSince == nil then
				stableSince = os.clock()
			elseif os.clock() - stableSince >= 0.3 then
				return character, humanoid, root
			end
		else
			stableSince = nil
		end
		task.wait(0.1)
	end
	error("character was not alive and parented to Workspace within 15 seconds")
end

-- Move the real character through the real Touched trigger. This checks the
-- physical hookup as well as the profile lock, without invoking Portals API.
local function crossPortal(player: Player, worldId: string, destination: Layout.Vec?): boolean
	local character, humanoid, root = readyCharacter(player)
	local prior = portalResults[player]
	if
		destination ~= nil
		and prior ~= nil
		and prior.from == worldId
		and prior.moved
		and nearArrival(root.Position, destination)
	then
		-- The production handler is reached only through its Touched hook.
		-- Preserve an already accepted physical crossing instead of moving
		-- the character back to the source portal for another attempt.
		task.wait(0.3)
		assert(nearArrival(root.Position, destination), "early portal arrival was not stable")
		print("[Playtest portals] " .. worldId .. " already transported by a physical touch")
		return true
	end
	local model, trigger = portalFor(worldId)
	local step = model:FindFirstChild("Step")
	assert(step ~= nil and step:IsA("BasePart"), "portal has no Step: " .. worldId)
	local front = model:GetPivot().LookVector
	-- The cylinder's X size is its thickness along the walking direction;
	-- Y is its visual diameter. Start inside the arch, clear of its plane.
	local offset = trigger.Size.X / 2 + root.Size.Z / 2 + 1.5
	local rootY = step.Position.Y + step.Size.Y / 2 + humanoid.HipHeight + root.Size.Y / 2
	local start = Vector3.new(trigger.Position.X, rootY, trigger.Position.Z) + front * offset
	local finish = Vector3.new(trigger.Position.X, rootY, trigger.Position.Z) - front * offset
	-- Studio's local player normally owns character physics. Give this brief
	-- scripted crossing to the server so client controls cannot cancel it.
	local owned, ownershipError = pcall(function()
		root:SetNetworkOwner(nil)
	end)
	assert(owned, "server could not own character physics: " .. tostring(ownershipError))
	local touched = false
	portalResults[player] = nil
	local connection = trigger.Touched:Connect(function(hit: BasePart)
		if hit:IsDescendantOf(character) then
			touched = true
		end
	end)
	humanoid:MoveTo(root.Position)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(CFrame.lookAt(start, finish))
	print(
		string.format(
			"[Playtest portals] %s trigger=%s size=%s start=%s finish=%s front=%s",
			worldId,
			tostring(trigger.Position),
			tostring(trigger.Size),
			tostring(start),
			tostring(finish),
			tostring(front)
		)
	)
	humanoid:MoveTo(finish)
	local started = os.clock()
	local arrived = false
	while os.clock() - started < 8 do
		local observed = portalResults[player]
		if
			destination ~= nil
			and observed ~= nil
			and observed.from == worldId
			and observed.moved
		then
			break
		end
		if
			destination == nil
			and touched
			and (root.Position - trigger.Position):Dot(front) < -1
		then
			break
		end
		root.AssemblyLinearVelocity = -front * 12
		RunService.Heartbeat:Wait()
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	humanoid:MoveTo(root.Position)
	humanoid:Move(Vector3.zero)
	local observed = portalResults[player]
	if destination ~= nil and observed ~= nil and observed.from == worldId and observed.moved then
		local deadline = os.clock() + 2
		local stable = 0
		while os.clock() < deadline do
			local rootNear = nearArrival(root.Position, destination)
			local pivotNear = nearArrival(character:GetPivot().Position, destination)
			if rootNear and pivotNear then
				stable += 1
				if stable >= 3 then
					arrived = true
					break
				end
			else
				stable = 0
			end
			RunService.Heartbeat:Wait()
		end
	end
	connection:Disconnect()
	local expected = if destination ~= nil
		then tostring(Vector3.new(destination.x, destination.y, destination.z))
		else "refusal"
	print(
		string.format(
			"[Playtest portals] %s result touched=%s handlerMoved=%s arrived=%s root=%s pivot=%s expected=%s elapsed=%.2f",
			worldId,
			tostring(touched),
			tostring(observed ~= nil and observed.moved),
			tostring(arrived),
			tostring(root.Position),
			tostring(character:GetPivot().Position),
			expected,
			os.clock() - started
		)
	)
	assert(touched, "portal Trigger was not physically touched: " .. worldId)
	if destination ~= nil then
		assert(
			observed ~= nil and observed.from == worldId and observed.moved,
			"portal handler did not accept transport: " .. worldId
		)
		assert(arrived, "portal did not arrive at its target world: " .. worldId)
	else
		assert(
			observed ~= nil and observed.from == worldId and not observed.moved,
			"portal handler did not refuse: " .. worldId
		)
		assert(
			(root.Position - trigger.Position).Magnitude <= offset * 2 + 8,
			"refused portal unexpectedly transported: " .. worldId
		)
	end
	return touched
end

local function runPortals(player: Player, profile: any)
	local plan = Layout.plan(Config.worlds)
	local ordered = table.clone(Config.worlds)
	table.sort(ordered, function(a, b)
		return a.index < b.index
	end)
	assert(#ordered >= 2, "portal QA needs at least two worlds")
	local first = ordered[1]
	local second = ordered[2]
	local firstModel = portalFor(first.id)
	assert(
		firstModel:GetAttribute("ToIndex") == second.index,
		"first portal target does not match config"
	)
	print("[Playtest portals] locked " .. first.id .. " -> " .. second.id .. ": crossing trigger")
	crossPortal(player, first.id, nil)
	assert(
		not nearArrival((player.Character :: Model):GetPivot().Position, plan.arrivals[second.id]),
		"locked portal moved player"
	)
	print("[Playtest portals] PASS locked first portal touched, no transport")
	-- Move well away before the retry. Limbs can keep touching the trigger
	-- and refreshing Portals' 2-second debounce while standing beside it.
	local spawn = plan.arrivals[first.id]
	local character = player.Character :: Model
	character:PivotTo(CFrame.new(spawn.x, spawn.y + 4, spawn.z))
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid ~= nil and root ~= nil and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		humanoid:MoveTo(root.Position)
		humanoid:Move(Vector3.zero)
	end
	task.wait(2.3)
	profile.gymsBeaten = data.unlockWorlds
	profile.badges = table.clone(data.unlockWorlds)
	assert(#Profile.validate(profile) == 0, "unlocked portal profile invalid")
	Guard.push(player)
	print("[Playtest portals] unlocked prior gyms; testing next-world portals")
	for index = 1, #ordered - 1 do
		local from = ordered[index]
		local to = ordered[index + 1]
		task.wait(2.2) -- Portals' touch debounce is 2 seconds.
		crossPortal(player, from.id, plan.arrivals[to.id])
		print("[Playtest portals] PASS " .. from.id .. " -> " .. to.id .. " arrival")
	end
	task.wait(2.2)
	local last = ordered[#ordered]
	local lastModel = portalFor(last.id)
	assert(lastModel:GetAttribute("ToIndex") == nil, "last portal is not coming soon")
	crossPortal(player, last.id, nil)
	print("[Playtest portals] PASS coming soon portal touched, no transport")
end

local function seed(player: Player)
	local profile = Profiles.get(player)
	local deadline = os.clock() + 30
	while profile == nil and player.Parent ~= nil and os.clock() < deadline do
		task.wait(0.1)
		profile = Profiles.get(player)
	end
	if profile == nil or player.Parent == nil then
		warn("[Playtest] no temporary profile for " .. player.Name)
		return
	end
	assert(RunService:IsStudio() and game.PlaceId == 0, "QA scenario cannot seed a published place")
	if data.scenario ~= "beginner" then
		profile.coins = data.coins
		profile.rebirths = data.rebirths
		profile.pets = data.pets
		profile.team = data.team
		profile.index = data.index
		profile.badges = data.badges
		profile.gymsBeaten = data.gymsBeaten
		profile.feesPaid = {}
		profile.gymRetryAt = {}
		profile.tutorialStep = data.tutorialStep
	end
	assert(#Profile.validate(profile) == 0, "QA scenario produced an invalid profile")
	player:SetAttribute("PlaytestScenario", data.scenario)
	Guard.push(player)
	print(
		string.format(
			"[Playtest] %s ready for %s; coins=%d pets=%d rebirths=%d",
			data.scenario,
			player.Name,
			profile.coins,
			#profile.pets,
			profile.rebirths
		)
	)
	if data.scenario == "portals" then
		task.spawn(function()
			local originalWalkSpeed: number? = nil
			local ok, err = pcall(function()
				local _, humanoid, root = readyCharacter(player)
				originalWalkSpeed = humanoid.WalkSpeed
				humanoid.WalkSpeed = 0
				root:SetNetworkOwner(nil)
				runPortals(player, profile)
			end)
			if not ok then
				warn("[Playtest portals] FAIL " .. tostring(err))
			end
			local character = player.Character
			if character ~= nil and character.Parent ~= nil then
				local spawn = Workspace:FindFirstChildOfClass("SpawnLocation")
				if spawn ~= nil then
					character:PivotTo(spawn.CFrame * CFrame.new(0, 5, 0))
				end
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				local root = character:FindFirstChild("HumanoidRootPart")
				if humanoid ~= nil and root ~= nil and root:IsA("BasePart") then
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
					humanoid:MoveTo(root.Position)
					humanoid:Move(Vector3.zero)
					if originalWalkSpeed ~= nil then
						humanoid.WalkSpeed = originalWalkSpeed
					end
					pcall(function()
						root:SetNetworkOwnershipAuto()
					end)
				end
			end
			print("[Playtest portals] finished; character returned to spawn")
		end)
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(seed, player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(seed, player)
end
print("[Playtest] local QA fixture active: " .. data.scenario)
