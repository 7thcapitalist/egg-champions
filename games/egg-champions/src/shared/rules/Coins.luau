--!strict
--[[
	Coins: how an equipped team turns into coins per click.

	The spec formula:

		coins per click = (1 + sum of equipped Click Power)
			x (1 + rebirth_coin_bonus x rebirths)
			x (1 + index_egg_bonus x completed eggs)
			x pass multiplier

	Every factor comes from Config. The pass multiplier is an input, so this
	module knows nothing about game passes; the caller multiplies whatever
	passes the player owns into one number.

	The pet index shape used here is the one the index rules record into:
	index[petId] = { normal = true?, shiny = true?, golden = true? }.
	Only normal hatches count toward completing an egg.
]]

local Config = require(script.Parent.Parent.Config)

-- An owned pet, as far as coins care: which pet it is and its variant, if any.
export type OwnedPet = {
	petId: string,
	variant: string?,
}

export type IndexEntry = {
	normal: boolean?,
	shiny: boolean?,
	golden: boolean?,
}

export type PetIndex = { [string]: IndexEntry }

export type ClickState = {
	-- The equipped pets, already resolved from uids by the caller.
	team: { OwnedPet },
	rebirths: number,
	completedEggs: number,
	-- Product of every owned pass's coin factor. Defaults to 1 when omitted.
	passMultiplier: number?,
	legacyAnchor: number?,
}

local Coins = {}

-- A pet's Click Power, including its variant multiplier.
function Coins.rawPowerOf(pet: OwnedPet): number
	local power = Config.petById[pet.petId].click_power
	local variant = pet.variant
	if variant ~= nil then
		power *= Config.variantById[variant].click_mult
	end
	return power
end

function Coins.legacyAnchor(owned: { OwnedPet }): number
	local strongest = 0
	for _, pet in owned do
		strongest = math.max(strongest, Coins.rawPowerOf(pet))
	end
	return strongest
end

function Coins.clickPowerOf(pet: OwnedPet, anchor: number?): number
	local rarity = Config.petById[pet.petId].rarity
	local fraction = if rarity == "epic"
		then Config.constants.legacy_epic_floor
		elseif rarity == "legendary" then Config.constants.legacy_legendary_floor
		else 0
	return math.max(Coins.rawPowerOf(pet), (anchor or 0) * fraction)
end

function Coins.teamClickPower(team: { OwnedPet }, anchor: number?): number
	local total = 0
	for _, pet in team do
		total += Coins.clickPowerOf(pet, anchor)
	end
	return total
end

function Coins.rebirthMultiplier(rebirths: number): number
	return 1 + Config.constants.rebirth_coin_bonus * rebirths
end

function Coins.indexMultiplier(completedEggs: number): number
	return 1 + Config.constants.index_egg_bonus * completedEggs
end

function Coins.perClick(state: ClickState): number
	local passMultiplier = state.passMultiplier or 1
	return (1 + Coins.teamClickPower(state.team, state.legacyAnchor))
		* Coins.rebirthMultiplier(state.rebirths)
		* Coins.indexMultiplier(state.completedEggs)
		* passMultiplier
end

-- True when the index holds a normal hatch of at least pets_per_egg pets of
-- this egg. Shiny and golden hatches do not count.
function Coins.isEggComplete(index: PetIndex, eggId: string): boolean
	local _ = Config.eggById[eggId]
	local seen = 0
	for _, pet in Config.pets do
		if pet.egg == eggId then
			local entry = index[pet.id]
			if entry ~= nil and entry.normal == true then
				seen += 1
			end
		end
	end
	return seen >= Config.constants.pets_per_egg
end

-- How many eggs the index has completed.
function Coins.completedEggs(index: PetIndex): number
	local count = 0
	for _, egg in Config.eggs do
		if Coins.isEggComplete(index, egg.id) then
			count += 1
		end
	end
	return count
end

return Coins
