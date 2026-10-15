--!strict
--[[
	EggShopView: what the egg shop screen shows, worked out with no engine
	calls so the headless tests can check it.

	- One card per egg in Config.eggs, in config order, so a new egg needs no
	  code change.
	- Each card lists the egg's pets, one per rarity, in rarity order, with the
	  hatch chance from Hatch.odds. Hatch.odds is the table the server rolls
	  with, built from config/rarities.json, so the screen can never advertise
	  odds the server does not roll. With the Lucky Eggs pass (which the server
	  reports) the card shows the boosted table the server then rolls.
	- A locked egg (Progression.eggUnlocked) says what unlocks it: beating the
	  gym of the world before.
	- The shop lists only eggs of unlocked worlds plus the next locked egg as
	  a teaser (shownCards).
	- An egg the player cannot afford is marked so the screen can mute it. It
	  is only a hint; the server decides every purchase.

	Nothing here changes the state it is given.
]]

local Config = require(script.Parent.Parent.Config)
local Hatch = require(script.Parent.Parent.rules.Hatch)
local Progression = require(script.Parent.Parent.rules.Progression)
local Format = require(script.Parent.Format)
local Tutorial = require(script.Parent.Parent.rules.Tutorial)

export type State = {
	coins: number,
	gymsBeaten: { [string]: boolean },
}

export type Options = {
	luckyEggs: boolean?,
}

export type PetLine = {
	petId: string,
	name: string,
	rarity: string,
	rarityName: string,
	chance: number,
	chanceText: string,
}

export type Card = {
	eggId: string,
	name: string,
	price: number,
	priceText: string,
	worldId: string,
	worldName: string,
	pets: { PetLine },
	locked: boolean,
	unlockText: string?,
	affordable: boolean,
	-- Coins still needed for one egg, 0 when affordable.
	short: number,
	-- True for the one locked egg the shop shows as a preview of what comes
	-- next (see shownCards).
	teaser: boolean,
}

export type HatchLine = {
	petId: string,
	name: string,
	rarity: string,
	rarityName: string,
	variant: string?,
	variantName: string?,
	newInIndex: boolean,
	-- The pet's Click Power as the server sent it, or nil when it did not.
	clickPower: number?,
}

local EggShopView = {}

-- How many eggs one Hatch x3 opens. Names the Triple Hatch pass's effect, the
-- same count the server checks (Hatch.TRIPLE_COUNT).
EggShopView.TRIPLE_COUNT = Hatch.TRIPLE_COUNT

-- Readable messages for the reasons the server can refuse a purchase.
local REASONS: { [string]: string } = {
	cannot_afford = "Not enough coins for this egg.",
	egg_locked = "This egg is locked. Beat the gym of the world before to open it.",
	no_triple_hatch_pass = "Hatch x3 needs the Triple Hatch pass.",
	rate_limited = "Slow down a little and try again.",
	no_profile = "Your save is still loading. Try again in a moment.",
	server_error = "Something went wrong on the server. Try again.",
	bad_choice = "The shop did not understand that request.",
	unknown_choice = "That egg is not in the shop.",
}

function EggShopView.reasonText(reason: any): string
	if type(reason) == "string" and REASONS[reason] ~= nil then
		return REASONS[reason]
	end
	return "The shop refused: " .. tostring(reason)
end

-- A chance as a percent with up to two decimals: 0.5 -> "50%", 0.045 -> "4.5%".
function EggShopView.percent(chance: number): string
	local hundredths = math.floor(chance * 10000 + 0.5)
	local whole = hundredths // 100
	local rest = hundredths % 100
	if rest == 0 then
		return string.format("%d%%", whole)
	elseif rest % 10 == 0 then
		return string.format("%d.%d%%", whole, rest // 10)
	end
	return string.format("%d.%02d%%", whole, rest)
end

local function rarityName(rarityId: string): string
	return Config.rarityById[rarityId].name
end

-- The odds lines of one egg, in rarity order.
function EggShopView.petLines(eggId: string, options: Options?): { PetLine }
	local byRarity: { [string]: Config.Pet } = {}
	for _, pet in Config.pets do
		if pet.egg == eggId then
			byRarity[pet.rarity] = pet
		end
	end
	local lines: { PetLine } = {}
	for _, entry in Hatch.odds({ luckyEggs = options ~= nil and options.luckyEggs == true }) do
		local pet = byRarity[entry.rarity]
		if pet ~= nil then
			table.insert(lines, {
				petId = pet.id,
				name = pet.name,
				rarity = entry.rarity,
				rarityName = rarityName(entry.rarity),
				chance = entry.chance,
				chanceText = EggShopView.percent(entry.chance),
			})
		end
	end
	return lines
end

-- What unlocks an egg, or nil when its world is the first.
function EggShopView.unlockText(eggId: string): string?
	local egg = Config.eggById[eggId]
	local world = Config.worldById[egg.world]
	for _, before in Config.worlds do
		if before.index == world.index - 1 then
			return string.format("Beat the %s gym to unlock", before.name)
		end
	end
	return nil
end

-- Every card, in config egg order.
function EggShopView.cards(state: State, options: Options?): { Card }
	local progress = Progression.newState()
	progress.coins = state.coins
	progress.gymsBeaten = state.gymsBeaten
	local cards: { Card } = {}
	for _, egg in Config.eggs do
		local world = Config.worldById[egg.world]
		local locked = not Progression.eggUnlocked(progress, egg.id)
		local short = math.max(0, egg.price - state.coins)
		table.insert(cards, {
			eggId = egg.id,
			name = egg.name,
			price = egg.price,
			priceText = Format.commas(egg.price) .. " coins",
			worldId = world.id,
			worldName = world.name,
			pets = EggShopView.petLines(egg.id, options),
			locked = locked,
			unlockText = if locked then EggShopView.unlockText(egg.id) else nil,
			affordable = short == 0,
			short = short,
			teaser = false,
		})
	end
	return cards
end

-- The cards the shop lists: every egg of an unlocked world, in config order,
-- plus the first locked egg as one teaser card. The rest stay hidden so the
-- list never fills with eggs the player cannot use yet.
function EggShopView.shownCards(state: State, options: Options?): { Card }
	local shown: { Card } = {}
	local teased = false
	for _, card in EggShopView.cards(state, options) do
		if not card.locked then
			table.insert(shown, card)
		elseif not teased then
			teased = true
			card.teaser = true
			table.insert(shown, card)
		end
	end
	return shown
end

-- How HATCH X3 looks on a card: gold ("accent") only when the player owns
-- the Triple Hatch pass, the egg is open and three are affordable, and
-- never while the tutorial runs (tutorialStep as the server sent it), so
-- the first minutes show no pass button in gold.
function EggShopView.tripleLook(
	tutorialStep: any,
	ownsTriple: boolean,
	locked: boolean,
	affordableThree: boolean
): "accent" | "muted"
	if Tutorial.active(tutorialStep) then
		return "muted"
	end
	return if ownsTriple and not locked and affordableThree then "accent" else "muted"
end

-- True when the note under the cards (variants and the pass) shows: not
-- while the tutorial runs.
function EggShopView.showsNote(tutorialStep: any): boolean
	return not Tutorial.active(tutorialStep)
end

-- The note under the cards: the variant odds and multipliers, from config.
function EggShopView.variantNote(): string
	local parts: { string } = {}
	for _, variant in Config.variants do
		table.insert(
			parts,
			string.format(
				"%s (%s, %sx clicks)",
				variant.name,
				EggShopView.percent(variant.hatch_chance),
				tostring(variant.click_mult)
			)
		)
	end
	local passName = Config.passById["triple_hatch"].name
	return string.format(
		"Any hatch can also be %s. Hatch x%d needs the %s pass.",
		table.concat(parts, " or "),
		EggShopView.TRIPLE_COUNT,
		passName
	)
end

-- One line per hatched pet, straight from the server's reply. Entries the
-- client does not recognise are skipped.
function EggShopView.hatchLines(reply: any): { HatchLine }
	local lines: { HatchLine } = {}
	if type(reply) ~= "table" or type(reply.pets) ~= "table" then
		return lines
	end
	for _, hatched in reply.pets do
		if type(hatched) == "table" and type(hatched.petId) == "string" then
			local ok, pet = pcall(function(): Config.Pet
				return Config.petById[hatched.petId]
			end)
			if ok and pet ~= nil then
				local variantId = if type(hatched.variant) == "string" then hatched.variant else nil
				local variantName: string? = nil
				if variantId ~= nil then
					local found, variant = pcall(function(): Config.Variant
						return Config.variantById[variantId]
					end)
					variantName = if found and variant ~= nil then variant.name else variantId
				end
				table.insert(lines, {
					petId = pet.id,
					name = pet.name,
					rarity = pet.rarity,
					rarityName = rarityName(pet.rarity),
					variant = variantId,
					variantName = variantName,
					newInIndex = hatched.newInIndex == true,
					clickPower = if type(hatched.clickPower) == "number"
							and hatched.clickPower == hatched.clickPower
						then hatched.clickPower
						else nil,
				})
			end
		end
	end
	return lines
end

return EggShopView
