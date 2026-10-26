--!strict
-- Authored scenic footprints shared by the scatter planner and geometry builder.
local SceneLayout = {}
export type Scene = {
	key: string,
	x: number,
	z: number,
	radius: number,
	height: number,
	startX: number,
	startZ: number,
	endX: number,
	endZ: number,
	endY: number,
	accessX: number,
	accessZ: number,
}
function SceneLayout.forTheme(theme: string): { Scene }
	local coast = theme == "coral_coast"
	local volcano = theme == "ember_volcano"
	local gardenHeight = if coast then 2 else if volcano then 5 else 4
	local vistaHeight = if coast then 3 else if volcano then 8 else 6
	return {
		{
			key = "garden",
			x = 46,
			z = 65,
			radius = 19,
			height = gardenHeight,
			startX = 42,
			startZ = 36,
			endX = 44,
			endZ = 48,
			endY = gardenHeight + 0.4,
			accessX = 42,
			accessZ = 40,
		},
		{
			key = "vista",
			x = 65,
			z = -55,
			radius = 22,
			height = vistaHeight,
			startX = 62,
			startZ = -15,
			endX = 64,
			endZ = -38,
			endY = vistaHeight + 1.5,
			accessX = 60,
			accessZ = 0,
		},
	}
end
return SceneLayout
