--!strict
--[[
	Format: the one place numbers are turned into text for the UI.

	Format.abbreviate keeps short numbers whole and shortens large ones to one
	decimal with a suffix: 950, 1.2K, 3.4M, 5.6B. It always rounds down, so the
	screen never shows more coins than the player has, and a trailing ".0" is
	dropped (1K, not 1.0K). Past the last suffix it falls back to scientific
	notation.

	The suffix list is display text, not a game number, so it lives here.
]]

local Format = {}

-- Each step is a thousand times the one before it.
Format.SUFFIXES = table.freeze({ "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" })

local STEP = 1000
-- Absorbs float error so 1.2e3 / 1e3 * 10 does not floor to 11.
local NUDGE = 1e-9

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

-- Rounds toward zero to one decimal and drops a trailing ".0".
local function oneDecimal(value: number): string
	local tenths = math.floor(value * 10 + NUDGE)
	if tenths % 10 == 0 then
		return tostring(tenths // 10)
	end
	return string.format("%d.%d", tenths // 10, tenths % 10)
end

-- Whole number with thousands separators, rounded down: 1250 -> "1,250".
function Format.commas(value: number): string
	if not isFinite(value) then
		return tostring(value)
	end
	local negative = value < 0
	local whole = tostring(math.floor(math.abs(value) + NUDGE))
	local grouped = whole:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if grouped:sub(1, 1) == "," then
		grouped = grouped:sub(2)
	end
	return if negative then "-" .. grouped else grouped
end

-- Short form of a number for the HUD: 950, 1.2K, 3.4M, 5.6B.
function Format.abbreviate(value: number): string
	if not isFinite(value) then
		return tostring(value)
	end
	if value < 0 then
		return "-" .. Format.abbreviate(-value)
	end
	if value < STEP then
		return tostring(math.floor(value + NUDGE))
	end
	local scaled = value
	for _, suffix in Format.SUFFIXES do
		scaled /= STEP
		if scaled < STEP then
			local text = oneDecimal(scaled)
			-- 999.95K rounds down to 999.9K, so the text never reaches 1000.
			return text .. suffix
		end
	end
	return string.format("%.1e", value)
end

return Format
