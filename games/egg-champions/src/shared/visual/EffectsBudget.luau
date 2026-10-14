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

-- Battle effects. Every event in a turn's list plays alone, one after another,
-- for exactly its row in BATTLE_SECONDS; nothing overlaps. The animations
-- inside an event are sized to fit its row (the Effects spec checks that).
--
-- A typical turn is two actions, each an attack then a damage event:
-- 2 x (attack 0.6 + damage 0.8) = 2.8 seconds, the same pace as the 0.7
-- seconds per event task 13 shipped with, so a battle the spec calls about
-- two minutes long stays about two minutes long. See typicalTurnSeconds.
EffectsBudget.BATTLE_SECONDS = table.freeze({
	attack = 0.6,
	damage = 0.8,
	heal = 0.7,
	guard = 0.7,
	rush = 0.7,
	faint = 0.7,
	switch = 0.5,
	win = 0.4,
	lose = 0.4,
} :: { [string]: number })

-- Battle effect sizes and inner timings, in canvas pixels at 1280 x 720.
EffectsBudget.BATTLE = table.freeze({
	-- Attack motion: the attacker hops toward the target and back.
	hopDistance = 60,
	hopSeconds = 0.15,
	-- The target flashes white and shakes.
	flashSeconds = 0.25,
	flashStart = 0.2,
	shakeOffset = 8,
	shakeSeconds = 0.05,
	shakes = 3,
	-- Type burst on hit. Smash and Off-type scale it up.
	burstParticles = 8,
	burstSize = 16,
	burstDistance = 90,
	burstLifetime = 0.45,
	smashBurstScale = 1.8,
	offTypeBurstScale = 1.5,
	-- Damage and heal numbers above the pet.
	numberSize = 40,
	strongNumberSize = 58,
	numberRise = 50,
	numberSeconds = 0.7,
	-- Guard: a shield ring that holds until the hit it absorbs.
	shieldPad = 22,
	shieldThickness = 4,
	shieldInSeconds = 0.25,
	shieldBreakSeconds = 0.3,
	-- Heal: rising green crosses.
	crosses = 4,
	crossSize = 34,
	crossRise = 90,
	crossSeconds = 0.6,
	-- Rush: speed lines trailing the user.
	speedLines = 5,
	speedLineLength = 120,
	speedLineWidth = 4,
	speedLineSeconds = 0.45,
	-- Drain: a stream of dots from the target to the user.
	streamDots = 6,
	streamDotSize = 14,
	streamSeconds = 0.45,
	streamStagger = 0.04,
	-- Faint: shrink and fade; the next pet grows in on switch.
	faintSeconds = 0.5,
	enterSeconds = 0.35,
	-- Pool caps: the most of each piece alive at once.
	dotPool = 24,
	barPool = 8,
	labelPool = 8,
})

-- Progression effects: gym win, rebirth and world unlock. Screen sizes are
-- pixels at 1280 x 720; world sizes are studs.
EffectsBudget.PROGRESS = table.freeze({
	-- Gym win: the badge pops in with a burst in the gold accent, holds, and
	-- fades. The newly open portal lights up once the badge is done.
	badgeSize = 120,
	badgeInSeconds = 0.35,
	badgeHoldSeconds = 1.2,
	badgeOutSeconds = 0.3,
	badgeBurstDots = 10,
	badgeBurstDistance = 150,
	badgeBurstDotSize = 14,
	badgeBurstSeconds = 0.5,
	captionSize = 30,
	-- Rebirth: one screen flash and one ring rising around the player.
	flashStrength = 0.15,
	flashSeconds = 0.5,
	ringSize = 8,
	ringGrow = 3,
	ringThickness = 0.4,
	ringRise = 9,
	ringSeconds = 0.9,
	-- World unlock: a swirl of particles on the portal in the world's color,
	-- and a short screen swirl when a player walks through an open portal.
	swirlParticles = 24,
	swirlLifetime = 0.8,
	swirlSpeed = 6,
	swirlSize = 0.6,
	swirlSpin = 360,
	-- Only portals this close to the camera play their swirl; farther ones
	-- just change state, so nothing runs off screen.
	swirlDistance = 160,
	walkSwirlSize = 260,
	walkSwirlSeconds = 0.6,
	walkSwirlTurns = 1,
	-- Portal look while locked: the glow dims.
	lockedTransparency = 0.75,
	openTransparency = 0.3,
})

-- Variant looks inside a ViewportFrame. Roblox does not render particles or
-- lights in a ViewportFrame, so every pet view (shop, pets screen, team bar,
-- battle, hatch reveal) shows shiny and golden only with things that do
-- render there: the model's material, and UI layered on the frame itself.
--
-- Each row may have:
-- - material: the Enum.Material name painted on the model's parts
--   (golden skips the rarity band, so rarity still reads).
-- - stroke: a UIStroke in the variant color around the frame.
-- - shimmer: a Frame tinted `color` with a UIGradient band that sweeps
--   across every `seconds`. `transparency` is the band at its strongest.
-- - pulse: the stroke and the tint breathe between `low` and `high`
--   transparency every `seconds`, back and forth.
-- - twinkles: small sparkle ImageLabels at fixed spots (scale 0 to 1 of the
--   frame), each growing in and out over `seconds`, staggered by `stagger`.
--
-- The normal row is empty: a normal pet is just its model.
export type RGB = PetLook.RGB

export type VariantStroke = { color: RGB, thickness: number, transparency: number }
export type VariantShimmer = { color: RGB, transparency: number, width: number, seconds: number }
export type VariantPulse = { low: number, high: number, seconds: number }
export type VariantTwinkles = {
	image: string,
	color: RGB,
	size: number,
	seconds: number,
	stagger: number,
	spots: { { x: number, y: number } },
}
export type VariantView = {
	material: string?,
	stroke: VariantStroke?,
	shimmer: VariantShimmer?,
	pulse: VariantPulse?,
	twinkles: VariantTwinkles?,
}

local function rgb(r: number, g: number, b: number): RGB
	return table.freeze({ r = r, g = g, b = b })
end

local SPARKLE_IMAGE = "rbxasset://textures/particles/sparkles_main.dds"

EffectsBudget.VARIANT_VIEW = table.freeze({
	normal = table.freeze({}),
	shiny = table.freeze({
		material = "Neon",
		stroke = table.freeze({ color = rgb(214, 236, 255), thickness = 2, transparency = 0.15 }),
		shimmer = table.freeze({
			color = rgb(235, 245, 255),
			transparency = 0.55,
			width = 0.25,
			seconds = 1.6,
		}),
		twinkles = table.freeze({
			image = SPARKLE_IMAGE,
			color = rgb(255, 255, 255),
			size = 0.18,
			seconds = 0.9,
			stagger = 0.3,
			spots = table.freeze({
				table.freeze({ x = 0.2, y = 0.22 }),
				table.freeze({ x = 0.8, y = 0.3 }),
				table.freeze({ x = 0.7, y = 0.8 }),
			}),
		}),
	}),
	golden = table.freeze({
		material = "Foil",
		stroke = table.freeze({ color = PetLook.GOLD, thickness = 3, transparency = 0 }),
		shimmer = table.freeze({
			color = rgb(255, 214, 110),
			transparency = 0.7,
			width = 0.6,
			seconds = 2.4,
		}),
		pulse = table.freeze({ low = 0, high = 0.6, seconds = 1.2 }),
	}),
} :: { [string]: VariantView })

-- The elemental accent on fire, electric and water pets: a small solid
-- piece at the feature attachment, its edge this share of the pet's edge.
EffectsBudget.ACCENT = table.freeze({
	share = 0.3,
	material = "Neon",
})

-- The instance classes each part of a variant view is made of, so the tests
-- can prove no view depends on something a ViewportFrame cannot render.
EffectsBudget.VIEW_CLASSES = table.freeze({
	stroke = table.freeze({ "UIStroke" }),
	shimmer = table.freeze({ "Frame", "UIGradient" }),
	pulse = table.freeze({ "UIStroke", "Frame" }),
	twinkles = table.freeze({ "ImageLabel" }),
} :: { [string]: { string } })

-- The viewport look for a variant id (nil for a normal pet). Errors on a
-- variant id that is not in config, like every config lookup.
function EffectsBudget.variantView(variant: string?): VariantView
	if variant == nil then
		return EffectsBudget.VARIANT_VIEW.normal
	end
	local _ = Config.variantById[variant]
	local row = EffectsBudget.VARIANT_VIEW[variant]
	if row == nil then
		error(string.format("EffectsBudget: no viewport look for variant %q", variant))
	end
	return row
end

-- Every instance class a variant's view creates, besides the model itself.
function EffectsBudget.variantClasses(variant: string?): { string }
	local view = EffectsBudget.variantView(variant)
	local classes: { string } = {}
	for _, piece in { "stroke", "shimmer", "pulse", "twinkles" } do
		if (view :: any)[piece] ~= nil then
			for _, class in EffectsBudget.VIEW_CLASSES[piece] do
				if table.find(classes, class) == nil then
					table.insert(classes, class)
				end
			end
		end
	end
	return classes
end

-- Seconds the gym win badge plays before the next portal lights up.
function EffectsBudget.badgeSeconds(): number
	local p = EffectsBudget.PROGRESS
	return p.badgeInSeconds + p.badgeHoldSeconds + p.badgeOutSeconds
end

-- Seconds one event kind plays for. An unknown kind gets the shortest row,
-- so a malformed event cannot stall the queue.
function EffectsBudget.battleSeconds(kind: string): number
	local seconds = EffectsBudget.BATTLE_SECONDS[kind]
	if seconds ~= nil then
		return seconds
	end
	local shortest = math.huge
	for _, row in EffectsBudget.BATTLE_SECONDS do
		shortest = math.min(shortest, row)
	end
	return shortest
end

-- Seconds a typical turn takes: both sides attack and hit once.
function EffectsBudget.typicalTurnSeconds(): number
	local seconds = EffectsBudget.BATTLE_SECONDS
	return 2 * (seconds.attack + seconds.damage)
end

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
