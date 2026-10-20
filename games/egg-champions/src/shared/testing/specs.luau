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
local analyticsSpecs = script.Parent.Parent.analytics.specs
local testingSpecs = script.Parent

return {
	ruleSpecs["Team.spec"],
	ruleSpecs["Coins.spec"],
	ruleSpecs["Legacy.spec"],
	ruleSpecs["Hatch.spec"],
	ruleSpecs["PetIndex.spec"],
	ruleSpecs["Battle.spec"],
	ruleSpecs["Gym.spec"],
	ruleSpecs["Progression.spec"],
	ruleSpecs["Rebirth.spec"],
	ruleSpecs["Profile.spec"],
	ruleSpecs["SaveOrder.spec"],
	ruleSpecs["PassEffects.spec"],
	ruleSpecs["Tutorial.spec"],
	netSpecs["Requests.spec"],
	worldSpecs["Layout.spec"],
	worldSpecs["Scenery.spec"],
	worldSpecs["SceneLayout.spec"],
	uiSpecs["Format.spec"],
	uiSpecs["NextGoal.spec"],
	uiSpecs["CollectionGoals.spec"],
	uiSpecs["EdgeArrow.spec"],
	uiSpecs["EggShopView.spec"],
	uiSpecs["HatchReveal.spec"],
	uiSpecs["EggShopLayout.spec"],
	uiSpecs["PetsLayout.spec"],
	uiSpecs["PetsView.spec"],
	uiSpecs["BattleView.spec"],
	uiSpecs["BattleLayout.spec"],
	uiSpecs["HudLayout.spec"],
	visualSpecs["PetLook.spec"],
	visualSpecs["PetPortrait.spec"],
	visualSpecs["Effects.spec"],
	visualSpecs["BattleEffects.spec"],
	visualSpecs["BattleMotion.spec"],
	visualSpecs["Progress.spec"],
	visualSpecs["VariantView.spec"],
	visualSpecs["ModelTemplates.spec"],
	visualSpecs["Followers.spec"],
	analyticsSpecs["Events.spec"],
	testingSpecs["Runner.spec"],
}
