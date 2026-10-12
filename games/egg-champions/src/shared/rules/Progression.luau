--!strict
--[[
	Progression: which worlds are open, which gyms are beaten, which badges a
	player holds.

	The progress state is a plain table:
		coins: number
		rebirths: number
		pets: owned pets, as later tasks define them
		team: equipped pet uids
		index: the pet index (see PetIndex)
		badges: { [worldId] = true }, kept forever, even through rebirth
		gymsBeaten: { [worldId] = true }, wins in the current rebirth run
		feesPaid: { [worldId] = true }, gym fees paid in the current run

	World 1 is always open. World N is open when the gym of world N-1 is beaten
	in the current run, so a rebirth (which clears gymsBeaten) locks the worlds
	again while the badges stay.
]]

local Config = require(script.Parent.Parent.Config)
local Coins = require(script.Parent.Coins)

export type Flags = { [string]: boolean }

export type State = {
	coins: number,
	rebirths: number,
	pets: { any },
	team: { string },
	index: Coins.PetIndex,
	badges: Flags,
	gymsBeaten: Flags,
	feesPaid: Flags,
}

local Progression = {}

-- A fresh state: no coins, no rebirths, nothing owned or beaten.
function Progression.newState(): State
	return {
		coins = 0,
		rebirths = 0,
		pets = {},
		team = {},
		index = {},
		badges = {},
		gymsBeaten = {},
		feesPaid = {},
	}
end

local function firstWorldIndex(): number
	local lowest = math.huge
	for _, world in Config.worlds do
		lowest = math.min(lowest, world.index)
	end
	return lowest
end

local function lastWorldIndex(): number
	local highest = -math.huge
	for _, world in Config.worlds do
		highest = math.max(highest, world.index)
	end
	return highest
end

function Progression.isGymBeaten(state: State, worldIndex: number): boolean
	local world = Config.worldByIndex[worldIndex]
	return state.gymsBeaten[world.id] == true
end

function Progression.hasBadge(state: State, worldIndex: number): boolean
	local world = Config.worldByIndex[worldIndex]
	return state.badges[world.id] == true
end

function Progression.worldUnlocked(state: State, worldIndex: number): boolean
	local _ = Config.worldByIndex[worldIndex]
	if worldIndex == firstWorldIndex() then
		return true
	end
	return Progression.isGymBeaten(state, worldIndex - 1)
end

-- An egg is buyable only when its world is open.
function Progression.eggUnlocked(state: State, eggId: string): boolean
	local egg = Config.eggById[eggId]
	local world = Config.worldById[egg.world]
	return Progression.worldUnlocked(state, world.index)
end

-- Records a gym win in the current run and awards the badge. Beating the gym
-- opens the next world through worldUnlocked. Returns true when the badge is
-- new; a badge already held is neither lost nor duplicated.
function Progression.beatGym(state: State, worldIndex: number): boolean
	local world = Config.worldByIndex[worldIndex]
	state.gymsBeaten[world.id] = true
	if state.badges[world.id] == true then
		return false
	end
	state.badges[world.id] = true
	return true
end

-- True when the gym of the last world is beaten in the current run. Drives the
-- "World 4 coming soon" gate.
function Progression.isFinalGymBeaten(state: State): boolean
	return Progression.isGymBeaten(state, lastWorldIndex())
end

return Progression
