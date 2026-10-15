--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Config = require(script.Parent.Parent.Parent.Config)
local Tutorial = require(script.Parent.Parent.Parent.rules.Tutorial)
local Profile = require(script.Parent.Parent.Parent.rules.Profile)
local Rebirth = require(script.Parent.Parent.Parent.rules.Rebirth)
local HudLayout = require(script.Parent.Parent.HudLayout)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

-- The screens from the brief, plus the 844 x 390 phone.
local SCREENS = {
	{ width = 808, height = 432 },
	{ width = 1092, height = 432 },
	{ width = 1280, height = 720 },
	{ width = 1920, height = 1080 },
	{ width = 844, height = 390 },
}

-- Roblox top bars: none, the old 36 px bar with two buttons, and the 58 px
-- bar with logo, menu, chat and voice on the left and a button on the right.
-- right is the distance from the screen's right edge.
local TOPBARS = {
	{ name = "no top bar", left = 0, right = 0, top = 0 },
	{ name = "36 px top bar", left = 104, right = 0, top = 36 },
	{ name = "58 px top bar", left = 230, right = 60, top = 58 },
}

local function joined(list: { string }): string
	return table.concat(list, ", ")
end

local function insetsFor(
	screen: { width: number, height: number },
	bar: { left: number, right: number, top: number },
	chat: boolean
): HudLayout.Insets
	return {
		left = bar.left,
		right = screen.width - bar.right,
		top = bar.top,
		chat = if chat then HudLayout.chatEstimate(screen.width, screen.height, bar.top) else nil,
	}
end

-- Every line the goal card can show: the tutorial lines and NextGoal titles.
local function cardTexts(): { string }
	local texts = {}
	for _, step in
		{ Tutorial.steps.click, Tutorial.steps.hatch, Tutorial.steps.equip, Tutorial.steps.gym }
	do
		local card = Tutorial.card(step, { eggsOpen = false, petsOpen = false })
		if card ~= nil then
			table.insert(texts, card.text)
		end
	end
	local teamSize = Config.constants.team_size
	for more = 1, teamSize do
		table.insert(
			texts,
			string.format("Hatch %d more %s", more, if more == 1 then "pet" else "pets")
		)
	end
	table.insert(texts, string.format("Fill your team of %d", teamSize))
	table.insert(texts, "Rebirth")
	for _, world in Config.worlds do
		table.insert(texts, world.name .. " Gym")
	end
	for _, egg in Config.eggs do
		table.insert(texts, "Save for the " .. egg.name)
	end
	return texts
end

return function()
	describe("HudLayout.overlaps", function()
		it("finds a pair that shares area", function()
			local a = { name = "a", x = 0, y = 0, w = 10, h = 10 }
			local b = { name = "b", x = 5, y = 5, w = 10, h = 10 }
			local c = { name = "c", x = 100, y = 100, w = 10, h = 10 }
			expect(joined(HudLayout.overlaps({ a, b, c }))).toEqual("a/b")
		end)

		it("does not count touching edges", function()
			local a = { name = "a", x = 0, y = 0, w = 10, h = 10 }
			local b = { name = "b", x = 10, y = 0, w = 10, h = 10 }
			expect(#HudLayout.overlaps({ a, b })).toEqual(0)
		end)

		it("names parts past the screen edge", function()
			local a = { name = "a", x = 90, y = 0, w = 20, h = 10 }
			expect(joined(HudLayout.outside({ a }, 100, 100))).toEqual("a")
		end)
	end)

	describe("HudLayout.compute", function()
		local teamSize = Config.constants.team_size
		for _, screen in SCREENS do
			local width = screen.width
			local height = screen.height
			for _, bar in TOPBARS do
				for _, chat in { true, false } do
					local insets = insetsFor(screen, bar, chat)
					local label = string.format(
						"%d x %d, %s, chat %s",
						width,
						height,
						bar.name,
						if chat then "on" else "off"
					)
					for slots = 0, teamSize do
						it(
							string.format("has no overlaps at %s with %d team slots", label, slots),
							function()
								local layout = HudLayout.compute(width, height, slots, insets)
								expect(joined(HudLayout.overlaps(layout.parts))).toEqual("")
								expect(joined(HudLayout.blocked(layout))).toEqual("")
								expect(joined(HudLayout.outside(layout.parts, width, height))).toEqual(
									""
								)
							end
						)
					end
					it(
						string.format("keeps the coins clear of the Roblox buttons at %s", label),
						function()
							local layout = HudLayout.compute(width, height, 0, insets)
							if layout.inRow then
								expect(layout.coins.x >= bar.left + HudLayout.INSET_GAP).toBeTrue()
								expect(layout.coins.y + layout.coins.h <= bar.top).toBeTrue()
							else
								expect(layout.coins.y >= bar.top).toBeTrue()
							end
							expect(layout.contentTop >= bar.top).toBeTrue()
						end
					)
					it(
						string.format("puts the menu below 45%% and below the chat at %s", label),
						function()
							local layout = HudLayout.compute(width, height, teamSize, insets)
							expect(layout.menu.y >= height * HudLayout.MENU_BELOW).toBeTrue()
							local c = insets.chat
							if c ~= nil then
								expect(layout.menu.y >= c.y + c.h).toBeTrue()
							end
						end
					)
					it(
						string.format("keeps the goal card to a quarter of the screen at %s", label),
						function()
							local layout = HudLayout.compute(width, height, teamSize, insets)
							expect(layout.goal.h <= height / 4).toBeTrue()
						end
					)
					it(
						string.format("keeps the team bar low and off the character at %s", label),
						function()
							local layout = HudLayout.compute(width, height, teamSize, insets)
							local team = layout.team :: HudLayout.Rect
							-- The bottom quarter of the screen.
							expect(team.y >= height * 0.75).toBeTrue()
							if layout.compact then
								-- Bottom left, ending before the middle of the screen.
								expect(team.x).toEqual(layout.sizes.gutter)
								expect(team.x + team.w <= width / 2).toBeTrue()
							else
								local centre = team.x + team.w / 2
								expect(math.abs(centre - width / 2) <= 1).toBeTrue()
							end
						end
					)
				end
			end
		end

		it("puts coins, world and rebirths in the Roblox row when it has room", function()
			local insets = { left = 230, right = 1220, top = 58, chat = nil }
			local layout = HudLayout.compute(1280, 720, 0, insets)
			expect(layout.inRow).toBeTrue()
			expect(layout.coins.x).toEqual(238)
			expect(layout.contentTop).toEqual(58)
			local centre = layout.world.x + layout.world.w / 2
			expect(math.abs(centre - 640) <= 1).toBeTrue()
		end)

		it("puts the bar below the Roblox row when the row is too short", function()
			local layout =
				HudLayout.compute(1280, 720, 0, { left = 100, right = 1280, top = 20, chat = nil })
			expect(layout.inRow).toBeFalse()
			expect(layout.topBar.y).toEqual(20)
			expect(layout.contentTop).toEqual(20 + layout.sizes.topBar)
		end)

		it("keeps the old call with no insets working", function()
			local layout = HudLayout.compute(1280, 720, 0)
			expect(layout.inRow).toBeFalse()
			expect(layout.topBar.y).toEqual(0)
		end)

		it("gives the goal line two lines of at least 18 px text", function()
			expect(HudLayout.GOAL_TEXT >= 18).toBeTrue()
			for _, kind in { "normal", "compact" } do
				local s = (HudLayout.SIZES :: any)[kind] :: HudLayout.Sizes
				expect(s.goalLines).toEqual(2)
				expect(s.goalLine >= HudLayout.GOAL_TEXT).toBeTrue()
			end
		end)

		it("uses compact sizes on small screens only", function()
			expect(HudLayout.compute(844, 390, 0).compact).toBeTrue()
			expect(HudLayout.compute(808, 432, 0).compact).toBeTrue()
			expect(HudLayout.compute(1092, 432, 0).compact).toBeTrue()
			expect(HudLayout.compute(1280, 720, 0).compact).toBeFalse()
			expect(HudLayout.compute(1920, 1080, 0).compact).toBeFalse()
		end)

		it("leaves the team out when no slot shows", function()
			local layout = HudLayout.compute(1280, 720, 0)
			expect(layout.team == nil).toBeTrue()
			expect(#layout.parts).toEqual(5)
		end)

		it("has four menu entries and no Index", function()
			expect(joined(HudLayout.MENU)).toEqual("Eggs, Pets, Rebirth, Shop")
		end)
	end)

	describe("HudLayout goal text", function()
		it("wraps words onto lines", function()
			expect(HudLayout.lineCount("", 100, 18)).toEqual(0)
			expect(HudLayout.lineCount("Rebirth", 200, 18)).toEqual(1)
			local word = "abcdefghij"
			local one = HudLayout.textWidth(word, 18)
			expect(HudLayout.lineCount(word .. " " .. word, one + 1, 18)).toEqual(2)
		end)

		it("keeps the tutorial lines to 28 characters", function()
			for _, step in
				{
					Tutorial.steps.click,
					Tutorial.steps.hatch,
					Tutorial.steps.equip,
					Tutorial.steps.gym,
				}
			do
				local card =
					Tutorial.card(step, { eggsOpen = false, petsOpen = false }) :: Tutorial.Card
				expect(#card.text <= 28).toBeTrue()
			end
		end)

		for _, kind in { "normal", "compact" } do
			local s = (HudLayout.SIZES :: any)[kind] :: HudLayout.Sizes
			for _, text in cardTexts() do
				it(string.format("fits %q on the %s goal card", text, kind), function()
					expect(HudLayout.fitsGoal(text, s)).toBeTrue()
				end)
			end
		end
	end)

	describe("HudLayout.teamSlots", function()
		it("shows nothing before the first pet is equipped", function()
			expect(HudLayout.teamSlots(0, 3)).toEqual(0)
		end)

		it("shows one slot per equipped pet up to the team size", function()
			expect(HudLayout.teamSlots(1, 3)).toEqual(1)
			expect(HudLayout.teamSlots(2, 3)).toEqual(2)
			expect(HudLayout.teamSlots(3, 3)).toEqual(3)
			expect(HudLayout.teamSlots(40, 3)).toEqual(3)
		end)
	end)

	describe("HudLayout.menuShown", function()
		local cost = Rebirth.cost(0)

		it("shows only EGGS and PETS on minute one", function()
			local shown = HudLayout.menuShown({
				coins = 0,
				rebirthCost = cost,
				gymsBeaten = 0,
				tutorialDone = false,
			})
			expect(joined(shown)).toEqual("Eggs, Pets")
		end)

		it("adds SHOP once the tutorial is done", function()
			local shown = HudLayout.menuShown({
				coins = 0,
				rebirthCost = cost,
				gymsBeaten = 0,
				tutorialDone = true,
			})
			expect(joined(shown)).toEqual("Eggs, Pets, Shop")
		end)

		it("adds REBIRTH once a rebirth is affordable", function()
			local below = HudLayout.menuShown({
				coins = cost - 1,
				rebirthCost = cost,
				gymsBeaten = 0,
				tutorialDone = false,
			})
			expect(table.find(below, "Rebirth") == nil).toBeTrue()
			local shown = HudLayout.menuShown({
				coins = cost,
				rebirthCost = cost,
				gymsBeaten = 0,
				tutorialDone = false,
			})
			expect(joined(shown)).toEqual("Eggs, Pets, Rebirth")
		end)

		it("adds REBIRTH once the first gym is beaten", function()
			local shown = HudLayout.menuShown({
				coins = 0,
				rebirthCost = cost,
				gymsBeaten = 1,
				tutorialDone = true,
			})
			expect(joined(shown)).toEqual("Eggs, Pets, Rebirth, Shop")
		end)

		it("keeps the shorter menu clear of every other part", function()
			for _, screen in SCREENS do
				for count = 1, #HudLayout.MENU do
					local layout = HudLayout.compute(screen.width, screen.height, 3, nil, count)
					local s = layout.sizes
					expect(layout.menu.h).toEqual(count * s.menuButton + (count - 1) * s.menuGap)
					expect(joined(HudLayout.overlaps(layout.parts))).toEqual("")
					expect(joined(HudLayout.outside(layout.parts, screen.width, screen.height))).toEqual(
						""
					)
				end
			end
		end)
	end)

	describe("HudLayout.goldParts", function()
		it("puts exactly one gold element on screen for a new profile", function()
			local profile = Profile.new()
			local onboarding = Tutorial.active(profile.tutorialStep)
			local card = Tutorial.card(profile.tutorialStep, { eggsOpen = false, petsOpen = false })
			local beaten = 0
			for _ in profile.gymsBeaten do
				beaten += 1
			end
			local menu = HudLayout.menuShown({
				coins = profile.coins,
				rebirthCost = Rebirth.cost(profile.rebirths),
				gymsBeaten = beaten,
				tutorialDone = not onboarding,
			})
			local slots = HudLayout.teamSlots(#profile.team, Config.constants.team_size)
			local gold = HudLayout.goldParts({
				onboarding = onboarding,
				pointer = card ~= nil and card.target ~= nil,
				-- The first step's card shows the coins-for-the-first-egg bar.
				goalBar = card ~= nil and card.step == Tutorial.steps.click,
				goalReady = false,
				menu = menu,
				slots = slots,
			})
			expect(onboarding).toBeTrue()
			expect(#menu).toEqual(2)
			expect(#gold).toEqual(1)
		end)

		it("keeps the pointer the only gold element while the tutorial runs", function()
			local gold = HudLayout.goldParts({
				onboarding = true,
				pointer = true,
				goalBar = false,
				goalReady = true,
				menu = { "Eggs", "Pets", "Shop" },
				slots = 2,
			})
			expect(joined(gold)).toEqual("pointer")
		end)

		it("marks the goal, SHOP and click power once the tutorial is done", function()
			local gold = HudLayout.goldParts({
				onboarding = false,
				pointer = false,
				goalBar = false,
				goalReady = true,
				menu = { "Eggs", "Pets", "Shop" },
				slots = 1,
			})
			expect(joined(gold)).toEqual("goal, menu:Shop, perClick, slotPowers")
		end)
	end)
end
