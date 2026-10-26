--!strict
local RS = game:GetService("ReplicatedStorage")
local Marketplace = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local Shared = RS:WaitForChild("Shared")
local Config = require(Shared.Config)
local Prisms = require(Shared.rules.Prisms)
local Theme = require(script.Parent.Theme)
local Screens = require(script.Parent.Screens)
local State = require(script.Parent.State)
local UI = {}
function UI.mount(parent: PlayerGui, remote: RemoteFunction)
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.IgnoreGuiInset, gui.ResetOnSpawn, gui.DisplayOrder, gui.Enabled =
		"PrismShop", true, false, 30, false
	gui.Parent = parent
	local dim = Instance.new("TextButton")
	dim.Text, dim.Size, dim.BackgroundColor3, dim.BackgroundTransparency, dim.Parent =
		"", UDim2.fromScale(1, 1), Theme.colors.backdrop, 0.4, gui
	local card = Instance.new("Frame")
	card.Name, card.Active, card.AnchorPoint, card.Position =
		"Card", true, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
	card.Size, card.BackgroundColor3, card.Parent =
		UDim2.fromScale(0.9, 0.88), Theme.colors.panel, dim
	Theme.panel(card)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize, limit.Parent = Vector2.new(460, 390), card
	local title = Theme.text({
		name = "Title",
		text = "CAPTURE PRISMS",
		parent = card,
		size = 17,
		font = Theme.fonts.heading,
	})
	title.Position = UDim2.fromOffset(12, 10)
	local function button(name: string, text: string, holder: Instance): TextButton
		local b = Instance.new("TextButton")
		b.Name, b.Text, b.TextSize, b.FontFace = name, text, 13, Theme.fonts.label
		b.Size, b.BackgroundColor3, b.TextColor3, b.Parent =
			UDim2.fromOffset(128, 44), Theme.colors.raised, Theme.colors.text, holder
		Theme.panel(b)
		return b
	end
	local close = button("Close", "X", card)
	close.Size, close.Position = UDim2.fromOffset(44, 44), UDim2.new(1, -48, 0, 2)
	close.BackgroundColor3, close.TextColor3 = Theme.colors.close, Theme.colors.white
	local notice = Theme.text({
		name = "Notice",
		text = "Battle victories can drop prisms. Stronger monsters are harder to catch.",
		parent = card,
		size = 12,
	})
	notice.AutomaticSize, notice.TextWrapped = Enum.AutomaticSize.None, true
	notice.Position, notice.Size = UDim2.fromOffset(12, 48), UDim2.new(1, -24, 0, 36)
	local list = Instance.new("ScrollingFrame")
	list.Name, list.BackgroundTransparency, list.BorderSizePixel, list.ScrollBarThickness =
		"Items", 1, 0, 5
	list.Position, list.Size, list.CanvasSize =
		UDim2.fromOffset(12, 88), UDim2.new(1, -24, 1, -148), UDim2.new()
	list.AutomaticCanvasSize, list.Parent = Enum.AutomaticSize.Y, card
	local layout = Instance.new("UIListLayout")
	layout.Padding, layout.SortOrder, layout.Parent =
		UDim.new(0, 8), Enum.SortOrder.LayoutOrder, list
	local back = button("Back", "BACK", card)
	back.Position, back.Visible = UDim2.new(0, 12, 1, -52), false
	local buy = button("BuyPack", "CHECKING...", card)
	buy.Position, buy.Visible = UDim2.new(1, -140, 1, -52), false
	local rows: { [string]: any } = {}
	local data: any = nil
	local selected: any = nil
	local prices: { [number]: number } = {}
	local loading: { [number]: boolean } = {}
	local unavailable: { [number]: boolean } = {}
	local refresh = function() end
	local function stock(id: string): any
		if data then
			for _, p in data.items do
				if p.id == id then
					return p
				end
			end
		end
		return { count = 0, productId = 0, paid = 0 }
	end
	local function clearOdds()
		for _, child in list:GetChildren() do
			if child.Name == "Odds" then
				child:Destroy()
			end
		end
	end
	local function display(p: any?)
		selected = p
		clearOdds()
		for _, row in rows do
			row.frame.Visible = p == nil
		end
		back.Visible, buy.Visible = p ~= nil, p ~= nil
		if p then
			title.Text = string.upper(p.name) .. " ODDS"
			notice.Text = string.format(
				"Pack: %d prisms. One consumed per attempt. No guaranteed capture. Exact chances:",
				p.pack
			)
			for i, pet in Config.pets do
				local label = Theme.text({
					name = "Odds",
					text = string.format("%s: %.2f%%", pet.name, Prisms.chance(pet.id, p.id) * 100),
					parent = list,
					size = 13,
				})
				label.LayoutOrder, label.AutomaticSize, label.Size =
					i, Enum.AutomaticSize.None, UDim2.new(1, -8, 0, 24)
			end
		else
			title.Text = "CAPTURE PRISMS"
			notice.Text = string.format(
				"%g%% victory drop. Better areas drop better prisms.",
				Config.constants.wild_prism_drop_chance * 100
			)
		end
		list.CanvasPosition = Vector2.zero
		refresh()
	end
	for i, p in Config.prisms do
		local row = Instance.new("Frame")
		row.Name, row.LayoutOrder, row.Size, row.BackgroundColor3, row.Parent =
			p.id, i, UDim2.new(1, -6, 0, 116), Theme.colors.raised, list
		Theme.panel(row)
		local label = Theme.text({
			name = "Stock",
			text = "",
			parent = row,
			size = 14,
			font = Theme.fonts.label,
		})
		label.Position = UDim2.fromOffset(10, 8)
		local desc = Theme.text({
			name = "Effect",
			text = string.format(
				"%gx capture chance, capped at %g%%",
				p.multiplier,
				Config.constants.wild_capture_cap * 100
			),
			parent = row,
			size = 12,
		})
		desc.Position = UDim2.fromOffset(10, 33)
		local view = button("ViewPack", "PACK ODDS / BUY", row)
		view.Position, view.Size = UDim2.new(1, -146, 1, -52), UDim2.fromOffset(136, 44)
		view.Activated:Connect(function()
			display(p)
		end)
		if p.coin_price > 0 then
			local coins = button("BuyCoins", tostring(p.coin_price) .. " COINS", row)
			coins.Position, coins.Size = UDim2.new(0, 10, 1, -52), UDim2.fromOffset(124, 44)
			local busy = false
			coins.Activated:Connect(function()
				if busy then
					return
				end
				busy = true
				local ok, reply = pcall(function()
					return remote:InvokeServer(p.id)
				end)
				busy = false
				notice.Text = if ok and reply.ok
					then "+1 " .. p.name .. " Prism"
					else "Not enough coins. Battle victories can drop prisms too."
			end)
		end
		rows[p.id] = { frame = row, label = label }
	end
	refresh = function()
		for _, p in Config.prisms do
			local s = stock(p.id)
			rows[p.id].label.Text = string.format("%s | %d usable", p.name, s.count)
		end
		if selected then
			local s = stock(selected.id)
			local can = data and data.canPurchase and s.productId > 0
			buy.Interactable = can and prices[s.productId] ~= nil or false
			buy.Text = if not can or unavailable[s.productId]
				then "UNAVAILABLE"
				elseif prices[s.productId] then tostring(prices[s.productId]) .. " ROBUX"
				else "CHECKING..."
		end
	end
	local function pricesLoad()
		for _, p in Config.prisms do
			local id = stock(p.id).productId
			if id > 0 and not prices[id] and not loading[id] and not unavailable[id] then
				loading[id] = true
				task.spawn(function()
					local ok, info = pcall(function()
						return Marketplace:GetProductInfoAsync(id, Enum.InfoType.Product)
					end)
					if ok and info.IsForSale and type(info.PriceInRobux) == "number" then
						prices[id] = info.PriceInRobux
					else
						unavailable[id] = true
					end
					loading[id] = nil
					refresh()
				end)
			end
		end
	end
	buy.Activated:Connect(function()
		if not selected or not data or not data.canPurchase then
			return
		end
		local id = stock(selected.id).productId
		if id > 0 and prices[id] then
			pcall(function()
				Marketplace:PromptProductPurchase(Players.LocalPlayer, id)
			end)
		end
	end)
	back.Activated:Connect(function()
		display(nil)
	end)
	close.Activated:Connect(function()
		gui.Enabled = false
	end)
	dim.Activated:Connect(function()
		gui.Enabled = false
	end)
	Screens.track(gui)
	Screens.register(Screens.names.Prisms, function()
		Screens.close("Shop")
		table.clear(unavailable)
		gui.Enabled = true
		display(nil)
		pricesLoad()
	end)
	State.subscribe(function(payload)
		data = payload.derived.prisms
		refresh()
		if gui.Enabled then
			pricesLoad()
		end
	end)
end
return UI
