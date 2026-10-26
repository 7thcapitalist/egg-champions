--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Wild = require(Shared.rules.WildEncounter)
local Prisms = require(Shared.rules.Prisms)
local Layout = require(Shared.ui.WildLayout)
local Format = require(Shared.ui.Format)
local PetVisual = require(Shared.PetVisual)
local Theme = require(script.Parent.Theme)
local Screens = require(script.Parent.Screens)
local State = require(script.Parent.State)
local Visitor = require(script.Parent.Parent.Effects.WildVisitor)
local UI = {}
function UI.mount(parent: PlayerGui, remote: RemoteFunction)
	local gui = Instance.new("ScreenGui")
	gui.IgnoreGuiInset = true
	gui.Name, gui.DisplayOrder, gui.ResetOnSpawn = "WildEncounter", 25, false
	gui.Parent = parent
	local card = Instance.new("Frame")
	card.Name, card.BackgroundColor3, card.Visible = "FocusBattle", Theme.colors.panel, false
	card.Parent = gui
	Theme.panel(card)
	local title = Theme.text({
		name = "Title",
		text = "WILD ENCOUNTER",
		parent = card,
		font = Theme.fonts.heading,
		size = 16,
	})
	title.AutomaticSize, title.Size, title.Position =
		Enum.AutomaticSize.None, UDim2.new(1, -52, 0, 26), UDim2.fromOffset(8, 0)
	local function button(name: string, text: string, holder: Instance): TextButton
		local b = Instance.new("TextButton")
		b.Name, b.Text, b.FontFace, b.TextSize = name, text, Theme.fonts.label, 14
		b.BackgroundColor3, b.TextColor3, b.Parent = Theme.colors.raised, Theme.colors.text, holder
		Theme.panel(b)
		return b
	end
	local skip = button("Skip", "X", card)
	skip.Size, skip.Position = UDim2.fromOffset(44, 44), UDim2.new(1, -44, 0, 0)
	local portrait = Instance.new("Frame")
	portrait.Name, portrait.BackgroundTransparency, portrait.Parent = "Monster", 1, card
	portrait.Position = UDim2.fromOffset(8, 28)
	local info = Theme.text({ name = "Status", text = "", parent = card, size = 13 })
	info.AutomaticSize, info.TextWrapped = Enum.AutomaticSize.None, true
	info.Position, info.Size = UDim2.new(0.4, 0, 0, 30), UDim2.new(0.6, -12, 0, 60)
	local rail = Instance.new("Frame")
	rail.BackgroundColor3, rail.Parent = Theme.colors.raised, card
	rail.Size, rail.Position = UDim2.new(1, -24, 0, 12), UDim2.new(0, 12, 1, -74)
	local zone = Instance.new("Frame")
	zone.BackgroundColor3, zone.BorderSizePixel = Theme.colors.gold, 0
	zone.Position = UDim2.fromScale(0.5 - Config.constants.wild_focus_window, 0)
	zone.Size = UDim2.fromScale(Config.constants.wild_focus_window * 2, 1)
	zone.Parent = rail
	local marker = Instance.new("Frame")
	marker.Size, marker.AnchorPoint = UDim2.new(0, 4, 1, 6), Vector2.new(0.5, 0.5)
	marker.BackgroundColor3, marker.BorderSizePixel, marker.Parent = Theme.colors.text, 0, rail
	local action = button("Strike", "STRIKE IN GOLD", card)
	action.Size, action.Position = UDim2.new(0.58, -16, 0, 44), UDim2.new(0, 12, 1, -52)
	local capture = button("Capture", "PRISM", card)
	capture.Size, capture.Position = UDim2.new(0.42, -16, 0, 44), UDim2.new(0.58, 4, 1, -52)
	local invite = button("EncounterInvite", "WILD!", gui)
	invite.AnchorPoint, invite.Position, invite.Size =
		Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 64), UDim2.fromOffset(110, 44)
	invite.Visible = false
	local boost = Theme.text({
		name = "TrainingBoost",
		text = "",
		parent = gui,
		size = 14,
		color = Theme.colors.gold,
	})
	boost.AnchorPoint, boost.Position = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 112)
	boost.Visible = false
	local selector = button("PrismSelect", "BASIC", card)
	selector.Size, selector.Position = UDim2.new(0.6, -12, 0, 44), UDim2.new(0.4, 0, 0, 88)
	local tier = 1
	local inventory: any = nil
	local short = false
	local function count(): number
		if inventory then
			for _, p in inventory.items do
				if p.id == Config.prisms[tier].id then
					return p.count
				end
			end
		end
		return 0
	end
	local current: any = nil
	local resultText = ""
	local busy, opened = false, false
	local lastId: string? = nil
	local function layout()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local l = Layout.card(camera.ViewportSize.X, camera.ViewportSize.Y)
		card.Size, card.Position = UDim2.fromOffset(l.width, l.height), UDim2.fromOffset(l.x, l.y)
		portrait.Size = UDim2.new(0.4, -8, 0, l.portraitHeight)
		short = l.height < 200
		info.Position, info.Size =
			UDim2.new(0.4, 0, 0, if short then 28 else 30), UDim2.new(0.6, -12, 0, if short then 28 else 56)
		selector.Position = UDim2.new(0.4, 0, 0, if short then 56 else 88)
	end
	local function show()
		local e = current and current.encounter
		local available = e and workspace:GetServerTimeNow() < e.expiresAt
		local hidden = Screens.anyOpen()
		local boostLeft = if current
			then math.max(0, math.ceil((current.boostUntil or 0) - workspace:GetServerTimeNow()))
			else 0
		boost.Visible = boostLeft > 0 and not hidden and not (available and opened)
		boost.Text = string.format("TRAINING +%d%%  |  %ds", Config.constants.wild_training_bonus * 100, boostLeft)
		card.Visible = available and opened and not hidden or false
		invite.Visible = available and not opened and not hidden or false
		if not e then
			return
		end
		if lastId ~= e.id then
			lastId, resultText = e.id, ""
			PetVisual.view(portrait, e.petId, nil, nil)
		end
		local pet = Config.petById[e.petId]
		title.Text = "WILD " .. string.upper(pet.name)
		info.Text = if resultText ~= ""
			then string.format(
				"HP %d / %d | %d counters left\n%s",
				e.hp,
				e.maxHp,
				Config.constants.wild_max_misses - e.misses,
				resultText
			)
			else string.format(
				"HP %d / %d\n%d counters left\nWin: +%s coins & +%d%% training",
				e.hp,
				e.maxHp,
				Config.constants.wild_max_misses - e.misses,
				Format.abbreviate(e.rewardCoins or 0),
				Config.constants.wild_training_bonus * 100
			)
		if short then
			info.Text = string.format(
				"HP %d/%d | %d counters\n%s",
				e.hp,
				e.maxHp,
				Config.constants.wild_max_misses - e.misses,
				if resultText ~= ""
					then string.gsub(resultText, "\n", " ")
					else "+" .. Format.abbreviate(e.rewardCoins or 0) .. " coins"
			)
		end
		local p = Config.prisms[tier]
		selector.Text = string.format("%s x%d  >", string.upper(p.name), count())
		selector.Interactable = not busy
		action.Text = if e.phase == "fighting" then "STRIKE IN GOLD" else "DEFEATED!"
		action.Interactable = not busy and e.phase == "fighting"
		capture.Interactable = not busy and e.phase == "defeated"
		capture.Text = if e.phase == "captured"
			then "CAUGHT!"
			elseif e.phase == "escaped" then "ESCAPED"
			elseif count() == 0 then "GET PRISMS"
			else string.format("THROW %.2f%%", Prisms.chance(e.petId, Config.prisms[tier].id) * 100)
	end
	local function send(choice: string)
		local e = current and current.encounter
		if busy or not e then
			return
		end
		if choice == "capture" and count() == 0 then
			Screens.open(Screens.names.Prisms)
			return
		end
		busy = true
		show()
		if choice == "capture" then
			local prism = Instance.new("Frame")
			prism.Name, prism.Size, prism.Position = "CapturePrism", UDim2.fromOffset(24, 24), UDim2.new(1, -55, 1, -42)
			prism.Rotation, prism.BackgroundColor3, prism.Parent =
				45,
				(if tier == 3
					then Theme.colors.gold
					elseif tier == 2 then Theme.rarityColor("epic")
					else Theme.typeColor("water")),
				card
			local edge = Instance.new("UIStroke")
			edge.Color, edge.Thickness, edge.Parent = Theme.colors.gold, 3, prism
			TweenService:Create(prism, TweenInfo.new(0.45), {
				Position = UDim2.new(0.2, -12, 0, 48),
				Rotation = 225,
				Size = UDim2.fromOffset(8, 8),
				BackgroundTransparency = 1,
			}):Play()
			game:GetService("Debris"):AddItem(prism, 0.5)
		end
		local ok, reply = pcall(function()
			return remote:InvokeServer(e.id, choice, Config.prisms[tier].id)
		end)
		busy = false
		if ok and reply.ok then
			if choice == "skip" then
				opened = false
			elseif reply.phase == "captured" then
				resultText = "CAUGHT! Pets + Index updated"
				PetVisual.react(portrait, "attack", 0.45)
			elseif reply.phase == "escaped" then
				resultText = "Escaped. Training continues."
			elseif reply.phase == "defeated" then
				resultText = "+"
					.. Format.abbreviate(reply.rewardCoins or 0)
					.. string.format(" COINS!\n+%d%% training.", Config.constants.wild_training_bonus * 100)
				if reply.dropId then
					resultText ..= " +1 " .. string.upper(reply.dropId) .. " PRISM!"
				end
				PetVisual.react(portrait, "hit", 0.4)
				Visitor.react("hit")
			else
				resultText = if reply.result == "perfect" then "PERFECT HIT!" else "Counter! Aim for gold."
				PetVisual.react(portrait, if reply.result == "perfect" then "hit" else "attack", 0.3)
			end
		else
			resultText = if ok and reply.reason == "strike_cooldown"
				then "Wait for the next gold window."
				elseif ok and reply.reason == "no_prisms" then "No usable prism. Open the prism shop."
				else "Encounter unavailable. Training continues."
		end
		show()
	end
	selector.Activated:Connect(function()
		tier = tier % #Config.prisms + 1
		show()
	end)
	action.Activated:Connect(function()
		send("strike")
	end)
	capture.Activated:Connect(function()
		send("capture")
	end)
	skip.Activated:Connect(function()
		send("skip")
	end)
	invite.Activated:Connect(function()
		opened = true
		layout()
		show()
	end)
	State.subscribe(function(payload)
		current = payload.derived.wild
		inventory = payload.derived.prisms
		show()
	end)
	Screens.onChange(show)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	local lastSecond = -1
	RunService.RenderStepped:Connect(function()
		local second = math.floor(workspace:GetServerTimeNow())
		if second ~= lastSecond then
			lastSecond = second
			show()
		end
		if card.Visible then
			local e = current and current.encounter
			if e then
				marker.Position = UDim2.fromScale(Wild.focus(e.startedAt, workspace:GetServerTimeNow()), 0.5)
			end
			if e and workspace:GetServerTimeNow() >= e.expiresAt then
				show()
			end
		end
	end)
	layout()
end
return UI
