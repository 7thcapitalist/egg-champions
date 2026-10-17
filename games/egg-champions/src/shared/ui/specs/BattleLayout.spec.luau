--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Layout = require(script.Parent.Parent.BattleLayout)
return function()
	Runner.describe("Responsive battle layout", function()
		Runner.it(
			"keeps HP, pets and move controls inside supported viewports without overlap",
			function()
				for _, size in
					{
						{ 1280, 720 },
						{ 958, 540 },
						{ 844, 390 },
						{ 720, 239 },
						{ 320, 720 },
						{
							390,
							844,
						},
					}
				do
					for _, top in { 0, 36, 58 } do
						local p = Layout.compute(size[1], size[2], top)
						local rects = {
							p.playerPanel,
							p.leaderPanel,
							p.playerPet,
							p.leaderPet,
							p.move1,
							p.move2,
							p.giveUp,
						}
						if not p.short then
							table.insert(rects, p.log)
						end
						for i, a in rects do
							Runner.expect(
								a.x >= 0
									and a.y >= top
									and a.w > 0
									and a.h > 0
									and a.x + a.w <= size[1] + 0.001
									and a.y + a.h <= size[2] + 0.001
							).toBeTrue()
							for j = i + 1, #rects do
								local b = rects[j]
								Runner.expect(
									a.x + a.w <= b.x + 0.001
										or b.x + b.w <= a.x + 0.001
										or a.y + a.h <= b.y + 0.001
										or b.y + b.h <= a.y + 0.001
								).toBeTrue()
							end
						end
						Runner.expect(p.move1.h >= 44 and p.move2.h >= 44 and p.giveUp.h >= 36)
							.toBeTrue()
					end
				end
			end
		)
		Runner.it("keeps portrait creatures readable under a large reported top inset", function()
			local p = Layout.compute(390, 844, 172)
			Runner.expect(p.playerPet.w >= 170 and p.leaderPet.w >= 170).toBeTrue()
			Runner.expect(p.playerPanel.y >= 172 and p.giveUp.y + p.giveUp.h <= 844).toBeTrue()
		end)
		Runner.it(
			"allocates much more space to the desktop creature than the old scaled 150px card",
			function()
				local p = Layout.compute(958, 540, 36)
				Runner.expect(p.playerPet.w > 200).toBeTrue()
			end
		)
	end)
end
