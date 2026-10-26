--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Hatch = require(script.Parent.Parent.Parent.rules.Hatch)
local EggShopView = require(script.Parent.Parent.EggShopView)
local Tutorial = require(script.Parent.Parent.Parent.rules.Tutorial)

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
	describe("EggShopView auto hatch", function()
		it("starts one egg and prevents a second in-flight purchase", function()
			local initial = EggShopView.newAutoState()
			local started = EggShopView.startAuto(initial, "meadow")
			assert(started ~= nil, "auto start refused")
			local pending = EggShopView.beginAuto(started, "meadow", true)
			assert(pending ~= nil, "first request refused")
			expect(EggShopView.beginAuto(pending, "meadow", true)).toEqual(nil)
			expect(EggShopView.startAuto(pending, "other")).toEqual(nil)
			expect(initial.active).toBeFalse()
		end)

		it("stops on refusal, lock or insufficient coins", function()
			local started = EggShopView.startAuto(EggShopView.newAutoState(), "meadow")
			assert(started ~= nil, "auto start refused")
			expect(EggShopView.beginAuto(started, "meadow", false)).toEqual(nil)
			local pending = EggShopView.beginAuto(started, "meadow", true)
			assert(pending ~= nil, "first request refused")
			expect(EggShopView.finishAuto(pending, pending.token, false, true).active).toBeFalse()
			expect(EggShopView.finishAuto(pending, pending.token, true, false).active).toBeFalse()
		end)

		it("ignores a completed request after Stop", function()
			local started = EggShopView.startAuto(EggShopView.newAutoState(), "meadow")
			assert(started ~= nil, "auto start refused")
			local pending = EggShopView.beginAuto(started, "meadow", true)
			assert(pending ~= nil, "first request refused")
			local stopped = EggShopView.stopAuto(pending)
			expect(stopped.inFlight).toBeTrue()
			local late = EggShopView.finishAuto(stopped, pending.token, true, true)
			expect(late.active).toBeFalse()
			expect(late.inFlight).toBeFalse()
		end)

		it("continues only after a successful reveal and a fresh eligibility check", function()
			local started = EggShopView.startAuto(EggShopView.newAutoState(), "meadow")
			assert(started ~= nil, "auto start refused")
			local pending = EggShopView.beginAuto(started, "meadow", true)
			assert(pending ~= nil, "first request refused")
			local ready = EggShopView.finishAuto(pending, pending.token, true, true)
			expect(ready.active).toBeTrue()
			expect(ready.inFlight).toBeFalse()
			expect(EggShopView.beginAuto(ready, "other", true)).toEqual(nil)
		end)
	end)

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

		it("lists unlocked eggs plus the next locked egg as one teaser", function()
			local first = firstWorld()
			local shown = EggShopView.shownCards(newState(0))
			local unlocked = 0
			local teasers = 0
			for _, card in shown do
				if card.locked then
					teasers += 1
					expect(card.teaser).toBeTrue()
				else
					unlocked += 1
					expect(card.teaser).toBeFalse()
					expect(card.worldId).toEqual(first.id)
				end
			end
			expect(teasers).toEqual(1)
			expect(unlocked).toEqual(#first.eggs)
			expect(#shown < #Config.eggs).toBeTrue()
			-- The teaser is the first locked egg in config order.
			for _, card in EggShopView.cards(newState(0)) do
				if card.locked then
					expect(shown[#shown].eggId).toEqual(card.eggId)
					break
				end
			end
		end)

		it("shows no teaser once every egg is unlocked", function()
			local state = newState(0)
			for _, world in Config.worlds do
				state.gymsBeaten[world.id] = true
			end
			local shown = EggShopView.shownCards(state)
			expect(#shown).toEqual(#Config.eggs)
			for _, card in shown do
				expect(card.teaser).toBeFalse()
			end
		end)

		it("offers the same triple count the server accepts", function()
			expect(EggShopView.TRIPLE_COUNT).toEqual(Hatch.TRIPLE_COUNT)
		end)
	end)
	describe("EggShopView during the tutorial", function()
		it("keeps HATCH X3 neutral while the tutorial runs, even with the pass", function()
			for _, step in
				{
					Tutorial.steps.click,
					Tutorial.steps.hatch,
					Tutorial.steps.equip,
					Tutorial.steps.gym,
				}
			do
				expect(EggShopView.tripleLook(step, true, false, true)).toEqual("muted")
				expect(EggShopView.tripleLook(step, false, false, false)).toEqual("muted")
			end
		end)

		it("shows HATCH X3 in gold after the tutorial only when it would work", function()
			local done = Tutorial.steps.done
			expect(EggShopView.tripleLook(done, true, false, true)).toEqual("accent")
			expect(EggShopView.tripleLook(done, false, false, true)).toEqual("muted")
			expect(EggShopView.tripleLook(done, true, true, true)).toEqual("muted")
			expect(EggShopView.tripleLook(done, true, false, false)).toEqual("muted")
		end)

		it("hides the pass footer line while the tutorial runs", function()
			expect(EggShopView.showsNote(Tutorial.steps.click)).toBeFalse()
			expect(EggShopView.showsNote(Tutorial.steps.hatch)).toBeFalse()
			expect(EggShopView.showsNote(Tutorial.steps.done)).toBeTrue()
		end)
	end)
	describe("EggShopView card buttons and egg view", function()
		it("shows HATCH X3 only with the pass, after the tutorial, on open eggs", function()
			local done = Tutorial.steps.done
			expect(EggShopView.showsTriple(done, true, false)).toBeTrue()
			expect(EggShopView.showsTriple(done, false, false)).toBeFalse()
			expect(EggShopView.showsTriple(done, true, true)).toBeFalse()
			expect(EggShopView.showsTriple(done, false, true)).toBeFalse()
			for _, step in
				{
					Tutorial.steps.click,
					Tutorial.steps.hatch,
					Tutorial.steps.equip,
					Tutorial.steps.gym,
				}
			do
				expect(EggShopView.showsTriple(step, true, false)).toBeFalse()
			end
		end)

		it("never shows HATCH X3 on a locked card, for any player", function()
			for _, card in EggShopView.cards(newState(0)) do
				if card.locked then
					expect(EggShopView.showsTriple(Tutorial.steps.done, true, card.locked)).toBeFalse()
				end
			end
		end)

		it("writes only refusals on the card, never a hatch the reveal shows", function()
			expect(EggShopView.resultOnCard(true)).toBeFalse()
			expect(EggShopView.resultOnCard(false)).toBeTrue()
		end)

		it("shows the real egg only when its copy has parts and can be framed", function()
			expect(EggShopView.eggSource(true, true, 1, 10)).toEqual("model")
			expect(EggShopView.eggSource(true, true, 3, 0.5)).toEqual("model")
		end)

		it("falls back to the egg shape, never nothing", function()
			-- Not loaded yet, not a Model, an empty Model, or nothing to frame.
			expect(EggShopView.eggSource(false, false, 0, 0)).toEqual("shape")
			expect(EggShopView.eggSource(true, false, 2, 10)).toEqual("shape")
			expect(EggShopView.eggSource(true, true, 0, 10)).toEqual("shape")
			expect(EggShopView.eggSource(true, true, 2, 0)).toEqual("shape")
		end)

		it("frames the whole bounding box with room to spare", function()
			local fov = 30
			local distance = EggShopView.eggCameraDistance(2, 3, 2, fov, 1.15)
			local radius = math.sqrt(4 + 9 + 4) / 2
			-- The box's bounding sphere fits inside the view cone.
			expect(math.sin(math.rad(fov / 2)) * distance >= radius).toBeTrue()
			expect(distance > 0).toBeTrue()
			-- Bigger eggs sit further away.
			expect(EggShopView.eggCameraDistance(4, 6, 4, fov, 1.15) > distance).toBeTrue()
		end)

		it("gives no camera distance for an empty or broken box", function()
			expect(EggShopView.eggCameraDistance(0, 0, 0, 30, 1.15)).toEqual(0)
			expect(EggShopView.eggCameraDistance(0 / 0, 1, 1, 30, 1.15)).toEqual(0)
			expect(EggShopView.eggCameraDistance(math.huge, 1, 1, 30, 1.15)).toEqual(0)
			expect(EggShopView.eggCameraDistance(1, 1, 1, 0, 1.15)).toEqual(0)
		end)
	end)
end
