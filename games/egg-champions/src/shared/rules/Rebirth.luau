--!strict
--[[
	Rebirth: what a rebirth costs and what it resets.

	cost = rebirth_first_cost x rebirth_cost_growth ^ rebirths, from config.

	A rebirth clears exactly the fields in Rebirth.CLEARED (coins, gym wins of
	the current run, paid gym fees), adds one to rebirths, and keeps every other
	field as it was. Fields are kept unless listed here, so a new field added to
	the state later can never be wiped by accident. Pets, the pet index and
	badges are always kept.
]]

local Config = require(script.Parent.Parent.Config)
local Progression = require(script.Parent.Progression)

type State = Progression.State

local Rebirth = {}

-- The fields a rebirth clears, in sorted order.
Rebirth.CLEARED = table.freeze({ "coins", "feesPaid", "gymsBeaten" })

-- The field a rebirth counts up.
Rebirth.COUNTER = "rebirths"

function Rebirth.cost(rebirths: number): number
	if rebirths < 0 then
		error("Rebirth.cost: rebirths cannot be negative")
	end
	local constants = Config.constants
	return constants.rebirth_first_cost * constants.rebirth_cost_growth ^ rebirths
end

function Rebirth.canRebirth(state: State): boolean
	return state.coins >= Rebirth.cost(state.rebirths)
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, item in value do
		copy[deepCopy(key)] = deepCopy(item)
	end
	return copy
end

-- Returns the state after one rebirth. The input is left untouched. Does not
-- check the cost; the caller checks canRebirth and refuses first.
function Rebirth.apply(state: State): State
	local source: any = state
	local nextState: any = {}
	for key, value in source do
		nextState[key] = deepCopy(value)
	end
	nextState.coins = 0
	nextState.gymsBeaten = {}
	nextState.feesPaid = {}
	nextState.rebirths = state.rebirths + 1
	return nextState :: State
end

return Rebirth
