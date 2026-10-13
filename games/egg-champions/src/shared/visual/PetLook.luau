--!strict
--[[
	PetLook: what a pet looks like, as plain data.

	PetVisual builds the Roblox model from this. Keeping the look here, with
	no engine globals, lets the headless tests prove that every pet in config
	resolves to a color, a band and a size, so a new pet can never render as
	nil. Theme reads its type and rarity colors from here too, so the 2D UI
	and the 3D pet agree.

	Type and rarity come from config. Colors and sizes are presentation, not
	game numbers, so they live here in one place:
	- body color by type (orange fire, green grass, yellow electric, blue water)
	- band color by rarity order, lowest first (grey, green, blue, purple, orange)
	- size grows with rarity order, so a Legendary reads as larger
	- the elemental feature per type names the attachment point effects use

	MODEL_IDS is the asset stage's seam: when a pet has an entry, PetVisual
	uses that model instead of the placeholder block. Nothing else changes.
]]

local Config = require(script.Parent.Parent.Config)

export type RGB = { r: number, g: number, b: number }

export type Feature = {
	-- Name of the attachment on the model where elemental effects go.
	attachment: string,
	-- Whether the type gets a looping idle emitter.
	emits: boolean,
	-- Particle color for the idle emitter.
	color: RGB,
}

export type Look = {
	petId: string?,
	typeId: string,
	rarityId: string,
	variant: string?,
	body: RGB,
	band: RGB,
	-- Edge length of the block, in studs.
	size: number,
	feature: Feature,
	-- The asset stage's model id, or nil for the placeholder block.
	modelId: string?,
	shiny: boolean,
	golden: boolean,
}

local PetLook = {}

local function rgb(r: number, g: number, b: number): RGB
	return table.freeze({ r = r, g = g, b = b })
end

-- Body color by type id.
PetLook.TYPE_COLORS = table.freeze({
	fire = rgb(217, 98, 58),
	water = rgb(63, 142, 209),
	grass = rgb(79, 163, 82),
	electric = rgb(214, 190, 63),
} :: { [string]: RGB })

-- Used for a type with no entry above, so nothing renders as nil.
PetLook.FALLBACK_COLOR = rgb(155, 166, 186)

-- Band color by rarity order, lowest rarity first. A rarity past the end
-- reuses the last color.
PetLook.RARITY_PALETTE = table.freeze({
	rgb(155, 166, 186),
	rgb(76, 191, 115),
	rgb(76, 141, 255),
	rgb(192, 155, 255),
	rgb(255, 174, 69),
} :: { RGB })

-- Block edge in studs: BASE for the lowest rarity, plus STEP per rarity rank.
PetLook.SIZE = table.freeze({
	base = 2,
	step = 0.4,
})

-- Elemental feature by type id. Fire, electric and water have a visible
-- feature with an idle emitter; grass has an attachment but no emitter.
PetLook.FEATURES = table.freeze({
	fire = table.freeze({ attachment = "Flame", emits = true, color = rgb(255, 140, 40) }),
	electric = table.freeze({ attachment = "Sparks", emits = true, color = rgb(255, 236, 90) }),
	water = table.freeze({ attachment = "Droplets", emits = true, color = rgb(120, 200, 255) }),
	grass = table.freeze({ attachment = "Leaves", emits = false, color = rgb(120, 210, 110) }),
} :: { [string]: Feature })

PetLook.FALLBACK_FEATURE = table.freeze({
	attachment = "Feature",
	emits = false,
	color = rgb(255, 255, 255),
}) :: Feature

-- Variant looks (design/eggs-and-effects.md). Shiny lifts every color toward
-- white by this share; golden paints the body this color.
PetLook.SHINY_LIFT = 0.35
PetLook.GOLD = rgb(232, 179, 58)

-- The asset stage fills this: pet id to model id. Empty means every pet is
-- the placeholder block.
PetLook.MODEL_IDS = {} :: { [string]: string }

-- Rank of each rarity, 1 for the lowest, from config order.
local rarityRank: { [string]: number } = {}
do
	local ordered = table.clone(Config.rarities)
	table.sort(ordered, function(a, b)
		return a.order < b.order
	end)
	for rank, rarity in ordered do
		rarityRank[rarity.id] = rank
	end
end

local function lift(color: RGB, share: number): RGB
	return rgb(
		math.floor(color.r + (255 - color.r) * share + 0.5),
		math.floor(color.g + (255 - color.g) * share + 0.5),
		math.floor(color.b + (255 - color.b) * share + 0.5)
	)
end

function PetLook.typeColor(typeId: string): RGB
	return PetLook.TYPE_COLORS[typeId] or PetLook.FALLBACK_COLOR
end

function PetLook.rarityColor(rarityId: string): RGB
	local rank = rarityRank[rarityId]
	if rank == nil then
		return PetLook.FALLBACK_COLOR
	end
	return PetLook.RARITY_PALETTE[math.min(rank, #PetLook.RARITY_PALETTE)]
end

function PetLook.size(rarityId: string): number
	local rank = rarityRank[rarityId] or 1
	return PetLook.SIZE.base + PetLook.SIZE.step * (rank - 1)
end

function PetLook.feature(typeId: string): Feature
	return PetLook.FEATURES[typeId] or PetLook.FALLBACK_FEATURE
end

local function build(petId: string?, typeId: string, rarityId: string, variant: string?): Look
	local shiny = false
	local golden = false
	if variant ~= nil then
		-- Errors on an unknown variant id, like every config lookup.
		local _ = Config.variantById[variant]
		shiny = variant == "shiny"
		golden = variant == "golden"
	end
	local body = PetLook.typeColor(typeId)
	local band = PetLook.rarityColor(rarityId)
	if golden then
		body = PetLook.GOLD
	elseif shiny then
		body = lift(body, PetLook.SHINY_LIFT)
		band = lift(band, PetLook.SHINY_LIFT)
	end
	return table.freeze({
		petId = petId,
		typeId = typeId,
		rarityId = rarityId,
		variant = variant,
		body = body,
		band = band,
		size = PetLook.size(rarityId),
		feature = PetLook.feature(typeId),
		modelId = if petId ~= nil then PetLook.MODEL_IDS[petId] else nil,
		shiny = shiny,
		golden = golden,
	})
end

-- The look of one pet, with the variant the server sent (nil for normal).
-- A pet is never both shiny and golden: the variant is one id.
function PetLook.resolve(petId: string, variant: string?): Look
	local pet = Config.petById[petId]
	return build(petId, pet.type, pet.rarity, variant)
end

-- The look of a gym leader's pet, which has a type and a strength but no
-- pet id.
function PetLook.resolveType(typeId: string, rarityId: string?): Look
	local _ = Config.typeById[typeId]
	local rarity = rarityId
	if rarity == nil then
		local lowest = Config.rarities[1]
		for _, r in Config.rarities do
			if r.order < lowest.order then
				lowest = r
			end
		end
		rarity = lowest.id
	end
	return build(nil, typeId, rarity :: string, nil)
end

-- A short key that changes whenever the look changes, for callers that
-- rebuild a view only when the pet shown changes.
function PetLook.key(look: Look): string
	return string.format(
		"%s|%s|%s|%s",
		look.petId or "",
		look.typeId,
		look.rarityId,
		look.variant or ""
	)
end

return PetLook
