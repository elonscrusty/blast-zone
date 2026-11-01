--!strict
-- Pure part list for the Sweeper Cart: a little ride-on sweeper with a front brush roller and a
-- back bin that fills with ash (no Roblox types: Lune tests it).
-- Cart space: origin = middle of the ground under the cart, +Y up, -Z is forward (the brush end).
-- About 3.2 wide, 6 long, 4.1 tall to the top of the beacon.
-- Looks A Toy / B Steel / C Candy like the tools. Parts named "Spin*" turn (brush), "Wheel*" roll,
-- "AshHeap" grows with the bin fill (see CartSpecs.heap), "SeatSpot" is a see-through marker
-- where the rider sits (0, 1.7, 0.3); the main thread decides whether it becomes a real Seat.

local ModelKit = require("./ModelKit")

export type PartSpec = ModelKit.PartSpec
type Wheel = { name: string, x: number, z: number, d: number }
export type CartParts = { look: string, parts: { PartSpec } }

local CartSpecs = {}

CartSpecs.MAX_PARTS = 52
CartSpecs.seatSpot = { 0, 1.7, 0.3 } :: { number }
CartSpecs.binFloorTop = 1.36 -- top face of the bin floor

local box, cyl, ball = ModelKit.box, ModelKit.cyl, ModelKit.ball

local function add(list: { PartSpec }, ...: PartSpec)
	for _, p in { ... } do
		table.insert(list, p)
	end
end

-- Size (a squat round heap: diameter, height, diameter) and middle height of the ash heap in the bin for a fill of 0..1 (an empty bin keeps a tiny
-- heap so the part never has zero size).
function CartSpecs.heap(fill: number): ({ number }, number)
	local f = math.clamp(fill, 0, 1)
	local dia = 0.9 + 0.6 * f
	local h = 0.12 + 0.95 * f
	return { dia, h, dia }, CartSpecs.binFloorTop + h / 2
end

function CartSpecs.build(look: string?): CartParts
	local S = ModelKit.style(look)
	local body = S.main("#FF7A59")
	local deep = ModelKit.darken(body, 0.25)
	local parts: { PartSpec } = {}
	-- chassis and hood
	add(
		parts,
		cyl("Shadow", 5.4, 0.04, { 0, 0.03, 0 }, "#000000", "SmoothPlastic", nil, 0.7),
		box("Chassis", { 2.7, 0.5, 4.6 }, { 0, 0.95, 0 }, body, S.bodyMat),
		box("Hood", { 2.4, 0.5, 1.6 }, { 0, 1.4, -1.5 }, body, S.bodyMat),
		box("HoodStripe", { 0.5, 0.06, 1.6 }, { 0, 1.67, -1.5 }, S.accent("#FFD23F"), S.accentMat),
		box("Skirt", { 2.8, 0.16, 4.7 }, { 0, 0.62, 0 }, S.dark, "Metal"),
		box("SideStripeL", { 0.06, 0.16, 3.6 }, { -1.37, 1.0, 0.2 }, S.trim, S.bodyMat),
		box("SideStripeR", { 0.06, 0.16, 3.6 }, { 1.37, 1.0, 0.2 }, S.trim, S.bodyMat)
	)
	-- wheels: big at the back, small in front
	local wheels: { Wheel } = {
		{ name = "WheelFL", x = -1.5, z = -1.6, d = 1.1 },
		{ name = "WheelFR", x = 1.5, z = -1.6, d = 1.1 },
		{ name = "WheelBL", x = -1.55, z = 1.5, d = 1.5 },
		{ name = "WheelBR", x = 1.55, z = 1.5, d = 1.5 },
	}
	for _, w in wheels do
		local sign = if w.x < 0 then -1 else 1
		add(
			parts,
			cyl(w.name, w.d, 0.5, { w.x, w.d / 2, w.z }, S.dark, "Fabric", { 0, 0, 90 }),
			cyl(
				"Cap" .. string.sub(w.name, 6),
				w.d * 0.5,
				0.1,
				{ w.x + sign * 0.28, w.d / 2, w.z },
				S.accent("#FFD23F"),
				S.accentMat,
				{ 0, 0, 90 }
			)
		)
	end
	-- front brush roller with a dustpan lip
	add(
		parts,
		cyl("RollerBar", 0.6, 2.9, { 0, 0.55, -2.9 }, S.dark, "Fabric", { 0, 0, 90 }),
		box("SpinSpoke1", { 2.9, 0.1, 0.95 }, { 0, 0.55, -2.9 }, S.trim, "Fabric"),
		box("SpinSpoke2", { 2.9, 0.1, 0.95 }, { 0, 0.55, -2.9 }, S.trim, "Fabric", { 60, 0, 0 }),
		box("SpinSpoke3", { 2.9, 0.1, 0.95 }, { 0, 0.55, -2.9 }, S.trim, "Fabric", { 120, 0, 0 }),
		box("RollerArmL", { 0.14, 0.14, 1.0 }, { -1.5, 0.75, -2.45 }, S.dark, "Metal"),
		box("RollerArmR", { 0.14, 0.14, 1.0 }, { 1.5, 0.75, -2.45 }, S.dark, "Metal"),
		box("Dustpan", { 2.6, 0.08, 0.7 }, { 0, 0.45, -2.2 }, deep, S.bodyMat, { 15, 0, 0 })
	)
	-- headlights and beacon
	add(
		parts,
		ball("LightL", 0.45, { -0.85, 1.3, -2.35 }, "#FFF6C8", "Neon"),
		ball("LightR", 0.45, { 0.85, 1.3, -2.35 }, "#FFF6C8", "Neon"),
		cyl("BeaconBase", 0.5, 0.2, { 0, 3.58, 0.95 }, S.dark, "Metal"),
		ball("Beacon", 0.5, { 0, 3.85, 0.95 }, "#FF8A2F", "Neon")
	)
	-- rider seat, steering, roll bar
	add(
		parts,
		box("SeatBase", { 1.3, 0.3, 1.1 }, { 0, 1.35, 0.3 }, S.dark, S.soft),
		box("SeatBack", { 1.3, 1.0, 0.25 }, { 0, 1.9, 0.85 }, S.dark, S.soft, { 8, 0, 0 }),
		cyl("Column", 0.14, 1.0, { 0, 1.85, -0.55 }, S.trim, "Metal", { -35, 0, 0 }),
		cyl("SteerWheel", 0.85, 0.1, { 0, 2.3, -0.8 }, S.dark, S.soft, { 55, 0, 0 }),
		cyl("RollL", 0.16, 2.0, { -0.95, 2.4, 0.95 }, S.trim, "Metal"),
		cyl("RollR", 0.16, 2.0, { 0.95, 2.4, 0.95 }, S.trim, "Metal"),
		box("RollTop", { 2.1, 0.18, 0.18 }, { 0, 3.4, 0.95 }, S.accent("#FFD23F"), S.accentMat),
		box("SeatSpot", { 0.4, 0.4, 0.4 }, CartSpecs.seatSpot, "#FFFFFF", "SmoothPlastic", nil, 1)
	)
	-- the bin on the back: floor + 3 walls, window slot, ash heap
	local heapSize, heapY = CartSpecs.heap(0.5)
	add(
		parts,
		box("BinFloor", { 2.5, 0.16, 1.8 }, { 0, 1.28, 1.9 }, S.dark, "Metal"),
		box("BinWallL", { 0.14, 0.9, 1.8 }, { -1.2, 1.7, 1.9 }, deep, S.bodyMat),
		box("BinWallR", { 0.14, 0.9, 1.8 }, { 1.2, 1.7, 1.9 }, deep, S.bodyMat),
		box("BinWallBack", { 2.5, 0.9, 0.14 }, { 0, 1.7, 2.75 }, deep, S.bodyMat),
		box("BinWallFront", { 2.5, 0.6, 0.14 }, { 0, 1.55, 1.05 }, deep, S.bodyMat),
		box("BinRim", { 2.7, 0.1, 0.1 }, { 0, 2.18, 2.75 }, S.accent("#FFD23F"), S.accentMat),
		cyl("AshHeap", heapSize[1], heapSize[2], { 0, heapY, 1.9 }, "#8A8480", "SmoothPlastic"),
		cyl("Exhaust", 0.22, 0.9, { 0.9, 1.9, 2.95 }, S.trim, "Metal"),
		ball("ExhaustPuff", 0.5, { 0.9, 2.55, 3.0 }, "#C4BCBE", "SmoothPlastic", 0.55)
	)
	return { look = S.id, parts = parts }
end

return CartSpecs
