--!strict
-- The 3D top-wins board in the lobby (piece 24, carter's pick B "Neon Tower"):
-- a tall dark tower with a glowing pink edge and cap, a cyan edge, and neon rows.
-- Same doors as TrophyWall (the A skin): the server fills the top list; each client fills the
-- YOU row with its own stats and hides the board during a fight (StatsClientSystem).
-- Nothing here collides or blocks shots: CanCollide, CanQuery and CanTouch are all off.
--
--   local tower = NeonTower.build(rootCFrame)   -- rootCFrame: on the ground, LookVector toward the players
--   tower.setRows(rows) / tower.setStatus(text)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BoardRules = require(Shared.Stats.BoardRules)

type Row = BoardRules.Row

export type Wall = {
	model: Model,
	setRows: (rows: { Row }) -> (),
	setStatus: (text: string) -> (),
}

local DARK = Color3.fromHex("#0B0F1D")
local PINK = Color3.fromHex("#FF4FD8")
local PINK_TEXT = Color3.fromHex("#FF8AE6")
local CYAN = Color3.fromHex("#3EE8FF")
local CYAN_TEXT = Color3.fromHex("#A8F6FF")
local GOLD_TEXT = Color3.fromHex("#FFE58A")
local GOLD_GLOW = Color3.fromHex("#FFD84D")
local YOU_TEXT = Color3.fromHex("#FFD6F6")
local FONT = Enum.Font.FredokaOne

local TOWER_W, TOWER_H, TOWER_D = 11, 22, 2
local BASE_H = 1
local STRIP = 0.4 -- glowing edge thickness
local PIXELS_PER_STUD = 40

local NeonTower = {}

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	neon: boolean
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = not neon
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Reflectance = if neon then 0 else 0.08
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Neon text: bright fill plus a soft colored stroke as the glow.
local function glowText(
	parent: Instance,
	name: string,
	text: string,
	fill: Color3,
	glow: Color3,
	align: Enum.TextXAlignment
): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.Text = text
	l.TextColor3 = fill
	l.TextStrokeColor3 = glow
	l.TextStrokeTransparency = 0.45
	l.TextScaled = true
	l.TextXAlignment = align
	l.Parent = parent
	return l
end

local function light(parent: BasePart, color: Color3, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = 16
	l.Shadows = false
	l.Parent = parent
end

function NeonTower.build(root: CFrame): Wall
	local cfg = Config.Stats.board
	local old = workspace:FindFirstChild(cfg.modelName)
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = cfg.modelName

	-- Local space: -Z (LookVector) is toward the players, so the Front face looks at them.
	local midY = BASE_H + TOWER_H / 2
	local tower = part(
		model,
		"Board",
		Vector3.new(TOWER_W, TOWER_H, TOWER_D),
		root * CFrame.new(0, midY, 0),
		DARK,
		false
	)
	tower.Material = Enum.Material.Glass
	tower.Transparency = 0
	part(
		model,
		"Base",
		Vector3.new(TOWER_W + 1.6, BASE_H, TOWER_D + 2),
		root * CFrame.new(0, BASE_H / 2, 0),
		DARK,
		false
	)
	local left = part(
		model,
		"EdgePink",
		Vector3.new(STRIP, TOWER_H + 0.6, TOWER_D + 0.2),
		root * CFrame.new(-(TOWER_W + STRIP) / 2, midY, 0),
		PINK,
		true
	)
	local right = part(
		model,
		"EdgeCyan",
		Vector3.new(STRIP, TOWER_H + 0.6, TOWER_D + 0.2),
		root * CFrame.new((TOWER_W + STRIP) / 2, midY, 0),
		CYAN,
		true
	)
	part(
		model,
		"Cap",
		Vector3.new(TOWER_W + STRIP * 2 + 0.4, STRIP, TOWER_D + 0.4),
		root * CFrame.new(0, BASE_H + TOWER_H + STRIP / 2, 0),
		PINK,
		true
	)
	part(
		model,
		"BaseGlow",
		Vector3.new(TOWER_W + 1.8, 0.15, TOWER_D + 2.2),
		root * CFrame.new(0, BASE_H + 0.05, 0),
		CYAN,
		true
	)
	light(left, PINK, 1.6)
	light(right, CYAN, 1.3)

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0 -- it glows: same brightness day and night
	gui.MaxDistance = 250
	gui.Adornee = tower
	gui.Parent = tower

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundTransparency = 1
	panel.Size = UDim2.fromScale(1, 1)
	panel.Parent = gui

	local title = glowText(panel, "Title", "TOP WINS", PINK_TEXT, PINK, Enum.TextXAlignment.Center)
	title.Position = UDim2.fromScale(0.08, 0.03)
	title.Size = UDim2.fromScale(0.84, 0.08)

	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromScale(0.08, 0.15)
	list.Size = UDim2.fromScale(0.84, 0.62)
	list.Parent = panel

	local rowLabels: { { name: TextLabel, wins: TextLabel } } = {}
	local count = cfg.rows
	for i = 1, count do
		local top3 = i <= 3
		local fill = if top3 then GOLD_TEXT else CYAN_TEXT
		local glow = if top3 then GOLD_GLOW else CYAN
		local row = Instance.new("Frame")
		row.Name = `Row{i}`
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromScale(0, (i - 1) / count)
		row.Size = UDim2.fromScale(1, 1 / count)
		row.Parent = list
		local rank = glowText(row, "Rank", tostring(i), fill, glow, Enum.TextXAlignment.Left)
		rank.Position = UDim2.fromScale(0, 0.18)
		rank.Size = UDim2.fromScale(0.12, 0.64)
		local name = glowText(row, "PlayerName", "", fill, glow, Enum.TextXAlignment.Left)
		name.Position = UDim2.fromScale(0.14, 0.18)
		name.Size = UDim2.fromScale(0.62, 0.64)
		local wins = glowText(row, "Wins", "", fill, glow, Enum.TextXAlignment.Right)
		wins.Position = UDim2.fromScale(0.76, 0.18)
		wins.Size = UDim2.fromScale(0.24, 0.64)
		table.insert(rowLabels, { name = name, wins = wins })
	end

	local status =
		glowText(panel, "Status", "Loading...", CYAN_TEXT, CYAN, Enum.TextXAlignment.Center)
	status.Position = UDim2.fromScale(0.08, 0.42)
	status.Size = UDim2.fromScale(0.84, 0.05)

	-- YOU box: a pink neon outline. Left blank here; each client writes its own numbers.
	local you = Instance.new("Frame")
	you.Name = "YouRow"
	you.BackgroundTransparency = 1
	you.Position = UDim2.fromScale(0.06, 0.8)
	you.Size = UDim2.fromScale(0.88, 0.16)
	you.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = you
	local outline = Instance.new("UIStroke")
	outline.Color = PINK_TEXT
	outline.Thickness = 6
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outline.Parent = you
	local youTitle = glowText(you, "YouTitle", "YOU", YOU_TEXT, PINK, Enum.TextXAlignment.Center)
	youTitle.Position = UDim2.fromScale(0.05, 0.1)
	youTitle.Size = UDim2.fromScale(0.9, 0.36)
	local youLine = glowText(you, "YouLine", "", YOU_TEXT, PINK, Enum.TextXAlignment.Center)
	youLine.Position = UDim2.fromScale(0.05, 0.54)
	youLine.Size = UDim2.fromScale(0.9, 0.32)

	model.Parent = workspace

	local wall = {} :: Wall
	wall.model = model

	function wall.setStatus(text: string)
		status.Text = text
		status.Visible = text ~= ""
	end

	function wall.setRows(rows: { Row })
		for i, cell in rowLabels do
			local row = rows[i]
			cell.name.Text = if row then row.name else ""
			cell.wins.Text = if row then BoardRules.short(row.wins) else ""
		end
		wall.setStatus(if #rows == 0 then "Win a match to get on the board!" else "")
	end

	return wall
end

return NeonTower
