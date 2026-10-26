--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local Layout = require(script.Parent.Parent.WildLayout)
return function()
	Runner.describe("wild focus battle reachability", function()
		Runner.it("fits portrait and short landscape while leaving side control space", function()
			for _, size in { { 320, 720 }, { 390, 844 }, { 750, 381 }, { 720, 239 }, { 1280, 720 } } do
				local l = Layout.card(size[1], size[2])
				Runner.expect(
					l.x >= 0 and l.y >= 0 and l.x + l.width <= size[1] and l.y + l.height <= size[2]
				)
					.toBeTrue()
				if size[1] >= 720 then
					Runner.expect(l.x >= 180).toBeTrue()
				end
				local offer = Layout.offer(
					size[1],
					size[2],
					{ { x = 0, y = 0, width = size[1], height = 64 } }
				)
				Runner.expect(offer ~= nil).toBeTrue()
				if offer then
					Runner.expect(offer.y + offer.height <= size[2] - 120).toBeTrue()
				end
			end
			Runner.expect(Layout.offer(320, 239, { { x = 0, y = 0, width = 320, height = 239 } }))
				.toEqual(nil)
		end)
	end)
end
