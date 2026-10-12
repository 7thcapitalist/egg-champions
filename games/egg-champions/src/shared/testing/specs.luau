--!strict
--[[
	specs: every spec module the test runner runs.

	Each task that adds a rule module adds its spec module here. A spec module
	returns a function that calls Runner.describe and Runner.it.
]]

local rules = script.Parent.Parent.rules
local ruleSpecs = rules.specs

return {
	ruleSpecs["Team.spec"],
	ruleSpecs["Coins.spec"],
	ruleSpecs["Hatch.spec"],
	ruleSpecs["PetIndex.spec"],
	ruleSpecs["Battle.spec"],
	ruleSpecs["Gym.spec"],
	ruleSpecs["Progression.spec"],
	ruleSpecs["Rebirth.spec"],
}
