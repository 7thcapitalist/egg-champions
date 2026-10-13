--!strict
--[[
	Remotes: the one list of every remote the client and server share.

	Both sides read names from here, so a typo is a nil index at the call site
	instead of a request that silently goes nowhere. The server creates every
	remote (see server/Services/Guard.luau) inside one folder in
	ReplicatedStorage; the client only waits for them.

	Kinds:
		"event": a RemoteEvent. Click goes up; ProfileChanged, Notice and
			ClickCredited come down. Notice carries a short message for the
			player, such as why a portal refused them. ClickCredited carries
			the coins the server added for one accepted click, so the click pop
			shows the credited amount and never a client guess.
		"function": a RemoteFunction. The client asks and the server answers
			with a result table, { ok = true, ... } or { ok = false, reason }.

	The only thing a client ever sends is a choice: which egg, which pet uid,
	which world, which battle session, which move. Never an amount.
]]

export type Kind = "event" | "function"

export type Name =
	"Click"
	| "BuyEgg"
	| "Equip"
	| "Unequip"
	| "PayGymFee"
	| "StartBattle"
	| "BattleMove"
	| "GiveUp"
	| "Rebirth"
	| "ProfileChanged"
	| "Notice"
	| "ClickCredited"

local Remotes = {}

-- The folder under ReplicatedStorage that holds every remote.
Remotes.FOLDER = "Remotes"

Remotes.names = table.freeze({
	Click = "Click" :: Name,
	BuyEgg = "BuyEgg" :: Name,
	Equip = "Equip" :: Name,
	Unequip = "Unequip" :: Name,
	PayGymFee = "PayGymFee" :: Name,
	StartBattle = "StartBattle" :: Name,
	BattleMove = "BattleMove" :: Name,
	GiveUp = "GiveUp" :: Name,
	Rebirth = "Rebirth" :: Name,
	ProfileChanged = "ProfileChanged" :: Name,
	Notice = "Notice" :: Name,
	ClickCredited = "ClickCredited" :: Name,
})

-- Every remote and its kind, in a fixed order.
Remotes.list = table.freeze({
	table.freeze({ name = Remotes.names.Click, kind = "event" :: Kind }),
	table.freeze({ name = Remotes.names.BuyEgg, kind = "function" :: Kind }),
	table.freeze({ name = Remotes.names.Equip, kind = "function" :: Kind }),
	table.freeze({ name = Remotes.names.Unequip, kind = "function" :: Kind }),
	table.freeze({ name = Remotes.names.PayGymFee, kind = "function" :: Kind }),
	table.freeze({ name = Remotes.names.StartBattle, kind = "function" :: Kind }),
	table.freeze({ name = Remotes.names.BattleMove, kind = "function" :: Kind }),
	table.freeze({ name = Remotes.names.GiveUp, kind = "function" :: Kind }),
	table.freeze({ name = Remotes.names.Rebirth, kind = "function" :: Kind }),
	table.freeze({ name = Remotes.names.ProfileChanged, kind = "event" :: Kind }),
	table.freeze({ name = Remotes.names.Notice, kind = "event" :: Kind }),
	table.freeze({ name = Remotes.names.ClickCredited, kind = "event" :: Kind }),
})

-- The kind of a remote, or nil for a name that is not a remote.
function Remotes.kindOf(name: string): Kind?
	for _, entry in Remotes.list do
		if entry.name == name then
			return entry.kind
		end
	end
	return nil
end

return Remotes
