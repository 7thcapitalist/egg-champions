--!strict
--[[
	Example: a placeholder rule module that shows the pattern.

	Rule modules require no Roblox service and touch no `game` global, so they
	run headless under the test runner. Numbers come in as arguments (from
	Config at the call site), never written here.

	Delete this module and its spec in the first task that adds a real rule.
]]

local Example = {}

function Example.add(a: number, b: number): number
	return a + b
end

function Example.scale(values: { number }, factor: number): { number }
	local out = table.create(#values)
	for i, value in values do
		out[i] = value * factor
	end
	return out
end

return Example
