--!strict
--[[
	HatchReveal: what the reveal after every hatch shows, and how long it
	stays.

	After the hatch animation, a centered card shows each pet that hatched:
	its model, name, rarity (in the rarity color), a Shiny or Golden badge
	when it has a variant, and "Click +N" with the Click Power the server sent.
	The card stays until the player taps the button or SECONDS pass.

	During the tutorial the egg shop closes after the hatch step ends, but
	only once no hatch is playing: shopCloses says when.

	SECONDS is display timing, not a game number. Every number shown comes
	from the server's reply or from config.
]]

local Format = require(script.Parent.Format)
local EggShopView = require(script.Parent.EggShopView)

local HatchReveal = {}

-- How long the reveal stays when the player does not tap, in seconds.
HatchReveal.SECONDS = 3
HatchReveal.BUTTON = "Nice!"

export type Entry = {
	petId: string,
	variant: string?,
	name: string,
	rarity: string,
	rarityName: string,
	-- "Shiny" or "Golden" (the variant's name from config), or nil.
	badge: string?,
	-- "Click +N", or nil when the server sent no Click Power.
	clickText: string?,
}

-- "Click +N" for a Click Power, or nil for none.
function HatchReveal.clickText(power: number?): string?
	if power == nil or power ~= power or power == math.huge or power == -math.huge then
		return nil
	end
	return "Click +" .. Format.abbreviate(power)
end

-- One entry per hatched pet, in hatch order.
function HatchReveal.entries(lines: { EggShopView.HatchLine }): { Entry }
	local entries: { Entry } = {}
	for _, line in lines do
		table.insert(entries, {
			petId = line.petId,
			variant = line.variant,
			name = line.name,
			rarity = line.rarity,
			rarityName = line.rarityName,
			badge = line.variantName,
			clickText = HatchReveal.clickText(line.clickPower),
		})
	end
	return entries
end

-- True when the reveal opened at openedAt should be gone at now: the player
-- tapped the button, or SECONDS have passed.
function HatchReveal.ended(openedAt: number, now: number, tapped: boolean): boolean
	return tapped or now - openedAt >= HatchReveal.SECONDS
end

-- Seconds left before the reveal closes by itself, never below 0.
function HatchReveal.remaining(openedAt: number, now: number): number
	return math.max(0, HatchReveal.SECONDS - (now - openedAt))
end

-- True when the tutorial should close the egg shop now: a close is waiting
-- (the hatch step ended), no hatch animation or reveal is playing, and the
-- step is not the hatch step again.
function HatchReveal.shopCloses(pending: boolean, hatching: boolean, onHatchStep: boolean): boolean
	return pending and not hatching and not onHatchStep
end

return HatchReveal
