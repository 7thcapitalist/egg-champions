--!strict
--[[
	NextGoal: what the player is saving for right now, shown in the panel on
	the right of the main screen.

	The current world is the furthest world open in this rebirth run. In it,
	the rule picks, in order:
		1. the gym is beaten (only possible in the last world): the rebirth
		   cost, which the server sends as a derived field;
		2. the gym fee is already paid: the gym itself, ready to fight;
		3. an egg of this world the player has never hatched a pet from, the
		   cheapest first, while it costs less than the gym fee;
		4. otherwise the gym fee.

	Every price comes from config or from the server. Nothing here changes the
	state it is given.
]]

local Config = require(script.Parent.Parent.Config)
local Progression = require(script.Parent.Parent.rules.Progression)

export type Kind = "egg" | "gym" | "rebirth"

export type State = {
	coins: number,
	rebirths: number,
	index: { [string]: any },
	gymsBeaten: { [string]: boolean },
	feesPaid: { [string]: boolean },
}

export type Goal = {
	kind: Kind,
	-- The egg id for an egg goal, otherwise the world id.
	id: string,
	worldIndex: number,
	title: string,
	detail: string,
	-- Coins counted toward the goal (never more than need) and the target.
	have: number,
	need: number,
	-- 0 to 1, for the progress bar.
	progress: number,
	-- True when the player can act on the goal now.
	ready: boolean,
}

local NextGoal = {}

NextGoal.kinds = table.freeze({
	egg = "egg" :: Kind,
	gym = "gym" :: Kind,
	rebirth = "rebirth" :: Kind,
})

local function asProgress(state: State): Progression.State
	return (state :: any) :: Progression.State
end

-- The furthest world open in the current run.
function NextGoal.currentWorld(state: State): Config.World
	local best: Config.World? = nil
	for _, world in Config.worlds do
		if Progression.worldUnlocked(asProgress(state), world.index) then
			if best == nil or world.index > best.index then
				best = world
			end
		end
	end
	assert(best ~= nil, "NextGoal.currentWorld: no world is open")
	return best
end

-- True when the index holds any pet that hatches from this egg.
function NextGoal.hasHatched(state: State, eggId: string): boolean
	for petId in state.index do
		local pet = Config.petById[petId]
		if pet.egg == eggId then
			return true
		end
	end
	return false
end

local function build(
	kind: Kind,
	id: string,
	world: Config.World,
	title: string,
	detail: string,
	coins: number,
	need: number,
	done: boolean
): Goal
	local progress = if done or need <= 0 then 1 else math.clamp(coins / need, 0, 1)
	return {
		kind = kind,
		id = id,
		worldIndex = world.index,
		title = title,
		detail = detail,
		have = if done then need else math.clamp(coins, 0, need),
		need = need,
		progress = progress,
		ready = done or coins >= need,
	}
end

local function gymDetail(world: Config.World): string
	local leader = Config.typeById[world.gym.leader_type].name
	local counter = Config.typeById[world.gym.counter_type].name
	return string.format("Leader uses %s pets. %s is strong against %s.", leader, counter, leader)
end

local function rebirthDetail(): string
	local percent = math.floor(Config.constants.rebirth_coin_bonus * 100 + 0.5)
	return string.format("Rebirth for +%d%% coins per click. Pets and badges stay.", percent)
end

-- The goal to show for this state. rebirthCost is the cost the server sent.
function NextGoal.pick(state: State, rebirthCost: number): Goal
	local world = NextGoal.currentWorld(state)
	local coins = state.coins
	local fee = world.gym.fee
	local gymTitle = world.name .. " Gym"

	if state.gymsBeaten[world.id] == true then
		return build(
			NextGoal.kinds.rebirth,
			world.id,
			world,
			"Rebirth",
			rebirthDetail(),
			coins,
			rebirthCost,
			false
		)
	end

	if state.feesPaid[world.id] == true then
		return build(
			NextGoal.kinds.gym,
			world.id,
			world,
			gymTitle,
			"Fee paid. Challenge the leader.",
			coins,
			fee,
			true
		)
	end

	local nextEgg: Config.Egg? = nil
	for _, eggId in world.eggs do
		local egg = Config.eggById[eggId]
		if egg.price < fee and not NextGoal.hasHatched(state, egg.id) then
			if nextEgg == nil or egg.price < nextEgg.price then
				nextEgg = egg
			end
		end
	end
	if nextEgg ~= nil then
		return build(
			NextGoal.kinds.egg,
			nextEgg.id,
			world,
			nextEgg.name,
			"Hatch it for new pets for your team.",
			coins,
			nextEgg.price,
			false
		)
	end

	return build(NextGoal.kinds.gym, world.id, world, gymTitle, gymDetail(world), coins, fee, false)
end

return NextGoal
