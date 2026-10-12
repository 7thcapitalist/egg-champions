--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Hatch = require(script.Parent.Parent.Parent.rules.Hatch)
local EggShopView = require(script.Parent.Parent.EggShopView)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

local function newState(coins: number): EggShopView.State
	return { coins = coins, gymsBeaten = {} }
end

local function firstWorld(): Config.World
	local lowest: Config.World? = nil
	for _, world in Config.worlds do
		if lowest == nil or world.index < lowest.index then
			lowest = world
		end
	end
	assert(lowest ~= nil, "config has no worlds")
	return lowest
end

-- Parses "4.5%" back to 0.045.
local function parsePercent(text: string): number
	local digits = string.match(text, "^([%d%.]+)%%$")
	assert(digits ~= nil, "not a percent: " .. text)
	return (tonumber(digits) :: number) / 100
end

return function()
	describe("EggShopView", function()
		it("has one card per egg, in config order", function()
			local cards = EggShopView.cards(newState(0))
			expect(#cards).toEqual(#Config.eggs)
			for position, egg in Config.eggs do
				expect(cards[position].eggId).toEqual(egg.id)
				expect(cards[position].name).toEqual(egg.name)
				expect(cards[position].price).toEqual(egg.price)
			end
		end)

		it("shows, for every egg, exactly the config hatch chance of each rarity", function()
			for _, card in EggShopView.cards(newState(0)) do
				expect(#card.pets).toEqual(#Config.rarities)
				local seen: { [string]: boolean } = {}
				for _, line in card.pets do
					local pet = Config.petById[line.petId]
					expect(pet.egg).toEqual(card.eggId)
					expect(pet.rarity).toEqual(line.rarity)
					expect(line.chance).toEqual(Config.rarityById[line.rarity].hatch_chance)
					expect(parsePercent(line.chanceText)).toBeCloseTo(line.chance, 1e-9)
					seen[line.rarity] = true
				end
				for _, rarity in Config.rarities do
					expect(seen[rarity.id] == true).toBeTrue()
				end
			end
		end)

		it("shows the same odds the server rolls, with and without Lucky Eggs", function()
			for _, lucky in { false, true } do
				local rolled = Hatch.odds({ luckyEggs = lucky })
				for _, card in EggShopView.cards(newState(0), { luckyEggs = lucky }) do
					for position, line in card.pets do
						expect(line.rarity).toEqual(rolled[position].rarity)
						expect(line.chance).toEqual(rolled[position].chance)
					end
				end
			end
		end)

		it("formats percents with up to two decimals", function()
			expect(EggShopView.percent(0.5)).toEqual("50%")
			expect(EggShopView.percent(0.045)).toEqual("4.5%")
			expect(EggShopView.percent(0.005)).toEqual("0.5%")
			expect(EggShopView.percent(0.0025)).toEqual("0.25%")
			expect(EggShopView.percent(1)).toEqual("100%")
		end)

		it("locks eggs outside the first world and says what unlocks them", function()
			local first = firstWorld()
			for _, card in EggShopView.cards(newState(0)) do
				if card.worldId == first.id then
					expect(card.locked).toBeFalse()
					expect(card.unlockText).toEqual(nil)
				else
					expect(card.locked).toBeTrue()
					expect(type(card.unlockText)).toEqual("string")
				end
			end
		end)

		it("opens the next world's eggs once the gym before is beaten", function()
			local first = firstWorld()
			local state = newState(0)
			state.gymsBeaten[first.id] = true
			for _, card in EggShopView.cards(state) do
				local world = Config.worldById[card.worldId]
				expect(card.locked).toEqual(world.index > first.index + 1)
			end
		end)

		it("marks eggs the player cannot afford and how much is missing", function()
			local egg = Config.eggs[1]
			local cards = EggShopView.cards(newState(egg.price - 1))
			expect(cards[1].affordable).toBeFalse()
			expect(cards[1].short).toEqual(1)
			cards = EggShopView.cards(newState(egg.price))
			expect(cards[1].affordable).toBeTrue()
			expect(cards[1].short).toEqual(0)
		end)

		it("shows every pet of a server reply, with rarity and variant", function()
			local egg = Config.eggs[1]
			local pets: { Config.Pet } = {}
			for _, pet in Config.pets do
				if pet.egg == egg.id then
					table.insert(pets, pet)
				end
			end
			local variant = Config.variants[1]
			local reply = {
				ok = true,
				eggId = egg.id,
				pets = {
					{ uid = "a", petId = pets[1].id, newInIndex = true },
					{ uid = "b", petId = pets[2].id, variant = variant.id },
					{ uid = "c", petId = pets[3].id },
				},
			}
			local lines = EggShopView.hatchLines(reply)
			expect(#lines).toEqual(3)
			expect(lines[1].name).toEqual(pets[1].name)
			expect(lines[1].rarityName).toEqual(Config.rarityById[pets[1].rarity].name)
			expect(lines[1].variant).toEqual(nil)
			expect(lines[1].newInIndex).toBeTrue()
			expect(lines[2].variantName).toEqual(variant.name)
			expect(#EggShopView.hatchLines({ ok = false })).toEqual(0)
			expect(#EggShopView.hatchLines({ pets = { { petId = "nobody" } } })).toEqual(0)
		end)

		it("turns server reasons into readable messages", function()
			expect(EggShopView.reasonText("cannot_afford")).toEqual(
				"Not enough coins for this egg."
			)
			expect(type(EggShopView.reasonText("something_new"))).toEqual("string")
		end)

		it("offers the same triple count the server accepts", function()
			expect(EggShopView.TRIPLE_COUNT).toEqual(Hatch.TRIPLE_COUNT)
		end)
	end)
end
