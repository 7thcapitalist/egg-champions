--!strict
-- Read-only measurements, not proof of input or visual approval.
-- Optional disabled QA script, never mapped into the shipping project.
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local player = Players.LocalPlayer
local screenName = script:GetAttribute("Screen")
local build = script:GetAttribute("BuildSha256")
assert(type(screenName) == "string", "set Screen to the visible screen being reviewed")
assert(type(build) == "string" and #build == 64, "set the exact reviewed build SHA-256")
local gui = player.PlayerGui:FindFirstChild(screenName)
assert(gui ~= nil and gui:IsA("ScreenGui") and gui.Enabled, "requested screen is not open")
local camera = workspace.CurrentCamera
assert(camera ~= nil, "viewport unknown")
local function visible(item: Instance): boolean
	local cursor: Instance? = item
	while cursor ~= nil and cursor ~= gui do
		if cursor:IsA("GuiObject") and not cursor.Visible then
			return false
		end
		cursor = cursor.Parent
	end
	return true
end
local controls = {}
local count = 0
for _, item in gui:GetDescendants() do
	if
		item:IsA("GuiObject")
		and visible(item)
		and (item:IsA("GuiButton") or item:IsA("TextLabel"))
	then
		count += 1
		if #controls < 300 then
			local label = item :: any
			table.insert(controls, {
				path = item:GetFullName(),
				position = { item.AbsolutePosition.X, item.AbsolutePosition.Y },
				size = { item.AbsoluteSize.X, item.AbsoluteSize.Y },
				text = if item:IsA("TextLabel") or item:IsA("TextButton") then label.Text else nil,
				text_fits = if item:IsA("TextLabel") or item:IsA("TextButton")
					then label.TextFits
					else nil,
			})
		end
	end
end
local insetA, insetB = GuiService:GetGuiInset()
print("[Beta mobile] " .. HttpService:JSONEncode({
	build_sha256 = build,
	screen = screenName,
	requested = { script:GetAttribute("RequestedWidth"), script:GetAttribute("RequestedHeight") },
	effective = { camera.ViewportSize.X, camera.ViewportSize.Y },
	gui_size = { gui.AbsoluteSize.X, gui.AbsoluteSize.Y },
	insets = { insetA.X, insetA.Y, insetB.X, insetB.Y },
	controls = controls,
	truncated = count > #controls,
	status = "measurements-only-review-pending",
}))
