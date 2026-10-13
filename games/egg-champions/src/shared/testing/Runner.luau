--!strict
--[[
	Runner: a tiny test runner for rule modules.

	It needs no Roblox service, so it runs both in Studio and headless under the
	Luau interpreter (see factory/tools/run_tests.py).

	A spec module returns a function. When that function runs, it calls
	Runner.describe and Runner.it to collect tests. Runner.run then runs every
	collected test inside pcall, so one failure never hides the rest.
]]

local Runner = {}

export type Spec = {
	name: string,
	fn: () -> (),
}

export type Failure = {
	name: string,
	message: string,
}

export type Result = {
	passed: number,
	failed: number,
	failures: { Failure },
}

type Test = {
	name: string,
	fn: () -> (),
}

local prefixes: { string } = {}
local collected: { Test } = {}

local function fullName(name: string): string
	if #prefixes == 0 then
		return name
	end
	return table.concat(prefixes, " > ") .. " > " .. name
end

function Runner.describe(name: string, fn: () -> ())
	table.insert(prefixes, name)
	local ok, err = pcall(fn)
	table.remove(prefixes)
	if not ok then
		error(err, 0)
	end
end

function Runner.it(name: string, fn: () -> ())
	table.insert(collected, { name = fullName(name), fn = fn })
end

local function show(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

-- True only for a number that is neither NaN nor infinite.
local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Returns nil when equal, or a short reason naming the first difference.
local function difference(a: any, b: any, path: string, seen: { [any]: any }): string?
	if a == b then
		return nil
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return string.format("at %s: got %s, expected %s", path, show(a), show(b))
	end
	if seen[a] == b then
		return nil
	end
	seen[a] = b
	for key, value in pairs(a) do
		local reason = difference(value, b[key], path .. "[" .. show(key) .. "]", seen)
		if reason then
			return reason
		end
	end
	for key, value in pairs(b) do
		if a[key] == nil then
			return string.format("at %s[%s]: missing, expected %s", path, show(key), show(value))
		end
	end
	return nil
end

export type Expectation = {
	toEqual: (expected: any) -> (),
	toBeCloseTo: (expected: number, epsilon: number?) -> (),
	toThrow: (pattern: string?) -> (),
	toBeTrue: () -> (),
	toBeFalse: () -> (),
}

function Runner.expect(value: any): Expectation
	local expectation = {}

	function expectation.toEqual(expected: any)
		local reason = difference(value, expected, "value", {})
		if reason then
			error("toEqual failed " .. reason, 2)
		end
	end

	function expectation.toBeCloseTo(expected: number, epsilon: number?)
		local margin = epsilon or 1e-6
		-- NaN and infinity never count as close: NaN compares false with
		-- everything, and inf - inf is NaN, so either could slip past the check.
		if not isFinite(value) or not isFinite(expected) or not isFinite(margin) then
			error(
				string.format(
					"toBeCloseTo failed: got %s, expected %s within %s (NaN and infinity are never close)",
					show(value),
					show(expected),
					show(margin)
				),
				2
			)
		end
		if not (math.abs(value - expected) <= margin) then
			error(
				string.format(
					"toBeCloseTo failed: got %s, expected %s within %s",
					show(value),
					show(expected),
					show(margin)
				),
				2
			)
		end
	end

	function expectation.toThrow(pattern: string?)
		if type(value) ~= "function" then
			error("toThrow needs a function, got " .. typeof(value), 2)
		end
		local ok, err = pcall(value)
		if ok then
			error("toThrow failed: the function did not throw", 2)
		end
		if pattern and not string.find(tostring(err), pattern, 1, true) then
			error(
				string.format(
					"toThrow failed: error %s does not contain %s",
					show(tostring(err)),
					show(pattern)
				),
				2
			)
		end
	end

	function expectation.toBeTrue()
		if value ~= true then
			error("toBeTrue failed: got " .. show(value), 2)
		end
	end

	function expectation.toBeFalse()
		if value ~= false then
			error("toBeFalse failed: got " .. show(value), 2)
		end
	end

	return expectation
end

function Runner.run(specs: { Spec }): Result
	local result: Result = { passed = 0, failed = 0, failures = {} }

	local function fail(name: string, message: any)
		result.failed += 1
		table.insert(result.failures, { name = name, message = tostring(message) })
	end

	for _, spec in specs do
		table.clear(prefixes)
		table.clear(collected)
		local ok, err = pcall(spec.fn)
		local tests = table.clone(collected)
		table.clear(collected)
		table.clear(prefixes)
		if not ok then
			fail(spec.name, "could not collect tests: " .. tostring(err))
		end
		for _, test in tests do
			local passed, message = pcall(test.fn)
			if passed then
				result.passed += 1
			else
				fail(spec.name .. ": " .. test.name, message)
			end
		end
	end

	return result
end

return Runner
