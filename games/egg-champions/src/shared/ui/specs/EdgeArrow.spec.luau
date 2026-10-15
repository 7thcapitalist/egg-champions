--!strict
local Runner = require(script.Parent.Parent.Parent.testing.Runner)
local EdgeArrow = require(script.Parent.Parent.EdgeArrow)

local describe = Runner.describe
local it = Runner.it
local expect = Runner.expect

local EPSILON = 1e-6
local SCREEN = { x = 1280, y = 720 }
local MARGIN = 40

return function()
	describe("EdgeArrow.place", function()
		it("hides the arrow while the point is on screen in front", function()
			local placed = EdgeArrow.place(SCREEN, { x = 600, y = 300 }, 10, MARGIN)
			expect(placed.visible).toBeFalse()
		end)

		it("shows it for a point in front but past the margin", function()
			local placed = EdgeArrow.place(SCREEN, { x = 1270, y = 360 }, 10, MARGIN)
			expect(placed.visible).toBeTrue()
			expect(placed.x).toBeCloseTo(SCREEN.x - MARGIN, EPSILON)
			expect(placed.y).toBeCloseTo(360, EPSILON)
			expect(placed.angle).toBeCloseTo(0, EPSILON)
		end)

		it("pins a far point to the edge, on the line from the centre", function()
			local placed = EdgeArrow.place(SCREEN, { x = 640, y = -5000 }, 10, MARGIN)
			expect(placed.visible).toBeTrue()
			expect(placed.x).toBeCloseTo(640, EPSILON)
			expect(placed.y).toBeCloseTo(MARGIN, EPSILON)
			expect(placed.angle).toBeCloseTo(-90, EPSILON)

			local corner = EdgeArrow.place(SCREEN, { x = 5000, y = 5000 }, 10, MARGIN)
			expect(corner.x <= SCREEN.x - MARGIN + EPSILON).toBeTrue()
			expect(corner.y <= SCREEN.y - MARGIN + EPSILON).toBeTrue()
			local onSide = math.abs(corner.x - (SCREEN.x - MARGIN)) < EPSILON
				or math.abs(corner.y - (SCREEN.y - MARGIN)) < EPSILON
			expect(onSide).toBeTrue()
		end)

		it("mirrors a point behind the camera", function()
			-- Behind and to the right projects to the left of the screen.
			local placed = EdgeArrow.place(SCREEN, { x = 200, y = 360 }, -10, MARGIN)
			expect(placed.visible).toBeTrue()
			expect(placed.x).toBeCloseTo(SCREEN.x - MARGIN, EPSILON)
			expect(placed.angle).toBeCloseTo(0, EPSILON)
		end)

		it("points down for a point straight behind", function()
			local placed = EdgeArrow.place(SCREEN, { x = 640, y = 360 }, -10, MARGIN)
			expect(placed.visible).toBeTrue()
			expect(placed.y).toBeCloseTo(SCREEN.y - MARGIN, EPSILON)
			expect(placed.angle).toBeCloseTo(90, EPSILON)
		end)
	end)
	describe("EdgeArrow.beside", function()
		local SIZE = 40
		local GAP = 8

		it("sits right of a button on the left half, pointing left", function()
			local rect = { x = 20, y = 300, w = 120, h = 40 }
			local placed = EdgeArrow.beside(SCREEN, rect, SIZE, GAP, 0)
			expect(placed.visible).toBeTrue()
			expect(placed.x).toBeCloseTo(20 + 120 + GAP + SIZE / 2, EPSILON)
			expect(placed.y).toBeCloseTo(320, EPSILON)
			expect(placed.angle).toBeCloseTo(180, EPSILON)
		end)

		it("sits left of a button on the right half, pointing right", function()
			local rect = { x = 1000, y = 100, w = 200, h = 60 }
			local placed = EdgeArrow.beside(SCREEN, rect, SIZE, GAP, 0)
			expect(placed.x).toBeCloseTo(1000 - GAP - SIZE / 2, EPSILON)
			expect(placed.y).toBeCloseTo(130, EPSILON)
			expect(placed.angle).toBeCloseTo(0, EPSILON)
		end)

		it("moves away from the button by the bounce", function()
			local rect = { x = 20, y = 300, w = 120, h = 40 }
			local still = EdgeArrow.beside(SCREEN, rect, SIZE, GAP, 0)
			local bounced = EdgeArrow.beside(SCREEN, rect, SIZE, GAP, 10)
			expect(bounced.x - still.x).toBeCloseTo(10, EPSILON)
		end)

		it("stays inside the viewport", function()
			local rect = { x = 1200, y = 700, w = 80, h = 40 }
			local placed = EdgeArrow.beside(SCREEN, rect, SIZE, GAP, 0)
			expect(placed.x <= SCREEN.x - SIZE / 2 + EPSILON).toBeTrue()
			expect(placed.y <= SCREEN.y - SIZE / 2 + EPSILON).toBeTrue()
		end)
	end)
end
