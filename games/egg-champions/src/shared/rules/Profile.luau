--!strict
--[[
	Profile: the shape of one player's saved progress, how an older save is
	upgraded, and how a loaded save is checked before it is trusted.

	A profile is a plain table:
		version: the schema version this table follows
		coins: number
		pets: owned pets, a list of { uid, petId, variant }
		team: equipped pet uids, in equip order
		index: the pet index (see PetIndex)
		badges: { [worldId] = true }, kept forever, even through rebirth
		rebirths: number
		gymsBeaten: { [worldId] = true }, wins in the current rebirth run
		feesPaid: { [worldId] = true }, gym fees paid in the current run
		gymRetryAt: { [worldId] = unix seconds }, when the next gym attempt
			is allowed after a loss (see Gym.recordLoss). Kept through rebirth.
		playSeconds: total seconds played over every earlier session, kept
			through rebirth. The server adds the current session's time on
			every save and when the player leaves (see Profile.playSecondsAfter).
		tutorialStep: the first-time tutorial step (see Tutorial), kept
			through rebirth.

	Schema versions:
		1: coins, pets, team, index, badges, rebirths.
		2: adds gymsBeaten and feesPaid (task 06 progression).
		3: adds gymRetryAt, so a gym retry wait survives leaving and rejoining.
		4: adds playSeconds, so analytics can report total play time.
		5: adds tutorialStep. An older save gets Tutorial.initialFor, so a
		   player who already owns a pet skips the first three steps.

	The version is a storage format number, not a game number, so it lives here
	rather than in config. Every function leaves its input untouched.
]]

local Config = require(script.Parent.Parent.Config)
local Progression = require(script.Parent.Progression)
local Tutorial = require(script.Parent.Tutorial)
local Prisms = require(script.Parent.Prisms)

export type OwnedPet = {
	uid: string,
	petId: string,
	variant: string?,
}

export type Profile = {
	version: number,
	coins: number,
	pets: { OwnedPet },
	team: { string },
	index: { [string]: any },
	badges: Progression.Flags,
	rebirths: number,
	gymsBeaten: Progression.Flags,
	feesPaid: Progression.Flags,
	gymRetryAt: { [string]: number },
	playSeconds: number,
	tutorialStep: number,
	prisms: { [string]: number },
	paidPrisms: { [string]: number },
	purchaseReceipts: { [string]: boolean },
}

export type ProblemKind =
	"negative_coins"
	| "bad_coins"
	| "unknown_pet"
	| "unknown_variant"
	| "duplicate_pet"
	| "team_too_long"
	| "team_not_owned"
	| "team_duplicate"
	| "bad_tutorial_step"
	| "bad_prisms"
	| "bad_receipts"

export type Problem = {
	kind: ProblemKind,
	detail: string,
	repairable: boolean,
}

local CURRENT_VERSION = 6

local Profile = {}

Profile.version = CURRENT_VERSION

Profile.problems = table.freeze({
	negativeCoins = "negative_coins" :: ProblemKind,
	badCoins = "bad_coins" :: ProblemKind,
	unknownPet = "unknown_pet" :: ProblemKind,
	unknownVariant = "unknown_variant" :: ProblemKind,
	duplicatePet = "duplicate_pet" :: ProblemKind,
	teamTooLong = "team_too_long" :: ProblemKind,
	teamNotOwned = "team_not_owned" :: ProblemKind,
	teamDuplicate = "team_duplicate" :: ProblemKind,
	badTutorialStep = "bad_tutorial_step" :: ProblemKind,
})

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value do
		copy[deepCopy(key)] = deepCopy(inner)
	end
	return copy
end

-- The empty profile a brand new player starts with.
-- True when a save store error means Studio has no access to API services:
-- Roblox's "StudioAccessToApisNotAllowed", "API access is not enabled", or
-- an error that starts with "403:". Retrying can not fix these.
function Profile.isNoAccessError(err: any): boolean
	local text = tostring(err)
	return string.find(text, "StudioAccessToApisNotAllowed", 1, true) ~= nil
		or string.find(text, "API access is not enabled", 1, true) ~= nil
		or string.sub(text, 1, 4) == "403:"
end

function Profile.new(): Profile
	local state = Progression.newState()
	return {
		version = CURRENT_VERSION,
		coins = state.coins,
		pets = {},
		team = {},
		index = state.index,
		badges = state.badges,
		rebirths = state.rebirths,
		gymsBeaten = state.gymsBeaten,
		feesPaid = state.feesPaid,
		gymRetryAt = {},
		playSeconds = 0,
		tutorialStep = Tutorial.steps.click,
		prisms = Prisms.initial(true),
		paidPrisms = Prisms.initial(false),
		purchaseReceipts = {},
	}
end

-- One step per version: steps[n] turns a version n table into version n + 1.
local steps: { [number]: (any) -> any } = {
	[5] = function(data: any): any
		data.prisms = data.prisms or Prisms.initial(true)
		data.paidPrisms = data.paidPrisms or Prisms.initial(false)
		data.purchaseReceipts = data.purchaseReceipts or {}
		data.version = 6
		return data
	end,
	[1] = function(data: any): any
		data.gymsBeaten = data.gymsBeaten or {}
		data.feesPaid = data.feesPaid or {}
		data.version = 2
		return data
	end,
	[2] = function(data: any): any
		data.gymRetryAt = data.gymRetryAt or {}
		data.version = 3
		return data
	end,
	[3] = function(data: any): any
		data.playSeconds = if type(data.playSeconds) == "number" then data.playSeconds else 0
		data.version = 4
		return data
	end,
	[4] = function(data: any): any
		data.tutorialStep = Tutorial.initialFor(data)
		data.version = 5
		return data
	end,
}

-- Total play time: the playSeconds a profile held when this session began,
-- plus whole seconds of the current session. A bad or negative session time
-- adds nothing, so total play time never goes down.
function Profile.playSecondsAfter(baseSeconds: number, sessionSeconds: number): number
	local base = if type(baseSeconds) == "number" and baseSeconds == baseSeconds
		then math.max(0, baseSeconds)
		else 0
	local session = if type(sessionSeconds) == "number"
			and sessionSeconds == sessionSeconds
			and sessionSeconds ~= math.huge
		then math.max(0, math.floor(sessionSeconds))
		else 0
	return base + session
end

-- Upgrades saved data to the current version and returns a new table.
-- Errors on anything it cannot read: a missing, unknown or newer version is
-- refused, never reset, because losing a save is worse than not loading it.
function Profile.migrate(data: any): Profile
	if type(data) ~= "table" then
		error("Profile.migrate: saved data is not a table (got " .. typeof(data) .. ")", 2)
	end
	local version = data.version
	if type(version) ~= "number" or version ~= math.floor(version) or version < 1 then
		error("Profile.migrate: unknown profile version " .. tostring(version), 2)
	end
	if version > CURRENT_VERSION then
		error(
			string.format(
				"Profile.migrate: profile version %d is newer than this server's version %d",
				version,
				CURRENT_VERSION
			),
			2
		)
	end
	local upgraded = deepCopy(data)
	while upgraded.version < CURRENT_VERSION do
		local step = steps[upgraded.version]
		if step == nil then
			error("Profile.migrate: no upgrade from version " .. tostring(upgraded.version), 2)
		end
		upgraded = step(upgraded)
	end
	return upgraded :: Profile
end

local knownPets: { [string]: boolean } = {}
for _, pet in Config.pets do
	knownPets[pet.id] = true
end

local knownVariants: { [string]: boolean } = {}
for _, variant in Config.variants do
	knownVariants[variant.id] = true
end

-- Every problem with a profile, in a fixed order. An empty list means the
-- profile can be trusted as it is.
function Profile.validate(profile: Profile): { Problem }
	local problems: { Problem } = {}
	local function report(kind: ProblemKind, detail: string, repairable: boolean)
		table.insert(problems, { kind = kind, detail = detail, repairable = repairable })
	end

	if type(profile.coins) ~= "number" or profile.coins ~= profile.coins then
		report(Profile.problems.badCoins, "coins is " .. tostring(profile.coins), false)
	elseif profile.coins < 0 then
		report(Profile.problems.negativeCoins, "coins is " .. tostring(profile.coins), false)
	end

	for _, field in { "prisms", "paidPrisms" } do
		local stock = (profile :: any)[field]
		if type(stock) ~= "table" then
			report("bad_prisms", field .. " is not a table", false)
		else
			for id, count in stock do
				if
					not Prisms.definition(id)
					or type(count) ~= "number"
					or count ~= count
					or count == math.huge
					or count < 0
					or count ~= math.floor(count)
				then
					report("bad_prisms", field .. " contains an invalid balance", false)
				end
			end
			for _, p in Config.prisms do
				if stock[p.id] == nil then
					report("bad_prisms", "missing " .. p.id, false)
				end
			end
		end
	end
	if type(profile.purchaseReceipts) ~= "table" then
		report("bad_receipts", "receipts is not a table", false)
	else
		for id, received in profile.purchaseReceipts do
			if type(id) ~= "string" or #id == 0 or received ~= true then
				report("bad_receipts", "invalid receipt", false)
			end
		end
	end
	local owned: { [string]: boolean } = {}
	for position, pet in profile.pets do
		if knownPets[pet.petId] ~= true then
			report(
				Profile.problems.unknownPet,
				string.format("pets[%d] has unknown petId %s", position, tostring(pet.petId)),
				false
			)
		end
		if pet.variant ~= nil and knownVariants[pet.variant] ~= true then
			report(
				Profile.problems.unknownVariant,
				string.format("pets[%d] has unknown variant %s", position, tostring(pet.variant)),
				false
			)
		end
		if owned[pet.uid] then
			report(
				Profile.problems.duplicatePet,
				string.format("pets[%d] repeats uid %s", position, tostring(pet.uid)),
				false
			)
		end
		owned[pet.uid] = true
	end

	local teamSize = Config.constants.team_size
	if #profile.team > teamSize then
		report(
			Profile.problems.teamTooLong,
			string.format("team has %d pets, the limit is %d", #profile.team, teamSize),
			true
		)
	end
	local equipped: { [string]: boolean } = {}
	for position, uid in profile.team do
		if owned[uid] ~= true then
			report(
				Profile.problems.teamNotOwned,
				string.format(
					"team[%d] is uid %s, which the player does not own",
					position,
					tostring(uid)
				),
				true
			)
		elseif equipped[uid] then
			report(
				Profile.problems.teamDuplicate,
				string.format("team[%d] repeats uid %s", position, tostring(uid)),
				true
			)
		end
		equipped[uid] = true
	end

	if not Tutorial.isStep(profile.tutorialStep) then
		report(
			Profile.problems.badTutorialStep,
			"tutorialStep is " .. tostring(profile.tutorialStep),
			true
		)
	end

	return problems
end

-- Fixes what can be fixed without losing anything the player earned: drops
-- team entries that are not owned or repeated, then trims the team to
-- team_size, and works out a broken tutorial step again. Returns a new profile and the problems that remain, which are
-- the ones that must not be trusted.
function Profile.repair(profile: Profile): (Profile, { Problem })
	local fixed: Profile = deepCopy(profile)
	local owned: { [string]: boolean } = {}
	for _, pet in fixed.pets do
		owned[pet.uid] = true
	end
	local team: { string } = {}
	local equipped: { [string]: boolean } = {}
	for _, uid in fixed.team do
		if owned[uid] == true and not equipped[uid] and #team < Config.constants.team_size then
			table.insert(team, uid)
			equipped[uid] = true
		end
	end
	fixed.team = team
	if not Tutorial.isStep(fixed.tutorialStep) then
		fixed.tutorialStep = Tutorial.initialFor(fixed :: any)
	end
	return fixed, Profile.validate(fixed)
end

return Profile
