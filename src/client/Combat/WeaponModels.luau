--!strict
-- Part lists for every held gun: the Volt Pistol (carter's "A++" pick) and the three new guns
-- (Breaker shotgun, Hornet SMG, Longline rifle) at the same realistic level. Pure data, no Roblox
-- types, so Lune can check it. GunModels turns a list into welded parts.
-- Every gun points along +X. Units are scaled by GunModels (SCALE). Each list has a "Slide" and a
-- "Grip" part: the character piece re-welds those two by name.
-- The preview page (plans/previews/guns.html) is made from these lists by tools/gun_preview.py.

local WeaponModels = {}

export type Shape = "box" | "cylX" | "cylY" | "cylZ" | "ball"

export type PartDef = {
	name: string,
	shape: Shape,
	w: number, -- box: width (X), height (Y), depth (Z). cylinders: length, diameter, diameter. ball: diameter.
	h: number,
	d: number,
	look: string,
	x: number, -- offset from the gun centre, or from the centre of its frame
	y: number,
	z: number,
	pitch: number, -- turn about X
	roll: number, -- turn about Z
	frame: string?, -- "grip", "mag" or "stock": placed in that frame's tilted space
}

export type Frame = { x: number, y: number, tilt: number }

export type Model = {
	id: string,
	frames: { [string]: Frame },
	parts: { PartDef },
	hold: { x: number, y: number, z: number }, -- where the gun centre sits from the root part (root space)
}

local function box(
	name: string,
	w: number,
	h: number,
	d: number,
	look: string,
	x: number,
	y: number,
	z: number,
	pitch: number?,
	roll: number?
): PartDef
	return {
		name = name,
		shape = "box",
		w = w,
		h = h,
		d = d,
		look = look,
		x = x,
		y = y,
		z = z,
		pitch = pitch or 0,
		roll = roll or 0,
	}
end

local function cyl(
	name: string,
	length: number,
	diameter: number,
	look: string,
	x: number,
	y: number,
	z: number,
	axis: "X" | "Y" | "Z"
): PartDef
	return {
		name = name,
		shape = if axis == "Y" then "cylY" elseif axis == "Z" then "cylZ" else "cylX",
		w = length,
		h = diameter,
		d = diameter,
		look = look,
		x = x,
		y = y,
		z = z,
		pitch = 0,
		roll = 0,
	}
end

local function ball(
	name: string,
	diameter: number,
	look: string,
	x: number,
	y: number,
	z: number
): PartDef
	return {
		name = name,
		shape = "ball",
		w = diameter,
		h = diameter,
		d = diameter,
		look = look,
		x = x,
		y = y,
		z = z,
		pitch = 0,
		roll = 0,
	}
end

local function on(frame: string, def: PartDef): PartDef
	def.frame = frame
	return def
end

-- @gun volt_pistol
local PISTOL: { PartDef } = {
	box("Slide", 3.3, 0.58, 0.5, "gun", 0.15, 0.42, 0),
	box("BevelR", 3.3, 0.1, 0.12, "gun", 0.15, 0.72, 0.17, 0.8),
	box("BevelL", 3.3, 0.1, 0.12, "gun", 0.15, 0.72, -0.17, -0.8),
	box("FrontBlock", 0.5, 0.42, 0.4, "gun", 1.95, 0.35, 0),
	cyl("Barrel", 0.4, 0.3, "steel", 2.2, 0.38, 0, "X"),
	cyl("Bore", 0.05, 0.17, "dark", 2.41, 0.38, 0, "X"),
	box("Cut1", 0.1, 0.05, 0.2, "dark", 1.25, 0.76, 0),
	box("Cut2", 0.1, 0.05, 0.2, "dark", 1.47, 0.76, 0),
	box("Cut3", 0.1, 0.05, 0.2, "dark", 1.69, 0.76, 0),
	box("SerRearR", 0.7, 0.46, 0.03, "dark", -1.15, 0.42, 0.255),
	box("SerRearL", 0.7, 0.46, 0.03, "dark", -1.15, 0.42, -0.255),
	box("SerFrontR", 0.45, 0.46, 0.03, "dark", 1.15, 0.42, 0.255),
	box("SerFrontL", 0.45, 0.46, 0.03, "dark", 1.15, 0.42, -0.255),
	box("Port", 0.78, 0.22, 0.04, "dark", 0.35, 0.55, 0.255),
	box("Brass", 0.32, 0.1, 0.03, "brass", 0.3, 0.52, 0.262),
	box("Extractor", 0.1, 0.22, 0.04, "steel", 0.85, 0.64, 0.262),
	box("Striker", 0.18, 0.3, 0.3, "gun", -1.68, 0.5, 0, 0, 0.35),
	box("RearSightBase", 0.28, 0.06, 0.4, "gun", -1.45, 0.76, 0),
	box("RearSightR", 0.12, 0.17, 0.1, "gun", -1.45, 0.86, 0.12),
	box("RearSightL", 0.12, 0.17, 0.1, "gun", -1.45, 0.86, -0.12),
	box("FrontSight", 0.1, 0.2, 0.08, "gun", 1.68, 0.84, 0),
	box("FrontDot", 0.05, 0.05, 0.1, "cyan", 1.68, 0.92, 0),
	box("Frame", 2.6, 0.28, 0.44, "poly", -0.05, 0, 0),
	box("FrameBevelR", 2.6, 0.07, 0.07, "poly", -0.05, 0.13, 0.2, 0.7),
	box("FrameBevelL", 2.6, 0.07, 0.07, "poly", -0.05, 0.13, -0.2, -0.7),
	box("Beavertail", 0.5, 0.1, 0.44, "poly", -1.4, 0.14, 0, 0, -0.15),
	box("RailBlock", 0.9, 0.22, 0.46, "poly", 1.4, -0.02, 0),
	box("Slot1", 0.07, 0.2, 0.48, "dark", 1.1, -0.02, 0),
	box("Slot2", 0.07, 0.2, 0.48, "dark", 1.35, -0.02, 0),
	box("Slot3", 0.07, 0.2, 0.48, "dark", 1.6, -0.02, 0),
	box("Light", 0.62, 0.24, 0.34, "gun", 1.56, -0.28, 0),
	box("LightLens", 0.05, 0.13, 0.13, "cyan", 1.88, -0.28, 0),
	box("LightDot", 0.04, 0.04, 0.04, "coral", 1.88, -0.17, 0),
	cyl("TakedownPin", 0.5, 0.14, "steel", 0.75, -0.05, 0, "Z"),
	box("SlideStop", 0.55, 0.08, 0.06, "steel", -0.2, 0.17, 0.255),
	cyl("SpringGuide", 0.55, 0.13, "steel", 2.1, 0.12, 0, "X"),
	box("CellBar1", 0.1, 0.04, 0.02, "cyan", -0.3, 0.04, -0.222),
	box("CellBar2", 0.1, 0.04, 0.02, "cyan", -0.14, 0.04, -0.222),
	box("CellBar3", 0.1, 0.04, 0.02, "cyan", 0.02, 0.04, -0.222),
	box("GuardBottom", 0.95, 0.07, 0.34, "poly", 0.05, -0.58, 0),
	box("GuardFront", 0.07, 0.42, 0.34, "poly", 0.5, -0.36, 0),
	box("Trigger", 0.07, 0.32, 0.1, "steel", -0.02, -0.38, 0, 0, 0.25),
	on("grip", box("Grip", 0.72, 1.5, 0.46, "poly", 0, 0, 0)),
	on("grip", box("Backstrap", 0.14, 1.3, 0.4, "poly", -0.42, -0.05, 0)),
	on("grip", cyl("Groove1", 0.5, 0.18, "dark", 0.37, 0.3, 0, "Z")),
	on("grip", cyl("Groove2", 0.5, 0.18, "dark", 0.37, 0, 0, "Z")),
	on("grip", cyl("Groove3", 0.5, 0.18, "dark", 0.37, -0.3, 0, "Z")),
	on("grip", box("TextureR", 0.5, 1.0, 0.04, "dark", -0.02, -0.05, 0.235)),
	on("grip", box("TextureL", 0.5, 1.0, 0.04, "dark", -0.02, -0.05, -0.235)),
	on("grip", box("Magwell", 0.86, 0.1, 0.54, "poly", 0, -0.76, 0)),
	on("grip", box("Lanyard", 0.1, 0.22, 0.08, "steel", -0.4, -0.78, 0)),
	on("grip", box("Magazine", 0.52, 0.95, 0.38, "blued", 0.03, -0.55, 0)),
	on("grip", box("Rounds", 0.22, 0.5, 0.4, "brass", 0.03, -0.55, 0)),
	on("grip", box("Floorplate", 0.6, 0.1, 0.46, "poly", 0.03, -1.05, 0)),
	on("grip", box("FloorLine", 0.4, 0.03, 0.48, "cyan", 0.03, -1.1, 0)),
}
-- @end

-- Pump shotgun. Long steel barrel over a tube magazine, ribbed pump, side shell carrier, solid stock.
-- @gun breaker
local BREAKER: { PartDef } = {
	box("Slide", 2.6, 0.75, 0.55, "gun", 0, 0.35, 0),
	box("BevelR", 2.6, 0.1, 0.14, "gun", 0, 0.7, 0.2, 0.8),
	box("BevelL", 2.6, 0.1, 0.14, "gun", 0, 0.7, -0.2, -0.8),
	box("Port", 0.9, 0.3, 0.04, "dark", 0.25, 0.42, 0.28),
	box("ShellInPort", 0.5, 0.17, 0.03, "hull", 0.3, 0.42, 0.29),
	box("ShellHead", 0.12, 0.19, 0.035, "brass", 0.02, 0.42, 0.29),
	box("Rail", 2.2, 0.08, 0.3, "poly", 0, 0.76, 0),
	box("RailSlot1", 0.07, 0.09, 0.32, "dark", -0.7, 0.76, 0),
	box("RailSlot2", 0.07, 0.09, 0.32, "dark", -0.25, 0.76, 0),
	box("RailSlot3", 0.07, 0.09, 0.32, "dark", 0.2, 0.76, 0),
	box("RailSlot4", 0.07, 0.09, 0.32, "dark", 0.65, 0.76, 0),
	box("RearSightR", 0.14, 0.22, 0.08, "gun", -0.95, 0.9, 0.12),
	box("RearSightL", 0.14, 0.22, 0.08, "gun", -0.95, 0.9, -0.12),
	box("RearSightTop", 0.14, 0.06, 0.32, "gun", -0.95, 1.02, 0),
	cyl("Barrel", 4.6, 0.36, "steel", 3.6, 0.42, 0, "X"),
	box("HeatShield", 3.2, 0.1, 0.44, "gun", 3.1, 0.64, 0),
	box("Vent1", 0.3, 0.03, 0.22, "dark", 2.0, 0.7, 0),
	box("Vent2", 0.3, 0.03, 0.22, "dark", 2.55, 0.7, 0),
	box("Vent3", 0.3, 0.03, 0.22, "dark", 3.1, 0.7, 0),
	box("Vent4", 0.3, 0.03, 0.22, "dark", 3.65, 0.7, 0),
	box("Vent5", 0.3, 0.03, 0.22, "dark", 4.2, 0.7, 0),
	cyl("Choke", 0.32, 0.44, "gun", 5.95, 0.42, 0, "X"),
	cyl("Bore", 0.05, 0.26, "dark", 6.12, 0.42, 0, "X"),
	ball("Bead", 0.12, "cyan", 5.75, 0.64, 0),
	cyl("MagTube", 3.9, 0.34, "gun", 3.25, 0.02, 0, "X"),
	cyl("MagCap", 0.26, 0.4, "steel", 5.3, 0.02, 0, "X"),
	box("Clamp", 0.22, 0.72, 0.44, "poly", 4.9, 0.22, 0),
	cyl("ClampScrew", 0.5, 0.1, "steel", 4.9, 0.22, 0, "Z"),
	box("Pump", 1.9, 0.5, 0.56, "poly", 2.6, 0.02, 0),
	box("PumpRib1", 0.07, 0.44, 0.58, "dark", 1.95, 0.02, 0),
	box("PumpRib2", 0.07, 0.44, 0.58, "dark", 2.2, 0.02, 0),
	box("PumpRib3", 0.07, 0.44, 0.58, "dark", 2.45, 0.02, 0),
	box("PumpRib4", 0.07, 0.44, 0.58, "dark", 2.7, 0.02, 0),
	box("PumpRib5", 0.07, 0.44, 0.58, "dark", 2.95, 0.02, 0),
	box("PumpRib6", 0.07, 0.44, 0.58, "dark", 3.2, 0.02, 0),
	box("PumpLine", 1.4, 0.03, 0.58, "cyan", 2.6, -0.24, 0),
	box("Frame", 1.6, 0.3, 0.5, "poly", -0.2, -0.12, 0),
	cyl("Safety", 0.56, 0.12, "steel", -0.75, -0.05, 0, "Z"),
	cyl("Pin1", 0.56, 0.1, "steel", 0.35, 0.05, 0, "Z"),
	cyl("Pin2", 0.56, 0.1, "steel", -0.45, 0.18, 0, "Z"),
	box("GuardBottom", 0.95, 0.07, 0.34, "poly", -0.15, -0.62, 0),
	box("GuardFront", 0.07, 0.4, 0.34, "poly", 0.3, -0.42, 0),
	box("Trigger", 0.07, 0.32, 0.1, "steel", -0.2, -0.42, 0, 0, 0.25),
	box("Saddle", 1.4, 0.5, 0.06, "poly", -0.1, 0.38, -0.31),
	cyl("Shell1", 0.42, 0.17, "hull", -0.6, 0.42, -0.42, "Y"),
	cyl("Shell2", 0.42, 0.17, "hull", -0.27, 0.42, -0.42, "Y"),
	cyl("Shell3", 0.42, 0.17, "hull", 0.06, 0.42, -0.42, "Y"),
	cyl("Shell4", 0.42, 0.17, "hull", 0.39, 0.42, -0.42, "Y"),
	cyl("Head1", 0.1, 0.18, "brass", -0.6, 0.17, -0.42, "Y"),
	cyl("Head2", 0.1, 0.18, "brass", -0.27, 0.17, -0.42, "Y"),
	cyl("Head3", 0.1, 0.18, "brass", 0.06, 0.17, -0.42, "Y"),
	cyl("Head4", 0.1, 0.18, "brass", 0.39, 0.17, -0.42, "Y"),
	box("CellBar1", 0.1, 0.04, 0.02, "cyan", 0.55, 0.12, 0.28),
	box("CellBar2", 0.1, 0.04, 0.02, "cyan", 0.71, 0.12, 0.28),
	box("CellBar3", 0.1, 0.04, 0.02, "cyan", 0.87, 0.12, 0.28),
	on("grip", box("Grip", 0.62, 1.35, 0.48, "poly", 0, 0, 0)),
	on("grip", box("TextureR", 0.44, 0.9, 0.04, "dark", 0, -0.05, 0.245)),
	on("grip", box("TextureL", 0.44, 0.9, 0.04, "dark", 0, -0.05, -0.245)),
	on("grip", box("GripCap", 0.72, 0.1, 0.52, "poly", 0, -0.7, 0)),
	on("stock", box("StockTop", 2.6, 0.42, 0.48, "poly", 0, 0.15, 0)),
	on("stock", box("StockLower", 2.5, 0.38, 0.46, "poly", -0.2, -0.4, 0, 0, 0.18)),
	on("stock", box("StockWeb", 1.3, 0.5, 0.46, "poly", -0.75, -0.1, 0)),
	on("stock", box("StockCut", 0.9, 0.22, 0.5, "dark", 0.3, -0.13, 0)),
	on("stock", box("Pad", 0.3, 1.25, 0.56, "rubber", -1.42, -0.15, 0)),
	on("stock", box("PadLine", 0.32, 0.03, 0.58, "cyan", -1.42, 0.25, 0)),
	on("stock", box("SlingLoop", 0.1, 0.24, 0.08, "steel", -0.9, -0.72, 0)),
}
-- @end

-- Compact SMG. Rail on top with a red-dot sight, long magazine, vertical foregrip, folding wire stock.
-- @gun hornet
local HORNET: { PartDef } = {
	box("Slide", 3.0, 0.6, 0.5, "gun", 0.3, 0.42, 0),
	box("BevelR", 3.0, 0.1, 0.12, "gun", 0.3, 0.72, 0.17, 0.8),
	box("BevelL", 3.0, 0.1, 0.12, "gun", 0.3, 0.72, -0.17, -0.8),
	box("Frame", 2.4, 0.32, 0.46, "poly", 0.1, -0.02, 0),
	box("Port", 0.8, 0.24, 0.04, "dark", 0.6, 0.48, 0.255),
	box("Brass", 0.3, 0.1, 0.03, "brass", 0.55, 0.47, 0.262),
	box("Charger", 0.28, 0.12, 0.5, "steel", -0.95, 0.55, -0.2),
	box("ChargerKnob", 0.2, 0.16, 0.12, "gun", -0.95, 0.55, -0.5),
	box("Handguard", 1.8, 0.58, 0.54, "poly", 2.7, 0.36, 0),
	box("HgVent1", 0.3, 0.12, 0.56, "dark", 2.15, 0.4, 0),
	box("HgVent2", 0.3, 0.12, 0.56, "dark", 2.7, 0.4, 0),
	box("HgVent3", 0.3, 0.12, 0.56, "dark", 3.25, 0.4, 0),
	box("Rail", 4.2, 0.1, 0.3, "poly", 1.2, 0.78, 0),
	box("RailSlot1", 0.07, 0.11, 0.32, "dark", 1.6, 0.78, 0),
	box("RailSlot2", 0.07, 0.11, 0.32, "dark", 2.0, 0.78, 0),
	box("RailSlot3", 0.07, 0.11, 0.32, "dark", 2.4, 0.78, 0),
	box("RailSlot4", 0.07, 0.11, 0.32, "dark", 2.8, 0.78, 0),
	box("RailSlot5", 0.07, 0.11, 0.32, "dark", 3.2, 0.78, 0),
	cyl("Barrel", 0.6, 0.26, "steel", 3.85, 0.4, 0, "X"),
	cyl("Comp", 0.7, 0.36, "gun", 4.4, 0.4, 0, "X"),
	box("CompCut1", 0.08, 0.04, 0.2, "dark", 4.22, 0.58, 0),
	box("CompCut2", 0.08, 0.04, 0.2, "dark", 4.4, 0.58, 0),
	box("CompCut3", 0.08, 0.04, 0.2, "dark", 4.58, 0.58, 0),
	cyl("Bore", 0.05, 0.18, "dark", 4.76, 0.4, 0, "X"),
	box("DotBase", 0.8, 0.12, 0.36, "gun", -0.1, 0.89, 0),
	box("DotBody", 0.8, 0.5, 0.44, "gun", -0.1, 1.18, 0),
	box("DotHoodL", 0.8, 0.1, 0.06, "gun", -0.1, 1.38, -0.19),
	box("DotHoodR", 0.8, 0.1, 0.06, "gun", -0.1, 1.38, 0.19),
	box("DotLensF", 0.04, 0.32, 0.34, "glass", 0.31, 1.2, 0),
	box("DotLensB", 0.04, 0.32, 0.34, "glass", -0.51, 1.2, 0),
	box("DotReticle", 0.03, 0.05, 0.05, "coral", 0.25, 1.2, 0),
	cyl("DotKnob", 0.12, 0.2, "steel", -0.1, 1.18, 0.26, "Z"),
	box("Selector", 0.18, 0.1, 0.04, "steel", -0.55, 0.1, 0.24, 0, 0.5),
	box("CellBar1", 0.1, 0.04, 0.02, "cyan", 0.0, 0.0, -0.235),
	box("CellBar2", 0.1, 0.04, 0.02, "cyan", 0.16, 0.0, -0.235),
	box("CellBar3", 0.1, 0.04, 0.02, "cyan", 0.32, 0.0, -0.235),
	box("Foregrip", 0.42, 0.95, 0.42, "poly", 2.7, -0.4, 0),
	box("ForegripRing1", 0.44, 0.06, 0.44, "dark", 2.7, -0.3, 0),
	box("ForegripRing2", 0.44, 0.06, 0.44, "dark", 2.7, -0.55, 0),
	box("ForegripCap", 0.5, 0.1, 0.5, "poly", 2.7, -0.88, 0),
	box("GuardBottom", 0.9, 0.07, 0.34, "poly", -0.1, -0.56, 0),
	box("GuardFront", 0.07, 0.4, 0.34, "poly", 0.33, -0.36, 0),
	box("Trigger", 0.07, 0.3, 0.1, "steel", -0.18, -0.36, 0, 0, 0.25),
	on("mag", box("Magwell", 0.62, 0.5, 0.52, "poly", 0, 0.3, 0)),
	on("mag", box("Magazine", 0.44, 1.7, 0.36, "blued", 0, -0.55, 0)),
	on("mag", box("MagRibR", 0.3, 1.3, 0.03, "dark", 0, -0.55, 0.19)),
	on("mag", box("MagRibL", 0.3, 1.3, 0.03, "dark", 0, -0.55, -0.19)),
	on("mag", box("Floorplate", 0.54, 0.1, 0.44, "poly", 0, -1.45, 0)),
	on("mag", box("FloorLine", 0.38, 0.03, 0.46, "cyan", 0, -1.5, 0)),
	on("grip", box("Grip", 0.62, 1.3, 0.46, "poly", 0, 0, 0)),
	on("grip", box("TextureR", 0.44, 0.9, 0.04, "dark", 0, -0.05, 0.235)),
	on("grip", box("TextureL", 0.44, 0.9, 0.04, "dark", 0, -0.05, -0.235)),
	on("grip", box("GripCap", 0.7, 0.1, 0.5, "poly", 0, -0.68, 0)),
	on("stock", box("Hinge", 0.4, 0.55, 0.52, "poly", 1.2, 0, 0)),
	on("stock", cyl("RodTopR", 2.4, 0.12, "steel", 0, 0.15, 0.18, "X")),
	on("stock", cyl("RodTopL", 2.4, 0.12, "steel", 0, 0.15, -0.18, "X")),
	on("stock", box("RodLowR", 2.3, 0.1, 0.1, "steel", 0, -0.32, 0.18, 0, 0.18)),
	on("stock", box("RodLowL", 2.3, 0.1, 0.1, "steel", 0, -0.32, -0.18, 0, 0.18)),
	on("stock", box("Butt", 0.2, 1.1, 0.52, "rubber", -1.25, -0.15, 0)),
	on("stock", box("ButtLine", 0.22, 0.03, 0.54, "cyan", -1.25, 0.3, 0)),
}
-- @end

-- Marksman rifle. Long tan handguard with slots, fluted barrel, muzzle brake, scope, folded bipod.
-- @gun longline
local LONGLINE: { PartDef } = {
	box("Slide", 3.0, 0.62, 0.52, "gun", 0, 0.42, 0),
	box("BevelR", 3.0, 0.1, 0.13, "gun", 0, 0.73, 0.18, 0.8),
	box("BevelL", 3.0, 0.1, 0.13, "gun", 0, 0.73, -0.18, -0.8),
	box("Frame", 2.4, 0.34, 0.48, "poly", 0, 0, 0),
	box("Port", 0.8, 0.24, 0.04, "dark", 0.3, 0.5, 0.265),
	box("Brass", 0.42, 0.1, 0.03, "brass", 0.3, 0.5, 0.272),
	cyl("BoltArm", 0.5, 0.1, "steel", -0.6, 0.5, 0.45, "Z"),
	ball("BoltKnob", 0.22, "gun", -0.6, 0.5, 0.72),
	box("Handguard", 4.4, 0.6, 0.56, "tan", 3.7, 0.38, 0),
	box("HgBevelR", 4.4, 0.1, 0.12, "tan", 3.7, 0.66, 0.2, 0.8),
	box("HgBevelL", 4.4, 0.1, 0.12, "tan", 3.7, 0.66, -0.2, -0.8),
	box("Mlok1", 0.4, 0.14, 0.58, "dark", 2.2, 0.32, 0),
	box("Mlok2", 0.4, 0.14, 0.58, "dark", 2.8, 0.32, 0),
	box("Mlok3", 0.4, 0.14, 0.58, "dark", 3.4, 0.32, 0),
	box("Mlok4", 0.4, 0.14, 0.58, "dark", 4.0, 0.32, 0),
	box("Mlok5", 0.4, 0.14, 0.58, "dark", 4.6, 0.32, 0),
	box("Mlok6", 0.4, 0.14, 0.58, "dark", 5.2, 0.32, 0),
	box("HgLine", 1.2, 0.03, 0.58, "cyan", 5.1, 0.12, 0),
	box("Rail", 6.4, 0.08, 0.32, "poly", 2.4, 0.78, 0),
	box("RailSlot1", 0.07, 0.09, 0.34, "dark", 2.6, 0.78, 0),
	box("RailSlot2", 0.07, 0.09, 0.34, "dark", 3.1, 0.78, 0),
	box("RailSlot3", 0.07, 0.09, 0.34, "dark", 3.6, 0.78, 0),
	box("RailSlot4", 0.07, 0.09, 0.34, "dark", 4.1, 0.78, 0),
	box("RailSlot5", 0.07, 0.09, 0.34, "dark", 4.6, 0.78, 0),
	box("RailSlot6", 0.07, 0.09, 0.34, "dark", 5.1, 0.78, 0),
	cyl("Barrel", 2.6, 0.3, "steel", 7.2, 0.42, 0, "X"),
	box("Flute1", 2.2, 0.03, 0.06, "dark", 7.1, 0.57, 0),
	box("Flute2", 2.2, 0.06, 0.03, "dark", 7.1, 0.42, 0.15),
	box("Flute3", 2.2, 0.06, 0.03, "dark", 7.1, 0.42, -0.15),
	box("Brake", 0.7, 0.42, 0.44, "gun", 8.8, 0.42, 0),
	box("BrakePort1", 0.1, 0.22, 0.46, "dark", 8.62, 0.42, 0),
	box("BrakePort2", 0.1, 0.22, 0.46, "dark", 8.8, 0.42, 0),
	box("BrakePort3", 0.1, 0.22, 0.46, "dark", 8.98, 0.42, 0),
	cyl("Bore", 0.05, 0.18, "dark", 9.16, 0.42, 0, "X"),
	box("RingRear", 0.3, 0.5, 0.5, "gun", -0.3, 1.02, 0),
	box("RingFront", 0.3, 0.5, 0.5, "gun", 1.3, 1.02, 0),
	cyl("ScopeTube", 3.2, 0.42, "poly", 0.5, 1.32, 0, "X"),
	cyl("ScopeTaper", 0.4, 0.58, "poly", 2.25, 1.32, 0, "X"),
	cyl("ScopeBell", 0.9, 0.72, "poly", 2.85, 1.32, 0, "X"),
	cyl("ScopeRing", 0.06, 0.74, "cyan", 2.5, 1.32, 0, "X"),
	cyl("ScopeLensF", 0.03, 0.62, "glass", 3.31, 1.32, 0, "X"),
	cyl("Ocular", 0.8, 0.6, "poly", -1.45, 1.32, 0, "X"),
	cyl("ScopeLensB", 0.03, 0.5, "glass", -1.86, 1.32, 0, "X"),
	cyl("TurretTop", 0.34, 0.36, "gun", 0.5, 1.62, 0, "Y"),
	cyl("TurretCap", 0.04, 0.38, "cyan", 0.5, 1.8, 0, "Y"),
	cyl("TurretSide", 0.3, 0.32, "gun", 0.5, 1.32, 0.34, "Z"),
	box("BipodMount", 0.4, 0.2, 0.4, "gun", 5.6, 0.02, 0),
	box("BipodLegR", 2.0, 0.1, 0.1, "steel", 4.6, 0.0, 0.14),
	box("BipodLegL", 2.0, 0.1, 0.1, "steel", 4.6, 0.0, -0.14),
	box("BipodFootR", 0.12, 0.16, 0.16, "rubber", 3.6, 0.0, 0.14),
	box("BipodFootL", 0.12, 0.16, 0.16, "rubber", 3.6, 0.0, -0.14),
	box("CellBar1", 0.1, 0.04, 0.02, "cyan", -0.4, 0.0, -0.245),
	box("CellBar2", 0.1, 0.04, 0.02, "cyan", -0.24, 0.0, -0.245),
	box("CellBar3", 0.1, 0.04, 0.02, "cyan", -0.08, 0.0, -0.245),
	box("GuardBottom", 0.95, 0.07, 0.34, "poly", -0.2, -0.6, 0),
	box("GuardFront", 0.07, 0.4, 0.34, "poly", 0.25, -0.4, 0),
	box("Trigger", 0.07, 0.32, 0.1, "steel", -0.25, -0.4, 0, 0, 0.25),
	on("mag", box("Magazine", 0.62, 0.7, 0.42, "blued", 0, 0, 0)),
	on("mag", box("MagRib", 0.4, 0.5, 0.44, "dark", 0, 0, 0)),
	on("mag", box("Floorplate", 0.7, 0.1, 0.48, "poly", 0, -0.38, 0)),
	on("mag", box("FloorLine", 0.5, 0.03, 0.5, "cyan", 0, -0.44, 0)),
	on("grip", box("Grip", 0.62, 1.3, 0.48, "poly", 0, 0, 0)),
	on("grip", box("TextureR", 0.44, 0.9, 0.04, "dark", 0, -0.05, 0.245)),
	on("grip", box("TextureL", 0.44, 0.9, 0.04, "dark", 0, -0.05, -0.245)),
	on("grip", box("GripCap", 0.7, 0.1, 0.52, "poly", 0, -0.68, 0)),
	on("stock", cyl("Buffer", 1.0, 0.36, "poly", 1.0, -0.05, 0, "X")),
	on("stock", box("StockBody", 2.4, 0.55, 0.5, "tan", -0.2, 0.05, 0)),
	on("stock", box("Cheek", 1.4, 0.25, 0.46, "poly", -0.3, 0.44, 0)),
	on("stock", box("CheekLine", 1.0, 0.03, 0.48, "cyan", -0.3, 0.57, 0)),
	on("stock", box("StockSpine", 2.0, 0.3, 0.42, "tan", -0.4, -0.5, 0)),
	on("stock", box("StockPost", 0.3, 0.5, 0.42, "tan", 0.45, -0.3, 0)),
	on("stock", box("Pad", 0.25, 1.25, 0.55, "rubber", -1.42, -0.2, 0)),
	on("stock", cyl("Monopod", 0.35, 0.16, "steel", -0.9, -0.8, 0, "Y")),
}
-- @end

WeaponModels.models = {
	volt_pistol = {
		id = "volt_pistol",
		frames = { grip = { x = -1.05, y = -0.78, tilt = -0.2 } },
		parts = PISTOL,
		hold = { x = 1.3, y = -0.1, z = -1.0 },
	} :: Model,
	breaker = {
		id = "breaker",
		frames = {
			grip = { x = -1.0, y = -0.75, tilt = -0.3 },
			stock = { x = -2.6, y = 0.1, tilt = 0 },
		},
		parts = BREAKER,
		hold = { x = 1.3, y = -0.1, z = -1.6 },
	} :: Model,
	hornet = {
		id = "hornet",
		frames = {
			grip = { x = -0.85, y = -0.72, tilt = -0.25 },
			mag = { x = 0.95, y = -0.4, tilt = 0.05 },
			stock = { x = -2.35, y = 0.2, tilt = 0 },
		},
		parts = HORNET,
		hold = { x = 1.3, y = -0.1, z = -1.3 },
	} :: Model,
	longline = {
		id = "longline",
		frames = {
			grip = { x = -0.95, y = -0.72, tilt = -0.3 },
			mag = { x = 0.75, y = -0.45, tilt = 0 },
			stock = { x = -2.75, y = 0.15, tilt = 0 },
		},
		parts = LONGLINE,
		hold = { x = 1.3, y = -0.1, z = -2.0 },
	} :: Model,
}

-- The model for a weapon id; unknown ids fall back to the pistol so a fighter is never empty-handed.
function WeaponModels.get(id: string): Model
	return WeaponModels.models[id] or WeaponModels.models.volt_pistol
end

return WeaponModels
