--!strict
--[[
	Tutorial: the first-time steps a new player is walked through, as pure
	rules. The server keeps the step in the profile (tutorialStep) and moves
	it on the events below; the client only shows the card and the pointer
	for the step the server sent.

	Steps, in order:
		1 click: "Click anywhere to earn coins", until the player can afford
		  the first egg.
		2 hatch: "Open EGGS and hatch your first pet". Points at the EGGS
		  button, then at the first egg's HATCH button once the shop is open.
		  The client closes the egg shop shortly after this step ends
		  (closesEggShop), so the pointer never targets a hidden button.
		3 equip: "Equip your new pet to your team". Points at PETS, then at
		  the first owned pet tile once the pets screen is open, then at
		  EQUIP once a pet is selected.
		4 gym: "Earn more and challenge the <type> Gym". Points at the first
		  world's gym.
		5 done: the card shows normal goals again.

	Events, each moving only its own step:
		coins: coins changed. click becomes hatch once coins reach the first
		  egg's price.
		hatched: an egg was hatched. click or hatch becomes equip (a hatch
		  proves the player could afford the egg).
		equipped: a pet was equipped. equip becomes gym.
		gym_started: a gym battle started. gym becomes done.
		skip: the player pressed SKIP. Any step becomes done.

	The first egg is the cheapest egg of the first world and the gym is that
	world's gym, both read from config. Nothing here changes its input.
]]

local Config = require(script.Parent.Parent.Config)

export type Step = number

export type Event = "coins" | "hatched" | "equipped" | "gym_started" | "skip"

-- The parts of a profile the tutorial reads.
export type State = {
	tutorialStep: any,
	coins: any,
	pets: any,
	team: any,
	badges: any,
	rebirths: any,
}

-- Which screens are open on the client, so the pointer can move from the
-- menu button to the button inside the screen.
export type Screens = {
	eggsOpen: boolean,
	petsOpen: boolean,
	-- True when an owned pet is selected on the pets screen.
	petSelected: boolean?,
}

export type Card = {
	step: Step,
	text: string,
	-- The pointer target name, or nil for no pointer. Names:
	-- "menu:<entry>" for a left menu button, "hatch:<eggId>" for an egg's
	-- HATCH button, "pet:first" for the first owned pet tile, "equip" for
	-- the EQUIP button, "gym:<worldId>" for a gym.
	target: string?,
	-- The one-line bar shown in the header of the open screen, or nil when
	-- no screen is open.
	screenText: string?,
}

local Tutorial = {}

Tutorial.steps = table.freeze({
	click = 1 :: Step,
	hatch = 2 :: Step,
	equip = 3 :: Step,
	gym = 4 :: Step,
	done = 5 :: Step,
})

Tutorial.events = table.freeze({
	coins = "coins" :: Event,
	hatched = "hatched" :: Event,
	equipped = "equipped" :: Event,
	gymStarted = "gym_started" :: Event,
	skip = "skip" :: Event,
})

local steps = Tutorial.steps

local firstWorld: Config.World = Config.worlds[1]
for _, world in Config.worlds do
	if world.index < firstWorld.index then
		firstWorld = world
	end
end

local firstEgg: Config.Egg = Config.eggById[firstWorld.eggs[1]]
for _, eggId in firstWorld.eggs do
	local egg = Config.eggById[eggId]
	if egg.price < firstEgg.price then
		firstEgg = egg
	end
end

-- The egg the tutorial points at and the world whose gym it points at.
Tutorial.firstEggId = firstEgg.id
Tutorial.gymWorldId = firstWorld.id

function Tutorial.firstEggPrice(): number
	return firstEgg.price
end

function Tutorial.gymName(): string
	return Config.typeById[firstWorld.gym.leader_type].name .. " Gym"
end

-- True when value is a step this module knows.
function Tutorial.isStep(value: any): boolean
	return type(value) == "number"
		and value == math.floor(value)
		and value >= steps.click
		and value <= steps.done
end

local function count(value: any): number
	if type(value) ~= "table" then
		return 0
	end
	local n = 0
	for _ in value do
		n += 1
	end
	return n
end

local function number(value: any): number
	return if type(value) == "number" and value == value then value else 0
end

-- The step for a profile that has none yet, such as a save from before the
-- tutorial existed. A player with no pet starts at the beginning; one who
-- already owns a pet skips steps 1 to 3; one who has already beaten a gym
-- or rebirthed has nothing left to learn.
function Tutorial.initialFor(state: State): Step
	if count(state.pets) == 0 then
		return steps.click
	end
	if count(state.badges) > 0 or number(state.rebirths) > 0 then
		return steps.done
	end
	return steps.gym
end

local function current(state: State): Step
	local step = state.tutorialStep
	if Tutorial.isStep(step) then
		return step
	end
	return Tutorial.initialFor(state)
end

-- The step after event happens in state. An event only moves the step it
-- belongs to; any other event leaves the step as it is.
function Tutorial.advance(state: State, event: Event): Step
	local step = current(state)
	if step == steps.done then
		return step
	end
	if event == Tutorial.events.skip then
		return steps.done
	end
	if event == Tutorial.events.coins then
		if step == steps.click and number(state.coins) >= firstEgg.price then
			return steps.hatch
		end
	elseif event == Tutorial.events.hatched then
		if step == steps.click or step == steps.hatch then
			return steps.equip
		end
	elseif event == Tutorial.events.equipped then
		if step == steps.equip then
			return steps.gym
		end
	elseif event == Tutorial.events.gymStarted then
		if step == steps.gym then
			return steps.done
		end
	end
	return step
end

-- The step a returning player resumes at: the saved step, moved past
-- anything the profile shows is already done (coins enough for the first
-- egg, a pet owned, a pet equipped). A missing or broken step is worked out
-- with initialFor.
function Tutorial.resume(state: State): Step
	local step = current(state)
	if step == steps.click and number(state.coins) >= firstEgg.price then
		step = steps.hatch
	end
	if step == steps.hatch and count(state.pets) > 0 then
		step = steps.equip
	end
	if step == steps.equip and count(state.team) > 0 then
		step = steps.gym
	end
	return step
end

-- True while the tutorial still has a step to show.
function Tutorial.active(step: any): boolean
	return Tutorial.isStep(step) and step ~= steps.done
end

-- The card line, pointer target and in-screen bar line for a step, or nil
-- once it is done. A target is only ever a button the player can see: with
-- the wrong screen open it is nil and the bar says what to do instead.
function Tutorial.card(step: any, screens: Screens): Card?
	if not Tutorial.active(step) then
		return nil
	end
	local anyOpen = screens.eggsOpen or screens.petsOpen
	if step == steps.click then
		return {
			step = step,
			text = "Click anywhere to earn coins",
			target = nil,
			screenText = if anyOpen then "Close this screen and click to earn coins" else nil,
		}
	elseif step == steps.hatch then
		if screens.eggsOpen then
			return {
				step = step,
				text = "Open EGGS and hatch your first pet",
				target = "hatch:" .. firstEgg.id,
				screenText = "Tap HATCH on the " .. firstEgg.name,
			}
		end
		return {
			step = step,
			text = "Open EGGS and hatch your first pet",
			target = if anyOpen then nil else "menu:Eggs",
			screenText = if anyOpen then "Close this screen, then open EGGS" else nil,
		}
	elseif step == steps.equip then
		if screens.petsOpen then
			local selected = screens.petSelected == true
			return {
				step = step,
				text = "Equip your new pet to your team",
				target = if selected then "equip" else "pet:first",
				screenText = if selected
					then "Tap EQUIP to add it to your team"
					else "Tap your new pet, then EQUIP",
			}
		end
		return {
			step = step,
			text = "Equip your new pet to your team",
			target = if anyOpen then nil else "menu:Pets",
			screenText = if anyOpen then "Your pet hatched. Next, open PETS" else nil,
		}
	end
	return {
		step = step,
		text = "Earn more and challenge the " .. Tutorial.gymName(),
		target = "gym:" .. firstWorld.id,
		screenText = if anyOpen
			then "Close this screen and walk to the " .. Tutorial.gymName()
			else nil,
	}
end

-- True when the client should close an open egg shop: the hatch step has
-- just ended (from the step before to the step now).
function Tutorial.closesEggShop(before: any, now: any): boolean
	return before == steps.hatch and Tutorial.isStep(now) and now ~= steps.hatch
end

return Tutorial
