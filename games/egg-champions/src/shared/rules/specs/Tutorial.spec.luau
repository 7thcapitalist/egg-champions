--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Profile = require(script.Parent.Parent.Profile)
local Tutorial = require(script.Parent.Parent.Tutorial)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

local steps = Tutorial.steps
local events = Tutorial.events

-- A fresh profile at a given step and coin count.
local function at(step: number, coins: number?): any
	local profile: any = Profile.new()
	profile.tutorialStep = step
	profile.coins = coins or 0
	return profile
end

local function withPet(profile: any): any
	table.insert(profile.pets, { uid = "u1", petId = Config.pets[1].id })
	return profile
end

local allEvents = {
	events.coins,
	events.hatched,
	events.equipped,
	events.gymStarted,
}

local closed: Tutorial.Screens = { eggsOpen = false, petsOpen = false }

return function()
	describe("Tutorial", function()
		it("reads the first egg and the gym from config", function()
			local world = Config.worlds[1]
			expect(Tutorial.gymWorldId).toEqual(world.id)
			expect(table.find(world.eggs, Tutorial.firstEggId) ~= nil).toBeTrue()
			for _, eggId in world.eggs do
				expect(Tutorial.firstEggPrice() <= Config.eggById[eggId].price).toBeTrue()
			end
			expect(Tutorial.gymName()).toEqual(
				Config.typeById[world.gym.leader_type].name .. " Gym"
			)
		end)

		it("starts a new profile at the click step", function()
			expect(Profile.new().tutorialStep).toEqual(steps.click)
		end)

		it("moves from click to hatch only when the first egg is affordable", function()
			local price = Tutorial.firstEggPrice()
			expect(Tutorial.advance(at(steps.click, price - 1), events.coins)).toEqual(steps.click)
			expect(Tutorial.advance(at(steps.click, price), events.coins)).toEqual(steps.hatch)
			expect(Tutorial.advance(at(steps.click, price * 10), events.coins)).toEqual(steps.hatch)
		end)

		it("advances each step only on its own event", function()
			local price = Tutorial.firstEggPrice()
			local expected: { [number]: { [string]: number } } = {
				[steps.click] = {
					coins = steps.hatch,
					hatched = steps.equip,
					equipped = steps.click,
					gym_started = steps.click,
				},
				[steps.hatch] = {
					coins = steps.hatch,
					hatched = steps.equip,
					equipped = steps.hatch,
					gym_started = steps.hatch,
				},
				[steps.equip] = {
					coins = steps.equip,
					hatched = steps.equip,
					equipped = steps.gym,
					gym_started = steps.equip,
				},
				[steps.gym] = {
					coins = steps.gym,
					hatched = steps.gym,
					equipped = steps.gym,
					gym_started = steps.done,
				},
				[steps.done] = {
					coins = steps.done,
					hatched = steps.done,
					equipped = steps.done,
					gym_started = steps.done,
				},
			}
			for step, byEvent in expected do
				for _, event in allEvents do
					local got = Tutorial.advance(at(step, price), event)
					if got ~= byEvent[event] then
						error(
							string.format(
								"step %d on %s: got %d, expected %d",
								step,
								event,
								got,
								byEvent[event]
							)
						)
					end
				end
			end
		end)

		it("walks a new player through every step to done", function()
			local profile = at(steps.click, 0)
			profile.tutorialStep = Tutorial.advance(profile, events.coins)
			expect(profile.tutorialStep).toEqual(steps.click)
			profile.coins = Tutorial.firstEggPrice()
			profile.tutorialStep = Tutorial.advance(profile, events.coins)
			expect(profile.tutorialStep).toEqual(steps.hatch)
			profile.tutorialStep = Tutorial.advance(profile, events.hatched)
			expect(profile.tutorialStep).toEqual(steps.equip)
			profile.tutorialStep = Tutorial.advance(profile, events.equipped)
			expect(profile.tutorialStep).toEqual(steps.gym)
			profile.tutorialStep = Tutorial.advance(profile, events.gymStarted)
			expect(profile.tutorialStep).toEqual(steps.done)
			expect(Tutorial.active(profile.tutorialStep)).toBeFalse()
		end)

		it("ends from any step on skip, and leaves its input alone", function()
			for step = steps.click, steps.done do
				local profile = at(step, 0)
				expect(Tutorial.advance(profile, events.skip)).toEqual(steps.done)
				expect(profile.tutorialStep).toEqual(step)
			end
		end)

		it("resumes a returning player at the saved step", function()
			expect(Tutorial.resume(at(steps.click, 0))).toEqual(steps.click)
			expect(Tutorial.resume(at(steps.hatch, Tutorial.firstEggPrice()))).toEqual(steps.hatch)
			expect(Tutorial.resume(withPet(at(steps.equip, 0)))).toEqual(steps.equip)
			expect(Tutorial.resume(withPet(at(steps.gym, 0)))).toEqual(steps.gym)
			expect(Tutorial.resume(at(steps.done, 0))).toEqual(steps.done)
		end)

		it("resumes past what the profile shows is already done", function()
			expect(Tutorial.resume(at(steps.click, Tutorial.firstEggPrice()))).toEqual(steps.hatch)
			expect(Tutorial.resume(withPet(at(steps.hatch, 0)))).toEqual(steps.equip)
			local equipped = withPet(at(steps.equip, 0))
			equipped.team = { "u1" }
			expect(Tutorial.resume(equipped)).toEqual(steps.gym)
			-- Never moves the gym step on its own: that needs a battle.
			equipped.tutorialStep = steps.gym
			expect(Tutorial.resume(equipped)).toEqual(steps.gym)
		end)

		it("works out a missing or broken step from the profile", function()
			local fresh = at(steps.click, 0)
			fresh.tutorialStep = nil
			expect(Tutorial.resume(fresh)).toEqual(steps.click)
			local owner = withPet(at(steps.click, 0))
			owner.tutorialStep = 2.5
			expect(Tutorial.resume(owner)).toEqual(steps.gym)
			expect(Tutorial.isStep(2.5)).toBeFalse()
			expect(Tutorial.isStep(0)).toBeFalse()
			expect(Tutorial.isStep(steps.done + 1)).toBeFalse()
			expect(Tutorial.isStep("1")).toBeFalse()
		end)

		it("skips steps 1 to 3 for a player who already owns a pet", function()
			local owner = withPet(at(steps.click, 0))
			owner.tutorialStep = nil
			expect(Tutorial.initialFor(owner)).toEqual(steps.gym)
			owner.badges = { [Config.worlds[1].id] = true }
			expect(Tutorial.initialFor(owner)).toEqual(steps.done)
			owner.badges = {}
			owner.rebirths = 1
			expect(Tutorial.initialFor(owner)).toEqual(steps.done)
		end)

		it("migrates a v4 profile with no pets to the first step", function()
			local save: any = Profile.new()
			save.version = 4
			save.tutorialStep = nil
			local migrated = Profile.migrate(save)
			expect(migrated.version).toEqual(Profile.version)
			expect(migrated.tutorialStep).toEqual(steps.click)
			expect(Profile.validate(migrated)).toEqual({})
			expect(save.tutorialStep).toEqual(nil)
		end)

		it("migrates an old profile that owns a pet past steps 1 to 3", function()
			local save: any = withPet(Profile.new())
			save.version = 4
			save.tutorialStep = nil
			expect(Profile.migrate(save).tutorialStep).toEqual(steps.gym)
			save.badges = { [Config.worlds[1].id] = true }
			expect(Profile.migrate(save).tutorialStep).toEqual(steps.done)
			-- A version 1 save goes through every step and gets a step too.
			local v1: any = {
				version = 1,
				coins = 10,
				pets = { { uid = "u1", petId = Config.pets[1].id } },
				team = { "u1" },
				index = {},
				badges = {},
				rebirths = 0,
			}
			local migrated = Profile.migrate(v1)
			expect(migrated.tutorialStep).toEqual(steps.gym)
			expect(Profile.validate(migrated)).toEqual({})
		end)

		it("reports and repairs a broken step", function()
			local broken: any = Profile.new()
			broken.tutorialStep = 9
			local problems = Profile.validate(broken)
			expect(#problems).toEqual(1)
			expect(problems[1].kind).toEqual(Profile.problems.badTutorialStep)
			expect(problems[1].repairable).toBeTrue()
			local fixed, remaining = Profile.repair(broken)
			expect(fixed.tutorialStep).toEqual(steps.click)
			expect(remaining).toEqual({})
		end)

		it("shows the card and pointer for each step", function()
			local clickCard = Tutorial.card(steps.click, closed)
			assert(clickCard ~= nil, "expected a card")
			expect(clickCard.text).toEqual("Click anywhere to earn coins")
			expect(clickCard.target).toEqual(nil)

			local hatchCard = Tutorial.card(steps.hatch, closed)
			assert(hatchCard ~= nil, "expected a card")
			expect(hatchCard.text).toEqual("Open EGGS and hatch your first pet")
			expect(hatchCard.target).toEqual("menu:Eggs")
			local inShop = Tutorial.card(steps.hatch, { eggsOpen = true, petsOpen = false })
			assert(inShop ~= nil, "expected a card")
			expect(inShop.target).toEqual("hatch:" .. Tutorial.firstEggId)

			local equipCard = Tutorial.card(steps.equip, closed)
			assert(equipCard ~= nil, "expected a card")
			expect(equipCard.text).toEqual("Equip your new pet to your team")
			expect(equipCard.target).toEqual("menu:Pets")
			local inPets = Tutorial.card(steps.equip, { eggsOpen = false, petsOpen = true })
			assert(inPets ~= nil, "expected a card")
			expect(inPets.target).toEqual("equip")

			local gymCard = Tutorial.card(steps.gym, closed)
			assert(gymCard ~= nil, "expected a card")
			expect(gymCard.text).toEqual("Earn more and challenge the " .. Tutorial.gymName())
			expect(gymCard.target).toEqual("gym:" .. Tutorial.gymWorldId)

			expect(Tutorial.card(steps.done, closed)).toEqual(nil)
			expect(Tutorial.card(nil, closed)).toEqual(nil)
		end)
	end)
end
