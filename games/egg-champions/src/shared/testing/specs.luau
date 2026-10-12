--!strict
--[[
	specs: every spec module the test runner runs.

	Each task that adds a rule module adds its spec module here. A spec module
	returns a function that calls Runner.describe and Runner.it.
]]

local rules = script.Parent.Parent.rules

return {
	rules["Example.spec"],
}
