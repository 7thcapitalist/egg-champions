--!strict
--[[
	PetIndex: what the pet index records.

	The index shape is the one Coins reads:
		index[petId] = { normal = true?, shiny = true?, golden = true? }
	Normal, shiny and golden hatches are tracked separately, as the spec says.

	An egg is complete when all pets_per_egg of its pets are seen as normal
	hatches. Shiny and golden hatches never count toward completion.

	The Fruit Edition is a collection tag, not a type or a rarity: it is every
	pet whose config edition is set.
]]

local Config = require(script.Parent.Parent.Config)
local Coins = require(script.Parent.Coins)

export type IndexEntry = Coins.IndexEntry
export type Index = Coins.PetIndex

local NORMAL = "normal"

local PetIndex = {}

-- An empty index.
function PetIndex.new(): Index
	return {}
end

-- The index slot a hatch fills: "normal" for nil, else the variant id.
local function slotOf(variant: string?): string
	if variant == nil then
		return NORMAL
	end
	return Config.variantById[variant].id
end

-- Marks petId seen in this variant. Returns true when that slot is new.
function PetIndex.record(index: Index, petId: string, variant: string?): boolean
	local _ = Config.petById[petId]
	local slot = slotOf(variant)
	local entry: any = index[petId]
	if entry == nil then
		entry = {}
		index[petId] = entry
	end
	if entry[slot] == true then
		return false
	end
	entry[slot] = true
	return true
end

-- True when petId has been seen in this variant (nil means normal).
function PetIndex.hasSeen(index: Index, petId: string, variant: string?): boolean
	local _ = Config.petById[petId]
	local entry: any = index[petId]
	return entry ~= nil and entry[slotOf(variant)] == true
end

-- True when all pets_per_egg normal pets of eggId are seen.
function PetIndex.isEggComplete(index: Index, eggId: string): boolean
	return Coins.isEggComplete(index, eggId)
end

-- How many eggs the index has completed.
function PetIndex.completedEggs(index: Index): number
	return Coins.completedEggs(index)
end

-- The seen Fruit Edition pet ids, in config order. A pet counts as seen in any
-- variant, since the Fruit page lists the characters collected.
function PetIndex.fruitEdition(index: Index): { string }
	local seen: { string } = {}
	for _, pet in Config.pets do
		if pet.edition ~= nil then
			local entry = index[pet.id]
			if
				entry ~= nil
				and (entry.normal == true or entry.shiny == true or entry.golden == true)
			then
				table.insert(seen, pet.id)
			end
		end
	end
	return seen
end

return PetIndex
