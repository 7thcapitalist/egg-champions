--!strict
--[[
	BattleView: what the gym battle screen shows, worked out with no engine
	calls so the headless tests can check it.

	- snapshot: the view of a battle the server sends with every answer (HP,
	  max HP, cooldown, speed and the active pet of each side). The server
	  builds it from its own state; the client renders it as sent.
	- apply: plays one server event onto a displayed snapshot, so HP bars and
	  the active pet move one event at a time. It only copies numbers the event
	  carries. When a turn's events are played, the screen resyncs to the
	  snapshot the server sent, so the server is always right.
	- lineFor: one readable log line per event: who acted, what it did, and
	  how much damage it dealt. Every kind in Battle.EVENT_KINDS has a format.
	- Move names: move 1 is the basic attack of the pet's type, named after
	  the type; move 2 is the pet's special, named from config.
	- The fee prompt, the result after a battle and the retry countdown.

	Nothing here resolves a turn. The server does, and reasonText only turns
	its refusal into words.
]]

local Config = require(script.Parent.Parent.Config)
local Battle = require(script.Parent.Parent.rules.Battle)
local Gym = require(script.Parent.Parent.rules.Gym)
local Progression = require(script.Parent.Parent.rules.Progression)
local Format = require(script.Parent.Format)

export type FighterView = {
	pet: string?,
	variant: string?,
	type: string,
	hp: number,
	maxHp: number,
	speed: number,
	special: string,
	cooldown: number,
}

export type SideView = {
	active: number,
	fighters: { FighterView },
}

export type Snapshot = {
	turn: number,
	player: SideView,
	leader: SideView,
	specialReady: boolean,
}

local BattleView = {}

-- Building and copying a snapshot

local function sideOf(s: Battle.Side): SideView
	local fighters = {}
	for _, fighter in s.fighters do
		table.insert(fighters, {
			pet = fighter.pet,
			variant = fighter.variant,
			type = fighter.type,
			hp = fighter.hp,
			maxHp = fighter.maxHp,
			speed = fighter.speed,
			special = fighter.special,
			cooldown = fighter.cooldown,
		})
	end
	return { active = s.active, fighters = fighters }
end

-- The view of a battle state the server sends to the client.
function BattleView.snapshot(state: Battle.State): Snapshot
	return {
		turn = state.turn,
		player = sideOf(state.player),
		leader = sideOf(state.leader),
		specialReady = Battle.canUseSpecial(state),
	}
end

local function copySide(side: SideView): SideView
	local fighters = {}
	for _, fighter in side.fighters do
		table.insert(fighters, table.clone(fighter))
	end
	return { active = side.active, fighters = fighters }
end

function BattleView.copy(snapshot: Snapshot): Snapshot
	return {
		turn = snapshot.turn,
		player = copySide(snapshot.player),
		leader = copySide(snapshot.leader),
		specialReady = snapshot.specialReady,
	}
end

local function sideView(snapshot: Snapshot, side: string): SideView
	return if side == "player" then snapshot.player else snapshot.leader
end

-- The active fighter of a side, or nil once that side has no pets left.
function BattleView.active(snapshot: Snapshot, side: string): FighterView?
	local s = sideView(snapshot, side)
	return s.fighters[s.active]
end

-- How many pets a side still has standing, for the team markers.
function BattleView.petsLeft(side: SideView): number
	local count = 0
	for _, fighter in side.fighters do
		if fighter.hp > 0 then
			count += 1
		end
	end
	return count
end

-- Plays one event onto a displayed snapshot. Only numbers the event carries
-- are copied; nothing is computed.
function BattleView.apply(display: Snapshot, event: Battle.Event)
	local side = sideView(display, event.side)
	local fighter = if event.pet ~= nil then side.fighters[event.pet] else nil
	if event.kind == "damage" or event.kind == "heal" then
		if fighter ~= nil and event.hp ~= nil then
			fighter.hp = event.hp
		end
	elseif event.kind == "faint" then
		if fighter ~= nil then
			fighter.hp = 0
		end
	elseif event.kind == "rush" then
		if fighter ~= nil and event.speed ~= nil then
			fighter.speed = event.speed
		end
	elseif event.kind == "switch" then
		if event.pet ~= nil then
			side.active = event.pet
		end
	end
end

-- Names and numbers

function BattleView.fighterName(snapshot: Snapshot, side: string, index: number): string
	local fighter = sideView(snapshot, side).fighters[index]
	if fighter == nil or fighter.pet == nil then
		return if side == "leader" then string.format("Leader's pet %d", index) else "Your pet"
	end
	local name = Config.petById[fighter.pet :: string].name
	if side == "leader" then
		return "Leader's " .. name
	end
	if fighter.variant ~= nil then
		return Config.variantById[fighter.variant :: string].name .. " " .. name
	end
	return name
end

function BattleView.typeName(typeId: string): string
	return Config.typeById[typeId].name
end

-- Move 1: the basic attack of the pet's type.
function BattleView.basicMoveName(typeId: string): string
	return BattleView.typeName(typeId) .. " Strike"
end

-- Move 2: the pet's special, named from config.
function BattleView.specialName(specialId: string): string
	return Config.specialById[specialId].name
end

function BattleView.hpText(hp: number, maxHp: number): string
	return string.format(
		"%s / %s HP",
		Format.commas(math.ceil(hp)),
		Format.commas(math.ceil(maxHp))
	)
end

function BattleView.hpShare(hp: number, maxHp: number): number
	if maxHp <= 0 then
		return 0
	end
	return math.clamp(hp / maxHp, 0, 1)
end

function BattleView.speedText(speed: number): string
	return "Speed " .. Format.commas(speed)
end

local function turns(count: number): string
	return if count == 1 then "1 turn" else string.format("%d turns", count)
end

-- The second line of the move 2 button.
function BattleView.cooldownText(cooldown: number): string
	if cooldown <= 0 then
		return "Ready"
	end
	return "Ready in " .. turns(cooldown)
end

-- The number that pops up over a pet that was hit: "-60".
function BattleView.damageText(amount: number): string
	return "-" .. Format.commas(math.ceil(amount))
end

-- The log

local function amountText(amount: number?): string
	return Format.commas(math.ceil(amount or 0))
end

type LineFormat = (event: Battle.Event, snapshot: Snapshot) -> string

local function nameOf(event: Battle.Event, snapshot: Snapshot): string
	return BattleView.fighterName(snapshot, event.side, event.pet or 0)
end

local LINES: { [string]: LineFormat } = {
	attack = function(event, snapshot)
		local moveName = if event.special ~= nil
			then BattleView.specialName(event.special :: string)
			else BattleView.basicMoveName(event.moveType or "")
		local line = string.format("%s used %s.", nameOf(event, snapshot), moveName)
		if event.special ~= nil and event.moveType ~= nil then
			local attacker = BattleView.active(snapshot, event.side)
			if attacker ~= nil and attacker.type ~= event.moveType then
				line ..= string.format(
					" It is a %s move.",
					BattleView.typeName(event.moveType :: string)
				)
			end
		end
		return line
	end,
	damage = function(event, snapshot)
		local target = sideView(snapshot, event.side).fighters[event.pet or 0]
		local bonus = event.typeBonus or 1
		local prefix = ""
		if target ~= nil and bonus > 1 then
			prefix = string.format("It is strong against %s. ", BattleView.typeName(target.type))
		elseif target ~= nil and bonus < 1 then
			prefix = string.format("It is weak against %s. ", BattleView.typeName(target.type))
		end
		local guarded = if event.guarded == true then " Guard softened the hit." else ""
		return string.format(
			"%s%s took %s damage, %s left.%s",
			prefix,
			nameOf(event, snapshot),
			amountText(event.amount),
			BattleView.hpText(event.hp or 0, event.maxHp or 0),
			guarded
		)
	end,
	heal = function(event, snapshot)
		return string.format(
			"%s healed %s HP with %s, now %s.",
			nameOf(event, snapshot),
			amountText(event.amount),
			BattleView.specialName(event.special or ""),
			BattleView.hpText(event.hp or 0, event.maxHp or 0)
		)
	end,
	guard = function(event, snapshot)
		local share = math.floor((event.value or 0) * 100 + 0.5)
		return string.format(
			"%s used %s. The next hit it takes does %d%% damage.",
			nameOf(event, snapshot),
			BattleView.specialName(event.special or ""),
			share
		)
	end,
	rush = function(event, snapshot)
		return string.format(
			"%s used %s. Its Speed rose to %s.",
			nameOf(event, snapshot),
			BattleView.specialName(event.special or ""),
			Format.commas(event.speed or 0)
		)
	end,
	faint = function(event, snapshot)
		return string.format("%s fainted.", nameOf(event, snapshot))
	end,
	switch = function(event, snapshot)
		if event.side == "player" then
			return string.format("You sent in %s.", nameOf(event, snapshot))
		end
		return string.format("The leader sent in %s.", nameOf(event, snapshot))
	end,
	win = function()
		return "You won the gym battle."
	end,
	lose = function()
		return "You lost the gym battle."
	end,
}

-- True when the log has a line format for this event kind.
function BattleView.handles(kind: string): boolean
	return LINES[kind] ~= nil
end

-- The kinds the log can write, sorted.
function BattleView.handledKinds(): { string }
	local kinds = {}
	for kind in LINES do
		table.insert(kinds, kind)
	end
	table.sort(kinds)
	return kinds
end

-- One readable line for one server event. The snapshot names the pets; any
-- snapshot of the same battle works, since teams never change mid battle.
function BattleView.lineFor(event: Battle.Event, snapshot: Snapshot): string
	local format = LINES[event.kind]
	if format == nil then
		error("BattleView: no log line for the event kind " .. tostring(event.kind))
	end
	return format(event, snapshot)
end

-- The log lines for a whole event list, one per event, in order.
function BattleView.lines(events: { Battle.Event }, snapshot: Snapshot): { string }
	local out = {}
	for _, event in events do
		table.insert(out, BattleView.lineFor(event, snapshot))
	end
	return out
end

-- Entering, leaving and waiting

export type GymState = {
	badges: { [string]: boolean },
	gymsBeaten: { [string]: boolean },
	feesPaid: { [string]: boolean },
}

local function asProgression(state: GymState): Progression.State
	local s = Progression.newState()
	s.badges = state.badges
	s.gymsBeaten = state.gymsBeaten
	s.feesPaid = state.feesPaid
	return s
end

-- The gym the Battle menu button goes to: the first open world whose gym is
-- not beaten in this run, else the last open world.
function BattleView.pickGym(state: GymState): string
	local progression = asProgression(state)
	local ordered = table.clone(Config.worlds)
	table.sort(ordered, function(a, b)
		return a.index < b.index
	end)
	local lastOpen = ordered[1].id
	for _, world in ordered do
		if Progression.worldUnlocked(progression, world.index) then
			lastOpen = world.id
			if not Progression.isGymBeaten(progression, world.index) then
				return world.id
			end
		end
	end
	return lastOpen
end

export type FeePrompt = {
	title: string,
	body: string,
	paid: boolean,
	fee: number,
	feeText: string,
}

function BattleView.feePrompt(worldId: string, state: GymState): FeePrompt
	local world = Config.worldById[worldId]
	local fee = Gym.fee(worldId)
	local paid = state.feesPaid[worldId] == true
	local cost = if paid
		then "Fee paid. Attempts are free until your next rebirth."
		else string.format(
			"The gym fee is %s coins. Once paid, attempts are free until your next rebirth.",
			Format.commas(fee)
		)
	local body = string.format(
		"Leader's pets are %s. %s moves are strong against them. %s A loss or giving up starts a %ds retry wait.",
		BattleView.typeName(world.gym.leader_type),
		BattleView.typeName(world.gym.counter_type),
		cost,
		Gym.retrySeconds()
	)
	return {
		title = world.name .. " Gym",
		body = body,
		paid = paid,
		fee = fee,
		feeText = Format.abbreviate(fee),
	}
end

-- The wait after a loss, as text.
function BattleView.countdownText(secondsLeft: number): string
	local whole = math.max(0, math.ceil(secondsLeft))
	if whole == 0 then
		return "The gym is open again."
	end
	return string.format("You can try again in %ds.", whole)
end

-- The seconds left on a "retry_wait" refusal from the server, 0 for any other
-- answer. The server sends the number; this only reads it safely.
function BattleView.retryWaitOf(reply: any): number
	if type(reply) ~= "table" or reply.reason ~= "retry_wait" then
		return 0
	end
	local seconds = reply.retrySeconds
	if type(seconds) ~= "number" or seconds ~= seconds or seconds == math.huge then
		return 0
	end
	return math.max(0, seconds)
end

-- The line under the result after a win: the badge, and the next world.
function BattleView.winText(worldId: string, newBadge: boolean): string
	local world = Config.worldById[worldId]
	local badge = if newBadge
		then string.format("You earned the %s badge.", world.name)
		else string.format("You already hold the %s badge.", world.name)
	local nextWorld: Config.World? = nil
	for _, candidate in Config.worlds do
		if candidate.index == world.index + 1 then
			nextWorld = candidate
		end
	end
	if nextWorld == nil then
		return badge .. " That was the final gym."
	end
	return string.format("%s %s is now open.", badge, nextWorld.name)
end

-- Readable messages for the reasons the server can refuse a gym request.
local REASONS: { [string]: string } = {
	world_locked = "That world is still locked.",
	fee_already_paid = "The fee is already paid.",
	cannot_afford = "You do not have enough coins for the gym fee.",
	fee_not_paid = "Pay the gym fee first.",
	already_in_battle = "You are already in a battle.",
	retry_wait = "The gym is not ready for a retry yet.",
	team_empty = "Equip at least one pet first.",
	special_on_cooldown = "That special is still cooling down.",
	session_ended = "That battle is over.",
	no_session = "That battle is over.",
	rate_limited = "Slow down a little.",
}

function BattleView.reasonText(reason: any): string
	if type(reason) == "string" and REASONS[reason] ~= nil then
		return REASONS[reason]
	end
	return "The gym refused: " .. tostring(reason)
end

return BattleView
