--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Coins = require(ReplicatedStorage.Shared.rules.Coins)
local CollectionGoals = require(ReplicatedStorage.Shared.ui.CollectionGoals)
local EggShop = require(script.Parent.EggShop)
local Theme = require(script.Parent.Theme)
local State = require(script.Parent.State)
local Screens = require(script.Parent.Screens)
local Journey = {}
function Journey.mount(playerGui: PlayerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.Enabled, gui.DisplayOrder = "Journey", false, false, 30
	local shade = Instance.new("TextButton")
	shade.Name, shade.Text, shade.Size = "Shade", "", UDim2.fromScale(1, 1)
	shade.BackgroundColor3, shade.BackgroundTransparency = Theme.colors.backdrop, 0.2
	shade.Parent = gui
	local panel = Instance.new("Frame")
	panel.Name, panel.AnchorPoint = "Panel", Vector2.new(0.5, 0.5)
	panel.Position, panel.Size = UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.9, 0.85)
	panel.BackgroundColor3 = Theme.colors.panel
	panel.Parent = shade
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(660, 590)
	limit.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = panel
	local title = Theme.text({
		name = "Title",
		text = "YOUR JOURNEY",
		font = Theme.fonts.heading,
		size = 24,
		color = Theme.colors.gold,
		parent = panel,
	})
	title.Size, title.Position = UDim2.new(1, -80, 0, 52), UDim2.fromOffset(20, 8)
	title.TextScaled = true
	title.AutomaticSize = Enum.AutomaticSize.None
	local titleLimit = Instance.new("UITextSizeConstraint")
	titleLimit.MinTextSize, titleLimit.MaxTextSize = 16, 24
	titleLimit.Parent = title
	local close = Instance.new("TextButton")
	close.Name, close.Text = "Close", "X"
	close.Size, close.Position = UDim2.fromOffset(44, 44), UDim2.new(1, -54, 0, 10)
	close.BackgroundColor3, close.TextColor3 = Theme.colors.raised, Theme.colors.text
	close.Parent = panel
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name, scroll.BackgroundTransparency, scroll.BorderSizePixel = "Steps", 1, 0
	scroll.Position, scroll.Size = UDim2.fromOffset(20, 68), UDim2.new(1, -40, 1, -88)
	scroll.AutomaticCanvasSize, scroll.CanvasSize = Enum.AutomaticSize.Y, UDim2.new()
	scroll.ScrollBarThickness = 4
	scroll.Parent = panel
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 12)
	list.Parent = scroll
	local rows = {}
	local function row(name: string, order: number, height: number): TextLabel
		local label = Theme.text({
			name = name,
			text = "",
			size = 16,
			color = Theme.colors.text,
			parent = scroll,
		})
		label.Size, label.LayoutOrder = UDim2.new(1, -10, 0, height), order
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Top
		return label
	end
	for i, world in Config.worlds do
		rows[world.id] = row(world.id, 10 + i, 86)
	end
	local collectionTarget = row("CollectionTarget", 1, 80)
	local targetEgg: string? = nil
	local trackCollection = Instance.new("TextButton")
	trackCollection.Name, trackCollection.Text = "TrackCollection", "OPEN TARGET EGG"
	trackCollection.Size, trackCollection.LayoutOrder = UDim2.new(1, -10, 0, 44), 0
	trackCollection.BackgroundColor3, trackCollection.TextColor3 = Theme.colors.raised, Theme.colors.text
	trackCollection.FontFace, trackCollection.TextSize = Theme.fonts.label, 16
	trackCollection.Parent = scroll
	trackCollection.Activated:Connect(function()
		if targetEgg ~= nil then
			gui.Enabled = false
			EggShop.openAt(targetEgg)
		end
	end)
	local collectionRows: { [string]: TextLabel } = {}
	for i, egg in Config.eggs do
		collectionRows[egg.id] = row("Collection_" .. egg.id, 20 + i, 64)
	end
	local bonuses = row("Bonuses", 100, 90)
	local legacy = row("Legacy", 101, 92)
	legacy.Text = string.format(
		"LEGACY POWER\nEpic pets keep at least %d%% and Legendaries %d%% of your strongest owned pet's raw coin power. Automatic, permanent ownership benefit. New hatches raise the ceiling. Battle stats stay separate.",
		Config.constants.legacy_epic_floor * 100,
		Config.constants.legacy_legendary_floor * 100
	)
	legacy.TextColor3 = Theme.colors.muted
	State.subscribe(function(payload)
		local p = payload.profile
		local goals, target = CollectionGoals.build(p)
		targetEgg = if target ~= nil then target.eggId else nil
		trackCollection.Visible = target ~= nil
		trackCollection.Text = if target ~= nil then "OPEN " .. string.upper(target.name) else "OPEN TARGET EGG"
		collectionTarget.Text = if target ~= nil
			then string.format(
				"COLLECTION TRAIL\nNext: %s (%d/%d normal pets)\nMissing: %s",
				target.name,
				target.have,
				target.need,
				table.concat(target.missing, ", ")
			)
			else "COLLECTION TRAIL\nAll currently available sets are complete.\nUnlock the next world or inspect your collection in PETS > INDEX."
		for _, goal in goals do
			local label = collectionRows[goal.eggId]
			local status = if goal.complete
				then "COMPLETE"
				else if goal.unlocked then "IN PROGRESS" else "LOCKED THIS RUN"
			label.Text = string.format(
				"%s | %s | %d/%d\n+%g%% coins on completion (automatic; normal pets only)",
				goal.name,
				status,
				goal.have,
				goal.need,
				goal.bonusPercent
			)
			label.TextColor3 = if goal.complete
				then Theme.colors.gold
				else if goal.unlocked then Theme.colors.text else Theme.colors.muted
		end
		local badges = p.badges or {}
		local beaten = p.gymsBeaten or {}
		for i, world in Config.worlds do
			local earned = badges[world.id] == true
			local unlocked = i == 1 or beaten[Config.worlds[i - 1].id] == true
			local status = if beaten[world.id]
				then "CLEARED THIS RUN"
				elseif not unlocked then "LOCKED THIS RUN"
				elseif (p.feesPaid or {})[world.id] then "FEE PAID: CHALLENGE GYM"
				else "NEXT: PAY GYM FEE"
			local reward = if Config.worlds[i + 1]
				then "Unlock " .. Config.worlds[i + 1].name
				else "Complete all three badges"
			rows[world.id].Text = string.format(
				"%s  %s\n%s | Counter: %s\n%s",
				if earned then "[BADGE EARNED]" else "[BADGE TO EARN]",
				world.name,
				status,
				Config.typeById[world.gym.counter_type].name,
				reward
			)
			rows[world.id].TextColor3 = if earned then Theme.colors.gold else Theme.colors.text
		end
		bonuses.Text = string.format(
			"YOUR COIN BONUSES\nRebirth x%.2f | Collection x%.2f\nBadges stay forever; gym access resets on rebirth. Badges are achievements, not a hidden multiplier.",
			Coins.rebirthMultiplier(p.rebirths or 0),
			Coins.indexMultiplier(Coins.completedEggs(p.index or {}))
		)
	end)
	close.Activated:Connect(function()
		gui.Enabled = false
	end)
	shade.Activated:Connect(function()
		gui.Enabled = false
	end)
	Screens.register("Journey", function()
		gui.Enabled = true
	end)
	Screens.track(gui)
	gui.Parent = playerGui
end
return Journey
