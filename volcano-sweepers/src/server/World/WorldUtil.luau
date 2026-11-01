--!strict
-- Tiny Part factory shared by every World module. Every part is Anchored, Massless and does not
-- cast shadows unless asked. Only solid things collide (and only those answer spatial queries,
-- so the character controller can still find the floor). Parent is always set LAST.

local CollectionService = game:GetService("CollectionService")

local WorldUtil = {}

-- One palette so the whole island reads as one toy world.
WorldUtil.Palette = {
	cream = "#FFF1CC",
	wood = "#C98A4B",
	woodLight = "#F6C27A",
	woodDark = "#8A5A3C",
	coral = "#FF7A59",
	red = "#FF4D4D",
	teal = "#2EB6C9",
	sun = "#FFD23F",
	gold = "#FFD84D",
	orange = "#FF6A1F",
	lava = "#FF7A2F",
	ember = "#FFC24D",
	navy = "#21304A",
	white = "#FFFFFF",
	bone = "#F3E9D2",
	stone = "#E9E2D0",
	dark = "#2B2230",
	smoke = "#6E6068",
	cyan = "#7DF0FF",
	pink = "#FF9AD5",
} :: { [string]: string }

-- Glow colour of each zone's boundary rope and gate (index = zone id of the zone you enter).
WorldUtil.zoneAccent = {
	[1] = "#FFE9A8",
	[2] = "#9BFF8A",
	[3] = "#7FF3FF",
	[4] = "#FF8A6B",
	[5] = "#FFB347",
} :: { [number]: string }

WorldUtil.SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

export type Extra = {
	material: Enum.Material?,
	transparency: number?,
	reflectance: number?,
	collide: boolean?,
	shadow: boolean?,
}

export type Props = {
	name: string?,
	size: Vector3,
	cf: CFrame,
	color: string | Color3,
	material: Enum.Material?,
	shape: Enum.PartType?,
	transparency: number?,
	reflectance: number?,
	collide: boolean?,
	shadow: boolean?,
	wedge: boolean?,
}

function WorldUtil.color(c: string | Color3): Color3
	if typeof(c) == "string" then
		return Color3.fromHex(c)
	end
	return c
end

function WorldUtil.part(parent: Instance, p: Props): BasePart
	local inst: BasePart
	if p.wedge == true then
		inst = Instance.new("WedgePart")
	else
		local plain = Instance.new("Part")
		plain.Shape = p.shape or Enum.PartType.Block
		inst = plain
	end
	inst.Anchored = true
	inst.CanCollide = p.collide == true
	inst.CanQuery = p.collide == true
	inst.CanTouch = false
	inst.Massless = true
	inst.CastShadow = p.shadow == true
	inst.Material = p.material or Enum.Material.SmoothPlastic
	inst.Color = WorldUtil.color(p.color)
	inst.Transparency = p.transparency or 0
	inst.Reflectance = p.reflectance or 0
	inst.TopSurface = Enum.SurfaceType.Smooth
	inst.BottomSurface = Enum.SurfaceType.Smooth
	inst.Size = p.size
	inst.CFrame = p.cf
	inst.Name = p.name or "Part"
	inst.Parent = parent
	return inst
end

local function withExtra(base: Props, extra: Extra?): Props
	if extra then
		base.material = extra.material
		base.transparency = extra.transparency
		base.reflectance = extra.reflectance
		base.collide = extra.collide
		base.shadow = extra.shadow
	end
	return base
end

function WorldUtil.block(
	parent: Instance,
	name: string,
	cf: CFrame,
	size: Vector3,
	color: string | Color3,
	extra: Extra?
): BasePart
	return WorldUtil.part(
		parent,
		withExtra({ name = name, size = size, cf = cf, color = color }, extra)
	)
end

function WorldUtil.wedge(
	parent: Instance,
	name: string,
	cf: CFrame,
	size: Vector3,
	color: string | Color3,
	extra: Extra?
): BasePart
	return WorldUtil.part(
		parent,
		withExtra({ name = name, size = size, cf = cf, color = color, wedge = true }, extra)
	)
end

-- Sphere centred at `centre`.
function WorldUtil.ball(
	parent: Instance,
	name: string,
	centre: Vector3,
	diameter: number,
	color: string | Color3,
	extra: Extra?
): BasePart
	return WorldUtil.part(
		parent,
		withExtra({
			name = name,
			size = Vector3.new(diameter, diameter, diameter),
			cf = CFrame.new(centre),
			color = color,
			shape = Enum.PartType.Ball,
		}, extra)
	)
end

-- Upright cylinder (axis = world Y) centred at `centre`.
function WorldUtil.cylinder(
	parent: Instance,
	name: string,
	centre: Vector3,
	diameter: number,
	height: number,
	color: string | Color3,
	extra: Extra?
): BasePart
	return WorldUtil.part(
		parent,
		withExtra({
			name = name,
			size = Vector3.new(height, diameter, diameter),
			cf = CFrame.new(centre) * CFrame.Angles(0, 0, math.pi / 2),
			color = color,
			shape = Enum.PartType.Cylinder,
		}, extra)
	)
end

-- Flat disc whose TOP face is at topY, centred on (x, z).
function WorldUtil.disc(
	parent: Instance,
	name: string,
	x: number,
	topY: number,
	z: number,
	radius: number,
	height: number,
	color: string | Color3,
	extra: Extra?
): BasePart
	return WorldUtil.cylinder(
		parent,
		name,
		Vector3.new(x, topY - height / 2, z),
		radius * 2,
		height,
		color,
		extra
	)
end

-- Cylinder from point a to point b (a little longer than the gap so joints overlap).
function WorldUtil.pole(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	thickness: number,
	color: string | Color3,
	extra: Extra?
): BasePart
	local length = (b - a).Magnitude + 0.15
	local mid = (a + b) / 2
	return WorldUtil.part(
		parent,
		withExtra({
			name = name,
			size = Vector3.new(length, thickness, thickness),
			cf = CFrame.lookAt(mid, b) * CFrame.Angles(0, math.pi / 2, 0),
			color = color,
			shape = Enum.PartType.Cylinder,
		}, extra)
	)
end

function WorldUtil.tag(inst: Instance, tag: string)
	CollectionService:AddTag(inst, tag)
end

-- 1234567 -> "1,234,567"
function WorldUtil.commas(n: number): string
	local out = tostring(math.floor(n + 0.5))
	while true do
		local replaced, changes = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
		out = replaced
		if changes == 0 then
			break
		end
	end
	return out
end

export type TextOpts = {
	text: string,
	textColor: string,
	font: Enum.Font?,
}

-- A flat label painted on one face of a part.
function WorldUtil.faceText(part: BasePart, face: Enum.NormalId, o: TextOpts)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = o.text
	label.TextScaled = true
	label.Font = o.font or Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromHex(o.textColor)
	label.Parent = gui
	gui.Parent = part
end

-- Sign board with text on the front AND the back, so it reads from both sides.
function WorldUtil.signBoard(
	parent: Instance,
	name: string,
	cf: CFrame,
	size: Vector3,
	bg: string,
	fg: string,
	text: string
): BasePart
	local board = WorldUtil.block(parent, name, cf, size, bg, { shadow = true })
	WorldUtil.faceText(board, Enum.NormalId.Front, { text = text, textColor = fg })
	WorldUtil.faceText(board, Enum.NormalId.Back, { text = text, textColor = fg })
	return board
end

-- Flat glowing arrow lying in the air, pointing along the frame's -Z (frame = CFrame at the tail).
function WorldUtil.arrow(parent: Instance, frame: CFrame, color: string)
	WorldUtil.block(
		parent,
		"ArrowShaft",
		frame * CFrame.new(0, 0, -2),
		Vector3.new(0.9, 0.9, 4),
		color,
		{
			material = Enum.Material.Neon,
		}
	)
	WorldUtil.block(
		parent,
		"ArrowHead",
		frame * CFrame.new(0, 0, -4.6) * CFrame.Angles(math.pi / 4, 0, 0),
		Vector3.new(0.9, 2.6, 2.6),
		color,
		{ material = Enum.Material.Neon }
	)
end

export type EmitterOpts = {
	colorA: string,
	colorB: string,
	rate: number,
	lifeMin: number,
	lifeMax: number,
	speedMin: number,
	speedMax: number,
	sizeA: number,
	sizeB: number,
	spread: number,
	accel: Vector3?,
	light: number?,
	alpha: number?, -- starting transparency (0 solid .. 1 invisible)
	texture: string?,
	direction: Enum.NormalId?, -- which face of the part particles leave from (flat discs: Right = up)
}

function WorldUtil.emitter(parent: Instance, o: EmitterOpts): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(Color3.fromHex(o.colorA), Color3.fromHex(o.colorB))
	e.Size = NumberSequence.new(o.sizeA, o.sizeB)
	local a0 = o.alpha or 0.3
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, a0),
		NumberSequenceKeypoint.new(0.7, a0 + (1 - a0) * 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(o.lifeMin, o.lifeMax)
	e.Rate = o.rate
	e.Speed = NumberRange.new(o.speedMin, o.speedMax)
	e.SpreadAngle = Vector2.new(o.spread, o.spread)
	e.Acceleration = o.accel or Vector3.zero
	e.LightEmission = o.light or 0
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-40, 40)
	e.LockedToPart = false
	if o.texture then
		e.Texture = o.texture
	end
	if o.direction then
		e.EmissionDirection = o.direction
	end
	e.Parent = parent
	return e
end

-- Invisible little part that carries emitters.
function WorldUtil.emitterAnchor(
	parent: Instance,
	name: string,
	cf: CFrame,
	size: Vector3
): BasePart
	return WorldUtil.block(parent, name, cf, size, "#FFFFFF", { transparency = 1 })
end

return WorldUtil
