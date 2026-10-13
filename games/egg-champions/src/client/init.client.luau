--!strict
--[[
	Client entry point.

	The client only sends requests and shows results. It:
	- keeps the latest state the server sent (UI/State) and builds the main
	  screen (UI/Main), where pressing the world view fires Click;
	- shows the server's Notice messages (such as why a portal refused);
	- builds the egg shop (UI/EggShop), where Hatch and Hatch x3 send BuyEgg;
	- builds the pets and index screen (UI/Pets), where Equip and Unequip send
	  their remotes;
	- opens the egg shop scrolled to a stand's egg when the player touches an
	  egg stand. The server decides whether any purchase goes through.

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

local UI = script:WaitForChild("UI")
local State = require(UI:WaitForChild("State"))
local Main = require(UI:WaitForChild("Main"))
local EggShop = require(UI:WaitForChild("EggShop"))
local Pets = require(UI:WaitForChild("Pets"))

State.start(remotes:WaitForChild(Remotes.names.ProfileChanged) :: RemoteEvent)
Main.mount(
	player:WaitForChild("PlayerGui") :: PlayerGui,
	remotes:WaitForChild(Remotes.names.Click) :: RemoteEvent
)
EggShop.mount(
	player:WaitForChild("PlayerGui") :: PlayerGui,
	remotes:WaitForChild(Remotes.names.BuyEgg) :: RemoteFunction
)
Pets.mount(
	player:WaitForChild("PlayerGui") :: PlayerGui,
	remotes:WaitForChild(Remotes.names.Equip) :: RemoteFunction,
	remotes:WaitForChild(Remotes.names.Unequip) :: RemoteFunction
)

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

local lastOpen = 0

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
	if EggShop.isOpen() or now - lastOpen < STAND_COOLDOWN_SECONDS then
		return
	end
	lastOpen = now
	EggShop.openAt(eggId)
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
