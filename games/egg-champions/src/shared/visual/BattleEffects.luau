--!strict
--[[
	BattleEffects: turns each battle event the server sent into one cue, the
	plain description of what client/Effects/Effects.luau draws for it.

	The cue comes only from the event: who acted, the move type it carried,
	the type bonus it carried, whether a guard absorbed it. Nothing here
	recomputes a matchup or a number, so a visual can never claim something
	the rules did not do.

	- SPECIAL_VISUALS has one row per special id in config/specials.json and
	  BURST_COLORS one row per type id in config/types.json. A new special or
	  type with no row fails the Effects spec instead of showing nothing.
	- HANDLERS has one function per Battle.EVENT_KINDS entry; the spec feeds
	  recorded battles through the dispatcher and fails on an unhandled kind.
	- The dispatcher keeps the little the cues need across events: the last
	  attack (its move type and special, for the burst on the damage event
	  after it) and which sides hold a guard shield.

	No engine globals, so the headless tests run it.
]]

local Config = require(script.Parent.Parent.Config)
local Battle = require(script.Parent.Parent.rules.Battle)
local PetLook = require(script.Parent.PetLook)
local EffectsBudget = require(script.Parent.EffectsBudget)

export type RGB = PetLook.RGB
export type SideId = "player" | "leader"

export type SpecialVisual = {
	-- "burst": the type burst, scaled. "shield", "crosses", "speedLines",
	-- "stream": the special's own visual.
	visual: "burst" | "shield" | "crosses" | "speedLines" | "stream",
	burstScale: number,
}

export type Burst = {
	color: RGB,
	scale: number,
}

export type Number = {
	amount: number,
	strong: boolean,
	heal: boolean,
}

export type Cue = {
	kind: string,
	seconds: number,
	-- The side the event is about: the attacker, the target, the healer.
	side: SideId,
	hop: boolean,
	hit: boolean,
	burst: Burst?,
	number: Number?,
	shieldUp: boolean,
	shieldBreak: boolean,
	crosses: boolean,
	speedLines: boolean,
	-- Drain: dots flow from this side to `side`.
	streamFrom: SideId?,
	faint: boolean,
	enter: boolean,
}

export type Dispatcher = {
	lastMoveType: string?,
	lastSpecial: string?,
	shields: { [string]: boolean },
}

local BattleEffects = {}

local function rgb(r: number, g: number, b: number): RGB
	return table.freeze({ r = r, g = g, b = b })
end

-- Burst color by type id: orange fire, green leaves, yellow sparks, blue
-- droplets. A fifth type needs one row here and no new code.
BattleEffects.BURST_COLORS = table.freeze({
	fire = rgb(255, 140, 40),
	grass = rgb(96, 204, 84),
	electric = rgb(255, 222, 60),
	water = rgb(64, 150, 255),
} :: { [string]: RGB })

-- Colors of the special visuals that are not a type burst.
BattleEffects.COLORS = table.freeze({
	flash = rgb(255, 255, 255),
	cross = rgb(110, 224, 120),
	shield = rgb(150, 205, 255),
	speedLine = rgb(255, 255, 255),
	stream = rgb(232, 92, 150),
	number = rgb(255, 255, 255),
	strongNumber = rgb(255, 205, 64),
	healNumber = rgb(110, 224, 120),
})

local B = EffectsBudget.BATTLE

-- One visual per special id in config. Smash and Off-type are the type burst
-- at a greater scale; Off-type's burst takes the off type's color because
-- its attack event carries the off type as moveType.
BattleEffects.SPECIAL_VISUALS = table.freeze({
	guard = table.freeze({ visual = "shield", burstScale = 1 }),
	heal = table.freeze({ visual = "crosses", burstScale = 1 }),
	rush = table.freeze({ visual = "speedLines", burstScale = 1 }),
	drain = table.freeze({ visual = "stream", burstScale = 1 }),
	smash = table.freeze({ visual = "burst", burstScale = B.smashBurstScale }),
	off_type = table.freeze({ visual = "burst", burstScale = B.offTypeBurstScale }),
} :: { [string]: SpecialVisual })

function BattleEffects.burstColor(typeId: string?): RGB
	if typeId == nil then
		return PetLook.FALLBACK_COLOR
	end
	return BattleEffects.BURST_COLORS[typeId] or PetLook.FALLBACK_COLOR
end

function BattleEffects.specialVisual(specialId: string?): SpecialVisual?
	if specialId == nil then
		return nil
	end
	return BattleEffects.SPECIAL_VISUALS[specialId]
end

local function asSide(value: any): SideId
	return if value == "leader" then "leader" else "player"
end

local function other(side: SideId): SideId
	return if side == "player" then "leader" else "player"
end

local function num(value: any): number
	return if type(value) == "number" then value else 0
end

local function str(value: any): string?
	return if type(value) == "string" then value else nil
end

local function blank(kind: string, side: SideId): Cue
	return {
		kind = kind,
		seconds = EffectsBudget.battleSeconds(kind),
		side = side,
		hop = false,
		hit = false,
		burst = nil,
		number = nil,
		shieldUp = false,
		shieldBreak = false,
		crosses = false,
		speedLines = false,
		streamFrom = nil,
		faint = false,
		enter = false,
	}
end

type Handler = (state: Dispatcher, event: any, cue: Cue) -> ()

-- One handler per event kind in Battle.EVENT_KINDS.
BattleEffects.HANDLERS = table.freeze({
	attack = function(state: Dispatcher, event: any, cue: Cue)
		cue.hop = true
		state.lastMoveType = str(event.moveType)
		state.lastSpecial = str(event.special)
	end,
	damage = function(state: Dispatcher, event: any, cue: Cue)
		cue.hit = true
		local visual = BattleEffects.specialVisual(state.lastSpecial)
		cue.burst = {
			color = BattleEffects.burstColor(state.lastMoveType),
			scale = if visual ~= nil and visual.visual == "burst" then visual.burstScale else 1,
		}
		cue.number = {
			amount = num(event.amount),
			-- Strong means the server's event carried the strong bonus.
			strong = event.typeBonus == Config.constants.type_bonus_strong,
			heal = false,
		}
		if event.guarded == true and state.shields[cue.side] then
			state.shields[cue.side] = false
			cue.shieldBreak = true
		end
		state.lastMoveType = nil
		state.lastSpecial = nil
	end,
	heal = function(_state: Dispatcher, event: any, cue: Cue)
		local visual = BattleEffects.specialVisual(str(event.special))
		if visual ~= nil and visual.visual == "stream" then
			cue.streamFrom = other(cue.side)
		else
			cue.crosses = true
		end
		cue.number = { amount = num(event.amount), strong = false, heal = true }
	end,
	guard = function(state: Dispatcher, _event: any, cue: Cue)
		state.shields[cue.side] = true
		cue.shieldUp = true
	end,
	rush = function(_state: Dispatcher, _event: any, cue: Cue)
		cue.speedLines = true
	end,
	faint = function(state: Dispatcher, _event: any, cue: Cue)
		cue.faint = true
		if state.shields[cue.side] then
			state.shields[cue.side] = false
			cue.shieldBreak = true
		end
	end,
	switch = function(_state: Dispatcher, _event: any, cue: Cue)
		cue.enter = true
	end,
	win = function(_state: Dispatcher, _event: any, _cue: Cue) end,
	lose = function(_state: Dispatcher, _event: any, _cue: Cue) end,
} :: { [string]: Handler })

function BattleEffects.handles(kind: string): boolean
	return BattleEffects.HANDLERS[kind] ~= nil
end

-- The event kinds the rules emit that have no handler. Empty when covered.
function BattleEffects.unhandledKinds(): { string }
	local missing = {}
	for _, kind in Battle.EVENT_KINDS do
		if not BattleEffects.handles(kind) then
			table.insert(missing, kind)
		end
	end
	return missing
end

function BattleEffects.newDispatcher(): Dispatcher
	return { lastMoveType = nil, lastSpecial = nil, shields = {} }
end

-- The cue for one event, or nil for an event kind with no handler.
function BattleEffects.cue(state: Dispatcher, event: any): Cue?
	if type(event) ~= "table" or type(event.kind) ~= "string" then
		return nil
	end
	local handler = BattleEffects.HANDLERS[event.kind]
	if handler == nil then
		return nil
	end
	local cue = blank(event.kind, asSide(event.side))
	handler(state, event, cue)
	return cue
end

return BattleEffects
