--!strict
-- The world ring for the safe zone, look "A Neon Wall": a red glowing wall with a bright line on
-- the floor, plus a blue ring that shows where the circle is going. Drawn only on this client.
-- None of it can be touched or hit: CanCollide, CanQuery and CanTouch are all off, so it never
-- changes gameplay (the server decides who is inside).

local Boundary = {}
Boundary.__index = Boundary

local SEGMENTS = 48
local WALL_HEIGHT = 12
local WALL_THICKNESS = 0.6
local LINE_WIDTH = 2
local LINE_HEIGHT = 0.3
local TARGET_WIDTH = 1.2
local OVERLAP = 1.05 -- segments overlap a little so no gaps show
local MIN_CHANGE = 0.02 -- studs: smaller radius changes are not worth redrawing

local CORAL = Color3.fromRGB(241, 91, 100)
local CORAL_LIGHT = Color3.fromRGB(255, 208, 211)
local CYAN = Color3.fromRGB(54, 217, 232)

type Ring = {
	folder: Folder,
	parts: { Part },
	cframes: { CFrame },
	height: number, -- of the part, in studs
	width: number, -- radial thickness
	lift: number, -- centre height above the floor
}

local function newPart(name: string, color: Color3, transparency: number, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	part.Size = Vector3.new(1, 1, 1)
	part.Parent = parent
	return part
end

local function newRing(
	parent: Instance,
	name: string,
	color: Color3,
	transparency: number,
	height: number,
	width: number
): Ring
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	local parts: { Part } = {}
	for i = 1, SEGMENTS do
		parts[i] = newPart(name .. i, color, transparency, folder)
	end
	return {
		folder = folder,
		parts = parts,
		cframes = table.create(SEGMENTS, CFrame.new()),
		height = height,
		width = width,
		lift = height / 2,
	}
end

local function placeRing(ring: Ring, cx: number, cy: number, cz: number, radius: number)
	local step = (2 * math.pi) / SEGMENTS
	local chord = 2 * radius * math.tan(step / 2) * OVERLAP
	local size = Vector3.new(math.max(chord, 0.1), ring.height, ring.width)
	for i = 1, SEGMENTS do
		local a = (i - 1) * step
		local pos =
			Vector3.new(cx + math.cos(a) * radius, cy + ring.lift, cz + math.sin(a) * radius)
		-- local X runs along the circle (tangent), so each part lies flat against it
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		ring.cframes[i] = CFrame.fromMatrix(pos, tangent, Vector3.yAxis)
		ring.parts[i].Size = size
	end
	workspace:BulkMoveTo(ring.parts, ring.cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

export type Boundary = typeof(setmetatable(
	{} :: {
		container: Folder,
		wall: Ring,
		line: Ring,
		target: Ring,
		shown: boolean,
		lastX: number,
		lastZ: number,
		lastRadius: number,
		lastTarget: number,
		targetShown: boolean,
		targetDim: boolean,
	},
	Boundary
))

function Boundary.new(): Boundary
	local container = Instance.new("Folder")
	container.Name = "ZoneRing" -- local only: this client made it, the server never sees it
	local self = setmetatable({
		container = container,
		wall = newRing(container, "Wall", CORAL, 0.7, WALL_HEIGHT, WALL_THICKNESS),
		line = newRing(container, "Line", CORAL_LIGHT, 0.1, LINE_HEIGHT, LINE_WIDTH),
		target = newRing(container, "Next", CYAN, 0.15, LINE_HEIGHT, TARGET_WIDTH),
		shown = false,
		lastX = math.huge,
		lastZ = math.huge,
		lastRadius = math.huge,
		lastTarget = math.huge,
		targetShown = true,
		targetDim = false,
	}, Boundary)
	return self
end

-- groundY: height of the floor. targetRadius: where the circle is going (nil/equal = no next ring).
-- blink: true during a warning, so the next ring flashes.
function Boundary.update(
	self: Boundary,
	cx: number,
	cz: number,
	groundY: number,
	radius: number,
	targetRadius: number,
	blink: boolean,
	now: number
)
	if not self.shown then
		self.shown = true
		self.container.Parent = workspace
		self.lastRadius = math.huge
		self.lastTarget = math.huge
	end

	local moved = math.abs(radius - self.lastRadius) > MIN_CHANGE
		or cx ~= self.lastX
		or cz ~= self.lastZ
	if moved then
		self.lastRadius, self.lastX, self.lastZ = radius, cx, cz
		-- the wall and floor line sit on the line itself
		placeRing(self.wall, cx, groundY, cz, radius)
		placeRing(self.line, cx, groundY + 0.1, cz, radius)
	end

	local showTarget = targetRadius < radius - MIN_CHANGE or (blink and targetRadius < radius)
	local targetMoved = math.abs(targetRadius - self.lastTarget) > MIN_CHANGE
	if showTarget and (targetMoved or moved) then
		self.lastTarget = targetRadius
		placeRing(self.target, cx, groundY + 0.15, cz, targetRadius)
	end
	if showTarget ~= self.targetShown then
		self.targetShown = showTarget
		self.target.folder.Parent = if showTarget then self.container else nil
	end
	if showTarget then
		-- flash 3 times a second during a warning; steady while closing
		local dim = blink and (math.floor(now * 3) % 2 == 0)
		if dim ~= self.targetDim then
			self.targetDim = dim
			for _, part in self.target.parts do
				part.Transparency = if dim then 0.75 else 0.15
			end
		end
	end
end

function Boundary.hide(self: Boundary)
	if self.shown then
		self.shown = false
		self.container.Parent = nil
	end
end

function Boundary.destroy(self: Boundary)
	self.container:Destroy()
end

return Boundary
