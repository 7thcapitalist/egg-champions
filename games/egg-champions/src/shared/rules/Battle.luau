--!strict
--[[
	Battle: the whole turn-based gym battle as pure rules.

	A battle is a plain state table plus an injected rng. Battle.start builds
	the state, Battle.takeTurn resolves one full turn from the player's move
	choice and returns the next state and the list of events that happened, and
	Battle.isOver names the winner. Nothing here touches the engine, so a
	battle can be replayed and tested headless.

	Rules, all numbers from Config:
	- Move 1 is the basic attack of the pet's type at basic_move_power, usable
	  every turn. Move 2 is the pet's special. After a special the pet cannot
	  use it for special_cooldown_turns turns.
	- damage = Attack x (power / basic_move_power) x TypeBonus x Random, with
	  TypeBonus from type_bonus_strong, type_bonus_weak or 1, and Random drawn
	  between damage_random_min and damage_random_max. There is no defense.
	- The faster active pet acts first. Ties go to the player. A pet that
	  faints before its action does not act.
	- The leader uses its special when ready, otherwise the basic attack.
	- When a pet faints, the next one in its team comes in at the end of the
	  turn. A side with no pets left loses.
	- Player pets get stat x (1 + rebirth_battle_bonus x rebirths) and their
	  variant battle_mult on HP and Attack. Leader pets get neither.

	These rules match the battle in factory/tools/simulate_economy.py, which
	tuned the gym leaders, so a gym plays at the win rate the tuner recorded.
	HP and damage are kept as exact numbers; the client rounds for display.

	The rng is anything with the Random:NextNumber() shape returning a number
	in [0, 1). Hatch.seededRng gives a pure Luau one for tests.
]]

local Config = require(script.Parent.Parent.Config)

export type Rng = {
	NextNumber: (self: any, ...any) -> number,
}

export type SideId = "player" | "leader"

-- What a team member brings into battle, before rebirth and variant bonuses.
export type FighterSpec = {
	pet: string?,
	variant: string?,
	type: string,
	hp: number,
	attack: number,
	speed: number,
	special: string,
	offType: string?,
}

export type Fighter = {
	pet: string?,
	variant: string?,
	type: string,
	maxHp: number,
	hp: number,
	attack: number,
	speed: number,
	special: string,
	offType: string?,
	-- Turns left before the special can be used again. 0 means ready.
	cooldown: number,
	-- The multiplier for the next hit taken, set by Guard, or nil.
	guard: number?,
}

export type Side = {
	fighters: { Fighter },
	active: number,
}

export type State = {
	player: Side,
	leader: Side,
	turn: number,
	rebirths: number,
	rng: Rng,
}

-- One thing that happened in a turn, with every number already resolved.
-- side is the side the event is about; pet is that side's team position.
export type Event = {
	kind: "attack" | "damage" | "heal" | "guard" | "rush" | "faint" | "switch" | "win" | "lose",
	side: SideId,
	pet: number?,
	move: number?,
	special: string?,
	moveType: string?,
	power: number?,
	amount: number?,
	hp: number?,
	maxHp: number?,
	typeBonus: number?,
	guarded: boolean?,
	speed: number?,
	value: number?,
}

local Battle = {}

Battle.BASIC = 1
Battle.SPECIAL = 2

local function constants(): Config.Constants
	return Config.constants
end

-- Damage

function Battle.typeBonus(moveType: string, targetType: string): number
	local moveRow = Config.typeById[moveType]
	if moveRow.strong_against == targetType then
		return constants().type_bonus_strong
	end
	if moveRow.weak_against == targetType then
		return constants().type_bonus_weak
	end
	return 1
end

local function drawRandom(rng: Rng): number
	local u = rng:NextNumber()
	if type(u) ~= "number" or u < 0 or u >= 1 then
		error("Battle: rng:NextNumber() must return a number in [0, 1), got " .. tostring(u))
	end
	local low = constants().damage_random_min
	local high = constants().damage_random_max
	return low + (high - low) * u
end

-- The spec formula. attacker needs attack; defender needs type.
function Battle.damage(
	attacker: { attack: number },
	defender: { type: string },
	power: number,
	moveType: string,
	rng: Rng
): number
	local bonus = Battle.typeBonus(moveType, defender.type)
	return attacker.attack * (power / constants().basic_move_power) * bonus * drawRandom(rng)
end

-- Building a battle

-- A team member straight from the pet config, before any bonus.
function Battle.fighterFromPet(petId: string, variant: string?): FighterSpec
	local pet = Config.petById[petId]
	if variant ~= nil then
		local _ = Config.variantById[variant]
	end
	return {
		pet = pet.id,
		variant = variant,
		type = pet.type,
		hp = pet.hp,
		attack = pet.attack,
		speed = pet.speed,
		special = pet.special,
		offType = pet.special_off_type,
	}
end

-- The HP and Attack multiplier a player pet gets at battle start.
function Battle.playerMultiplier(rebirths: number, variant: string?): number
	local mult = 1 + constants().rebirth_battle_bonus * rebirths
	if variant ~= nil then
		mult *= Config.variantById[variant].battle_mult
	end
	return mult
end

local function makeFighter(spec: FighterSpec, mult: number): Fighter
	local specialRow = Config.specialById[spec.special]
	local _ = Config.typeById[spec.type]
	if specialRow.kind == "offtype" and spec.offType == nil then
		error(string.format("Battle: a %s pet needs an offType", spec.special))
	end
	return {
		pet = spec.pet,
		variant = spec.variant,
		type = spec.type,
		maxHp = spec.hp * mult,
		hp = spec.hp * mult,
		attack = spec.attack * mult,
		speed = spec.speed,
		special = spec.special,
		offType = spec.offType,
		cooldown = 0,
		guard = nil,
	}
end

function Battle.start(
	playerTeam: { FighterSpec },
	leaderTeam: { FighterSpec },
	rebirths: number,
	rng: Rng
): State
	if #playerTeam == 0 or #leaderTeam == 0 then
		error("Battle.start: both teams need at least one pet")
	end
	if #playerTeam > constants().team_size then
		error("Battle.start: the player team is larger than team_size")
	end
	if rebirths < 0 then
		error("Battle.start: rebirths cannot be negative")
	end
	local players = {}
	for _, spec in playerTeam do
		table.insert(players, makeFighter(spec, Battle.playerMultiplier(rebirths, spec.variant)))
	end
	local leaders = {}
	for _, spec in leaderTeam do
		table.insert(leaders, makeFighter(spec, 1))
	end
	return {
		player = { fighters = players, active = 1 },
		leader = { fighters = leaders, active = 1 },
		turn = 0,
		rebirths = rebirths,
		rng = rng,
	}
end

-- Reading a battle

local function sideIsOut(side: Side): boolean
	return side.active > #side.fighters
end

-- Returns "player" or "leader" once one side has no pets left, else nil.
function Battle.isOver(state: State): SideId?
	if sideIsOut(state.leader) then
		return "player"
	end
	if sideIsOut(state.player) then
		return "leader"
	end
	return nil
end

function Battle.activeFighter(state: State, side: SideId): Fighter?
	local s = if side == "player" then state.player else state.leader
	return s.fighters[s.active]
end

function Battle.canUseSpecial(state: State): boolean
	local fighter = Battle.activeFighter(state, "player")
	return fighter ~= nil and fighter.cooldown == 0
end

-- Copies everything but the rng, so takeTurn never changes the state it got.
local function copyState(state: State): State
	local function copySide(side: Side): Side
		local fighters = {}
		for _, fighter in side.fighters do
			table.insert(fighters, table.clone(fighter))
		end
		return { fighters = fighters, active = side.active }
	end
	return {
		player = copySide(state.player),
		leader = copySide(state.leader),
		turn = state.turn,
		rebirths = state.rebirths,
		rng = state.rng,
	}
end

-- One turn

local function otherSide(side: SideId): SideId
	return if side == "player" then "leader" else "player"
end

local function hit(
	events: { Event },
	rng: Rng,
	attackerSide: SideId,
	attackerIndex: number,
	attacker: Fighter,
	defenderIndex: number,
	defender: Fighter,
	move: number,
	power: number,
	moveType: string
): number
	local bonus = Battle.typeBonus(moveType, defender.type)
	table.insert(events, {
		kind = "attack",
		side = attackerSide,
		pet = attackerIndex,
		move = move,
		special = if move == Battle.SPECIAL then attacker.special else nil,
		moveType = moveType,
		power = power,
	})
	local amount = Battle.damage(attacker, defender, power, moveType, rng)
	local guarded = false
	local guard = defender.guard
	if guard ~= nil then
		amount *= guard
		defender.guard = nil
		guarded = true
	end
	defender.hp = math.max(0, defender.hp - amount)
	table.insert(events, {
		kind = "damage",
		side = otherSide(attackerSide),
		pet = defenderIndex,
		amount = amount,
		hp = defender.hp,
		maxHp = defender.maxHp,
		typeBonus = bonus,
		guarded = guarded,
	})
	if defender.hp <= 0 then
		table.insert(
			events,
			{ kind = "faint", side = otherSide(attackerSide), pet = defenderIndex }
		)
	end
	return amount
end

local function heal(
	events: { Event },
	side: SideId,
	index: number,
	fighter: Fighter,
	amount: number,
	special: string
)
	local before = fighter.hp
	fighter.hp = math.min(fighter.maxHp, fighter.hp + amount)
	table.insert(events, {
		kind = "heal",
		side = side,
		pet = index,
		special = special,
		amount = fighter.hp - before,
		hp = fighter.hp,
		maxHp = fighter.maxHp,
	})
end

-- Resolves one action. Returns true when the special was used.
local function act(
	events: { Event },
	rng: Rng,
	side: SideId,
	index: number,
	attacker: Fighter,
	defenderIndex: number,
	defender: Fighter,
	move: number
): boolean
	local basicPower = constants().basic_move_power
	if move ~= Battle.SPECIAL then
		hit(
			events,
			rng,
			side,
			index,
			attacker,
			defenderIndex,
			defender,
			Battle.BASIC,
			basicPower,
			attacker.type
		)
		return false
	end
	local row = Config.specialById[attacker.special]
	local kind = row.kind
	if kind == "attack" then
		hit(
			events,
			rng,
			side,
			index,
			attacker,
			defenderIndex,
			defender,
			move,
			row.power,
			attacker.type
		)
	elseif kind == "drain" then
		local dealt = hit(
			events,
			rng,
			side,
			index,
			attacker,
			defenderIndex,
			defender,
			move,
			row.power,
			attacker.type
		)
		heal(events, side, index, attacker, row.value * dealt, row.id)
	elseif kind == "offtype" then
		local offType = attacker.offType :: string
		hit(events, rng, side, index, attacker, defenderIndex, defender, move, row.power, offType)
	elseif kind == "heal" then
		heal(events, side, index, attacker, row.value * attacker.maxHp, row.id)
	elseif kind == "guard" then
		attacker.guard = row.value
		table.insert(
			events,
			{ kind = "guard", side = side, pet = index, special = row.id, value = row.value }
		)
	elseif kind == "speed" then
		attacker.speed *= 1 + row.value
		table.insert(events, {
			kind = "rush",
			side = side,
			pet = index,
			special = row.id,
			value = row.value,
			speed = attacker.speed,
		})
	else
		error(string.format("Battle: special %s has the unknown kind %s", row.id, kind))
	end
	return true
end

local function settleCooldown(fighter: Fighter, usedSpecial: boolean)
	if usedSpecial then
		fighter.cooldown = constants().special_cooldown_turns
	elseif fighter.cooldown > 0 then
		fighter.cooldown -= 1
	end
end

-- After a faint, bring in the next pet, or end the battle.
local function advance(events: { Event }, side: Side, sideId: SideId)
	local fighter = side.fighters[side.active]
	if fighter == nil or fighter.hp > 0 then
		return
	end
	side.active += 1
	if side.fighters[side.active] ~= nil then
		table.insert(events, { kind = "switch", side = sideId, pet = side.active })
	end
end

-- Resolves one full turn. moveChoice is Battle.BASIC (1) or Battle.SPECIAL (2).
-- Errors on a finished battle, an unknown move, or a special still cooling
-- down, so the caller checks canUseSpecial first. The state passed in is left
-- untouched; the rng advances.
function Battle.takeTurn(state: State, moveChoice: number): (State, { Event })
	if Battle.isOver(state) ~= nil then
		error("Battle.takeTurn: the battle is already over")
	end
	if moveChoice ~= Battle.BASIC and moveChoice ~= Battle.SPECIAL then
		error("Battle.takeTurn: moveChoice must be 1 or 2, got " .. tostring(moveChoice))
	end
	if moveChoice == Battle.SPECIAL and not Battle.canUseSpecial(state) then
		error("Battle.takeTurn: the special is still cooling down")
	end

	local nextState = copyState(state)
	local events: { Event } = {}
	nextState.turn += 1

	local pIndex = nextState.player.active
	local lIndex = nextState.leader.active
	local p = nextState.player.fighters[pIndex]
	local l = nextState.leader.fighters[lIndex]
	local leaderMove = if l.cooldown == 0 then Battle.SPECIAL else Battle.BASIC
	local rng = nextState.rng

	local playerUsed = false
	local leaderUsed = false
	if p.speed >= l.speed then
		playerUsed = act(events, rng, "player", pIndex, p, lIndex, l, moveChoice)
		if l.hp > 0 then
			leaderUsed = act(events, rng, "leader", lIndex, l, pIndex, p, leaderMove)
		end
	else
		leaderUsed = act(events, rng, "leader", lIndex, l, pIndex, p, leaderMove)
		if p.hp > 0 then
			playerUsed = act(events, rng, "player", pIndex, p, lIndex, l, moveChoice)
		end
	end
	settleCooldown(p, playerUsed)
	settleCooldown(l, leaderUsed)

	advance(events, nextState.player, "player")
	advance(events, nextState.leader, "leader")

	local winner = Battle.isOver(nextState)
	if winner == "player" then
		table.insert(events, { kind = "win", side = "player" })
	elseif winner == "leader" then
		table.insert(events, { kind = "lose", side = "player" })
	end
	return nextState, events
end

return Battle
