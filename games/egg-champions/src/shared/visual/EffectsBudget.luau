--!strict
--[[
	EffectsBudget: the one table of effect counts, lifetimes and durations.

	client/Effects/Effects.luau exposes this as Effects.BUDGET and reads every
	number from it, so the whole feel can be tuned here and the phone budget
	is visible in one place. It lives in shared, with no engine globals, so the
	headless tests can check that every rarity in config has a reveal.

	These are presentation numbers, not game numbers: nothing here changes
	what a player gets. Rarity ids, names and order come from config; reveal
	colors come from PetLook, the same source Theme.rarityColor reads, so the
	rarity stripe and the light rays never disagree.

	Hatch timings are listed by rarity rank, lowest first, and keyed by rarity
	id at load from config order. A rarity past the end of the list reuses the
	last entry, so a new rarity in config still gets a reveal.
]]

local Config = require(script.Parent.Parent.Config)
local PetLook = require(script.Parent.PetLook)

export type HatchTiming = {
	-- Each shake tilts the egg and back; there are SHAKES of them.
	shakeSeconds: number,
	shakeAngle: number,
	-- The crack flash in the rarity color, from `flashStrength` to clear.
	flashSeconds: number,
	flashStrength: number,
	-- The pet grows in while the rays turn.
	revealSeconds: number,
	-- How long the finished reveal stays before the next one.
	holdSeconds: number,
	-- Light rays behind the pet.
	rays: number,
	rayLength: number,
	rayTurnDegrees: number,
	-- Whole sequence for one pet, worked out below.
	total: number,
}

local EffectsBudget = {}

-- Click pop: the coin amount at the click point, plus a coin burst in the
-- world. At most `maxLive` pops and `burstPool` bursts exist at once.
EffectsBudget.CLICK = table.freeze({
	maxLive = 12,
	lifetime = 0.6,
	rise = 70,
	textSize = 28,
	burstPool = 6,
	burstParticles = 6,
	burstLifetime = 0.45,
	burstSpeed = 10,
	burstSize = 0.5,
	rayDistance = 300,
	fallbackDistance = 25,
	-- Clicks waiting for the server's credited amount.
	pendingMax = 24,
	pendingSeconds = 1.5,
})

-- Hatch sequence, shared by every rarity.
EffectsBudget.HATCH = table.freeze({
	shakes = 3,
	shakeGap = 0.08,
	eggSize = 160,
	petSize = 180,
	rayWidth = 14,
	rayTransparency = 0.35,
	-- Hatch x3 plays its reveals one after another, never overlapping.
	tripleMode = "sequence",
})

-- Per rarity rank, lowest first: longer and brighter for Epic and Legendary.
EffectsBudget.HATCH_BY_RANK = table.freeze({
	table.freeze({
		shakeSeconds = 0.1,
		shakeAngle = 8,
		flashSeconds = 0.15,
		flashStrength = 0.35,
		revealSeconds = 0.25,
		holdSeconds = 0.6,
		rays = 6,
		rayLength = 140,
		rayTurnDegrees = 30,
	}),
	table.freeze({
		shakeSeconds = 0.1,
		shakeAngle = 9,
		flashSeconds = 0.18,
		flashStrength = 0.45,
		revealSeconds = 0.28,
		holdSeconds = 0.7,
		rays = 8,
		rayLength = 160,
		rayTurnDegrees = 40,
	}),
	table.freeze({
		shakeSeconds = 0.12,
		shakeAngle = 10,
		flashSeconds = 0.22,
		flashStrength = 0.55,
		revealSeconds = 0.32,
		holdSeconds = 0.8,
		rays = 10,
		rayLength = 190,
		rayTurnDegrees = 50,
	}),
	table.freeze({
		shakeSeconds = 0.16,
		shakeAngle = 13,
		flashSeconds = 0.35,
		flashStrength = 0.8,
		revealSeconds = 0.45,
		holdSeconds = 1.2,
		rays = 14,
		rayLength = 240,
		rayTurnDegrees = 80,
	}),
	table.freeze({
		shakeSeconds = 0.2,
		shakeAngle = 16,
		flashSeconds = 0.5,
		flashStrength = 1,
		revealSeconds = 0.6,
		holdSeconds = 1.6,
		rays = 18,
		rayLength = 300,
		rayTurnDegrees = 120,
	}),
})

local function timing(rank: number): HatchTiming
	local row = EffectsBudget.HATCH_BY_RANK[math.min(rank, #EffectsBudget.HATCH_BY_RANK)]
	local shakes = EffectsBudget.HATCH.shakes
	local total = shakes * (row.shakeSeconds * 2 + EffectsBudget.HATCH.shakeGap)
		+ row.flashSeconds
		+ row.revealSeconds
		+ row.holdSeconds
	return table.freeze({
		shakeSeconds = row.shakeSeconds,
		shakeAngle = row.shakeAngle,
		flashSeconds = row.flashSeconds,
		flashStrength = row.flashStrength,
		revealSeconds = row.revealSeconds,
		holdSeconds = row.holdSeconds,
		rays = row.rays,
		rayLength = row.rayLength,
		rayTurnDegrees = row.rayTurnDegrees,
		total = total,
	})
end

-- Hatch timing by rarity id, for every rarity in config.
local byId: { [string]: HatchTiming } = {}
do
	local ordered = table.clone(Config.rarities)
	table.sort(ordered, function(a, b)
		return a.order < b.order
	end)
	for rank, rarity in ordered do
		byId[rarity.id] = timing(rank)
	end
end
EffectsBudget.hatch = table.freeze(byId)

-- The timing for a rarity id; an unknown id gets the lowest rarity's.
function EffectsBudget.hatchTiming(rarityId: string): HatchTiming
	return byId[rarityId] or timing(1)
end

-- The reveal color for a rarity id: the same color as Theme.rarityColor.
function EffectsBudget.rarityColor(rarityId: string): PetLook.RGB
	return PetLook.rarityColor(rarityId)
end

-- Seconds a run of reveals takes, played one after another.
function EffectsBudget.sequenceSeconds(rarityIds: { string }): number
	local seconds = 0
	for _, rarityId in rarityIds do
		seconds += EffectsBudget.hatchTiming(rarityId).total
	end
	return seconds
end

return EffectsBudget
