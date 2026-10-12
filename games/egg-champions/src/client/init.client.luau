--!strict
--[[
	Client entry point.

	The client only sends requests and shows results. For now it:
	- shows the server's Notice messages (such as why a portal refused);
	- buys from egg stands: touching a stand's pad fires the BuyEgg remote for
	  that stand's egg. Task 11 replaces this with opening the shop screen
	  filtered to that egg. The server decides whether the purchase goes
	  through.

	The cooldown below is touch debounce timing, not a game number.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local STAND_TAG = "EggStand"
local STAND_COOLDOWN_SECONDS = 2

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild(Remotes.FOLDER)

local function show(title: string, text: string)
	local ok = pcall(function()
		StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = 4 })
	end)
	if not ok then
		print(string.format("[%s] %s", title, text))
	end
end

local notice = remotes:WaitForChild(Remotes.names.Notice) :: RemoteEvent
notice.OnClientEvent:Connect(function(message: any)
	if type(message) == "string" then
		show("Portal", message)
	end
end)

local buyEgg = remotes:WaitForChild(Remotes.names.BuyEgg) :: RemoteFunction
local busy = false
local lastBuy = 0

local function onStandTouched(stand: BasePart, hit: BasePart)
	local character = player.Character
	if character == nil or not hit:IsDescendantOf(character) then
		return
	end
	local eggId = stand:GetAttribute("EggId")
	if type(eggId) ~= "string" then
		return
	end
	local now = os.clock()
	if busy or now - lastBuy < STAND_COOLDOWN_SECONDS then
		return
	end
	busy = true
	lastBuy = now
	local ok, result = pcall(function(): any
		return buyEgg:InvokeServer(eggId)
	end)
	busy = false
	if not ok or type(result) ~= "table" then
		show("Egg", "The shop did not answer. Try again.")
	elseif result.ok then
		show(
			"Egg",
			string.format(
				"Hatched %d pet(s)",
				if type(result.pets) == "table" then #result.pets else 0
			)
		)
	else
		show("Egg", "Cannot buy: " .. tostring(result.reason))
	end
end

local hooked: { [Instance]: boolean } = {}
local function hook(instance: Instance)
	if hooked[instance] or not instance:IsA("BasePart") then
		return
	end
	hooked[instance] = true
	local stand = instance :: BasePart
	stand.Touched:Connect(function(hit: BasePart)
		onStandTouched(stand, hit)
	end)
end

for _, instance in CollectionService:GetTagged(STAND_TAG) do
	hook(instance)
end
CollectionService:GetInstanceAddedSignal(STAND_TAG):Connect(hook)
CollectionService:GetInstanceRemovedSignal(STAND_TAG):Connect(function(instance: Instance)
	hooked[instance] = nil
end)

print("client ready")
