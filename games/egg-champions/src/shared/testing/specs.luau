--!strict
--[[
	specs: every spec module the test runner runs.

	Each task that adds a rule module adds its spec module here. A spec module
	returns a function that calls Runner.describe and Runner.it.
]]

local rules = script.Parent.Parent.rules
local ruleSpecs = rules.specs
local netSpecs = script.Parent.Parent.net.specs
local worldSpecs = script.Parent.Parent.world.specs
local uiSpecs = script.Parent.Parent.ui.specs
local visualSpecs = script.Parent.Parent.visual.specs

return {
	ruleSpecs["Team.spec"],
	ruleSpecs["Coins.spec"],
	ruleSpecs["Hatch.spec"],
	ruleSpecs["PetIndex.spec"],
	ruleSpecs["Battle.spec"],
	ruleSpecs["Gym.spec"],
	ruleSpecs["Progression.spec"],
	ruleSpecs["Rebirth.spec"],
	ruleSpecs["Profile.spec"],
	ruleSpecs["PassEffects.spec"],
	netSpecs["Requests.spec"],
	worldSpecs["Layout.spec"],
	uiSpecs["Format.spec"],
	uiSpecs["NextGoal.spec"],
	uiSpecs["EggShopView.spec"],
	uiSpecs["PetsView.spec"],
	uiSpecs["BattleView.spec"],
	visualSpecs["PetLook.spec"],
	visualSpecs["Effects.spec"],
	visualSpecs["BattleEffects.spec"],
	visualSpecs["Progress.spec"],
}
