--!strict
--[[
	HudInsets: reads the space Roblox itself uses on screen, as the inputs
	shared/ui/HudLayout takes.

	- GuiService.TopbarInset: the free part of Roblox's top bar, right of
	  its logo, menu, chat and voice buttons. The HUD's coins start right of
	  it. When the engine reports no inset, the old GetGuiInset height is
	  used and the HUD bar goes below it.
	- TextChatService's ChatWindowConfiguration: where the chat window sits.
	  HudLayout treats it as reserved, so the left menu sits below it. When
	  the window has not reported a size yet, HudLayout.chatEstimate stands
	  in. With chat off nothing is reserved.

	onChange calls back whenever either changes, so the HUD and the screens
	lay out again.
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local HudLayout =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ui"):WaitForChild("HudLayout"))

local HudInsets = {}

local function topbarInset(): Rect?
	local ok, value = pcall(function()
		return (GuiService :: any).TopbarInset
	end)
	if ok and typeof(value) == "Rect" and value.Max.Y > 0 then
		return value
	end
	return nil
end

local function chatConfig(): Instance?
	return TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
end

local function chatRect(screen: Vector2, top: number): HudLayout.Rect?
	local config = chatConfig()
	if config == nil then
		return nil
	end
	local ok, enabled, position, size = pcall(function()
		local c = config :: any
		return c.Enabled, c.AbsolutePosition, c.AbsoluteSize
	end)
	if not ok or enabled ~= true then
		return nil
	end
	if
		typeof(position) == "Vector2"
		and typeof(size) == "Vector2"
		and size.X > 0
		and size.Y > 0
	then
		return {
			name = "chat",
			x = math.floor(position.X),
			y = math.floor(position.Y),
			w = math.ceil(size.X),
			h = math.ceil(size.Y),
		}
	end
	return HudLayout.chatEstimate(screen.X, screen.Y, top)
end

-- The insets for a full screen of the given size.
function HudInsets.read(screen: Vector2): HudLayout.Insets
	local inset = topbarInset()
	if inset ~= nil then
		local top = inset.Max.Y
		return {
			left = inset.Min.X,
			right = inset.Max.X,
			top = top,
			chat = chatRect(screen, top),
		}
	end
	-- No row to share: an empty row (left at the screen's right edge) puts
	-- the HUD bar below the Roblox bar.
	local top = GuiService:GetGuiInset().Y
	return {
		left = screen.X,
		right = screen.X,
		top = top,
		chat = chatRect(screen, top),
	}
end

local function watch(instance: Instance, property: string, callback: () -> ())
	pcall(function()
		instance:GetPropertyChangedSignal(property):Connect(callback)
	end)
end

-- Calls callback whenever the top-bar inset or the chat window changes.
function HudInsets.onChange(callback: () -> ())
	watch(GuiService, "TopbarInset", callback)
	task.spawn(function()
		local config = chatConfig() or TextChatService:WaitForChild("ChatWindowConfiguration", 30)
		if config == nil then
			return
		end
		for _, property in { "Enabled", "AbsolutePosition", "AbsoluteSize" } do
			watch(config, property, callback)
		end
		callback()
	end)
end

return HudInsets
