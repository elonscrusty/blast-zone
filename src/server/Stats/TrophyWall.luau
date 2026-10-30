--!strict
-- The 3D top-wins board in the lobby (piece 24, carter's pick A "Trophy Wall"):
-- a cream sticker board on two posts, with gold, silver and bronze podiums and trophies in front.
-- The server builds it and fills the top list. Each client fills the YOU row with its own stats
-- (StatsClientSystem), hides the board during a fight and spins the trophies.
-- Nothing here collides or blocks shots: CanCollide, CanQuery and CanTouch are all off.
--
--   local wall = TrophyWall.build(rootCFrame)   -- rootCFrame: on the ground, LookVector toward the players
--   wall.setRows(rows)                          -- BoardRules rows, best first
--   wall.setStatus(text)                        -- small line under the list ("" hides it)

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

local CREAM = Color3.fromHex("#FFF4D6")
local NAVY = Color3.fromHex("#14243A")
local GOLD = Color3.fromHex("#FFC44D")
local SILVER = Color3.fromHex("#C9D3DF")
local BRONZE = Color3.fromHex("#E0915A")
local MEDALS = { GOLD, SILVER, BRONZE }
local FONT = Enum.Font.FredokaOne

local BOARD_W, BOARD_H, BOARD_D = 14, 17, 1
local POST_H = 6 -- tall enough that the gold trophy never covers the YOU row
local PIXELS_PER_STUD = 50
local PODIUM_Z = 9 -- studs in front of the board

local TrophyWall = {}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function corner(parent: Instance, scale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = parent
end

local function stroke(parent: Instance, px: number)
	local s = Instance.new("UIStroke")
	s.Color = NAVY
	s.Thickness = px
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function label(
	parent: Instance,
	name: string,
	text: string,
	color: Color3,
	align: Enum.TextXAlignment
): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = true
	l.TextXAlignment = align
	l.Parent = parent
	return l
end

local function surface(target: BasePart, name: string): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0.3
	gui.MaxDistance = 250
	gui.Adornee = target
	gui.Parent = target
	return gui
end

-- A simple cup out of cylinders: foot, stem, bowl, rim and two handles.
local function trophy(
	parent: Instance,
	name: string,
	base: CFrame,
	color: Color3,
	scale: number
): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	local up = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder's length runs along X; turn it upright
	local function piece(n: string, h: number, d: number, y: number)
		local p =
			part(m, n, Vector3.new(h, d, d) * scale, base * CFrame.new(0, y * scale, 0) * up, color)
		p.Material = Enum.Material.Metal
		p.Reflectance = 0.15
		p.Shape = Enum.PartType.Cylinder
		return p
	end
	piece("Foot", 0.3, 1.6, 0.15)
	piece("Stem", 1.0, 0.45, 0.8)
	piece("Bowl", 1.2, 1.7, 1.9)
	piece("Rim", 0.15, 2.0, 2.55)
	for _, side in { -1, 1 } do
		local h = part(
			m,
			"Handle",
			Vector3.new(0.25, 1.0, 0.25) * scale,
			base * CFrame.new(side * 1.05 * scale, 2.0 * scale, 0),
			color
		)
		h.Material = Enum.Material.Metal
	end
	m.WorldPivot = base -- upright, so clients can spin the cup around world up
	m:SetAttribute("Spin", true)
	return m
end

function TrophyWall.build(root: CFrame): Wall
	local cfg = Config.Stats.board
	local old = workspace:FindFirstChild(cfg.modelName)
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = cfg.modelName

	-- Board and posts. Local space: -Z (LookVector) is toward the players, so the board's Front face looks at them.
	local boardCf = root * CFrame.new(0, POST_H + BOARD_H / 2, 0)
	local board = part(model, "Board", Vector3.new(BOARD_W, BOARD_H, BOARD_D), boardCf, NAVY)
	for _, x in { -5, 5 } do
		part(
			model,
			"Post",
			Vector3.new(1.2, POST_H, 1.2),
			root * CFrame.new(x, POST_H / 2, 0),
			NAVY
		)
	end

	local gui = surface(board, "Face")
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = CREAM
	panel.Position = UDim2.fromScale(0.025, 0.02)
	panel.Size = UDim2.fromScale(0.95, 0.96)
	panel.Parent = gui
	corner(panel, 0.05)

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundColor3 = GOLD
	header.Position = UDim2.fromScale(0.06, 0.025)
	header.Size = UDim2.fromScale(0.88, 0.1)
	header.Parent = panel
	corner(header, 0.3)
	stroke(header, 6)
	local title = label(header, "Title", "TOP WINS", NAVY, Enum.TextXAlignment.Center)
	title.Size = UDim2.fromScale(1, 0.8)
	title.Position = UDim2.fromScale(0, 0.1)

	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromScale(0.06, 0.15)
	list.Size = UDim2.fromScale(0.88, 0.6)
	list.Parent = panel

	local rowLabels: { { name: TextLabel, wins: TextLabel, rank: TextLabel, frame: Frame } } = {}
	local count = cfg.rows
	for i = 1, count do
		local row = Instance.new("Frame")
		row.Name = `Row{i}`
		row.BackgroundColor3 = NAVY
		row.BackgroundTransparency = if i % 2 == 1 then 0.93 else 1
		row.BorderSizePixel = 0
		row.Position = UDim2.fromScale(0, (i - 1) / count)
		row.Size = UDim2.fromScale(1, 1 / count)
		row.Parent = list

		local medal = MEDALS[i]
		local badge = Instance.new("Frame")
		badge.Name = "Badge"
		badge.BackgroundColor3 = medal or CREAM
		badge.BackgroundTransparency = if medal then 0 else 1
		badge.Position = UDim2.fromScale(0.01, 0.1)
		badge.Size = UDim2.fromScale(0.09, 0.8)
		badge.Parent = row
		corner(badge, 0.5)
		if medal then
			stroke(badge, 4)
		end
		local rank = label(badge, "Rank", tostring(i), NAVY, Enum.TextXAlignment.Center)
		rank.Size = UDim2.fromScale(1, 0.8)
		rank.Position = UDim2.fromScale(0, 0.1)

		local name = label(row, "PlayerName", "", NAVY, Enum.TextXAlignment.Left)
		name.Position = UDim2.fromScale(0.14, 0.15)
		name.Size = UDim2.fromScale(0.6, 0.7)
		local wins = label(row, "Wins", "", NAVY, Enum.TextXAlignment.Right)
		wins.Position = UDim2.fromScale(0.74, 0.15)
		wins.Size = UDim2.fromScale(0.24, 0.7)
		table.insert(rowLabels, { name = name, wins = wins, rank = rank, frame = row })
	end

	local status = label(panel, "Status", "Loading...", NAVY, Enum.TextXAlignment.Center)
	status.Position = UDim2.fromScale(0.06, 0.4)
	status.Size = UDim2.fromScale(0.88, 0.06)

	-- YOU row: left blank here; each client writes its own numbers into its own copy.
	local you = Instance.new("Frame")
	you.Name = "YouRow"
	you.BackgroundColor3 = NAVY
	you.Position = UDim2.fromScale(0.06, 0.79)
	you.Size = UDim2.fromScale(0.88, 0.18)
	you.Parent = panel
	corner(you, 0.25)
	local youTitle = label(you, "YouTitle", "YOU", GOLD, Enum.TextXAlignment.Left)
	youTitle.Position = UDim2.fromScale(0.05, 0.08)
	youTitle.Size = UDim2.fromScale(0.5, 0.38)
	local youLine = label(you, "YouLine", "", CREAM, Enum.TextXAlignment.Left)
	youLine.Position = UDim2.fromScale(0.05, 0.52)
	youLine.Size = UDim2.fromScale(0.9, 0.36)

	-- Podiums: gold in the middle (tallest), silver left, bronze right, in front of the board.
	local plates: { TextLabel } = {}
	local podiums = { { x = 0, h = 4.5 }, { x = -5, h = 3 }, { x = 5, h = 2 } }
	for i, spec in podiums do
		local color = MEDALS[i]
		local block = part(
			model,
			`Podium{i}`,
			Vector3.new(4.4, spec.h, 4.4),
			root * CFrame.new(spec.x, spec.h / 2, -PODIUM_Z),
			color
		)
		part(
			model,
			`PodiumEdge{i}`,
			Vector3.new(4.7, 0.35, 4.7),
			root * CFrame.new(spec.x, spec.h, -PODIUM_Z),
			NAVY
		)
		local plateGui = surface(block, "Plate")
		local plateBack = Instance.new("Frame")
		plateBack.Name = "Back"
		plateBack.BackgroundColor3 = color
		plateBack.Position = UDim2.fromScale(0.05, 0.12)
		plateBack.Size = UDim2.fromScale(0.9, math.min(0.76, 1.6 / spec.h))
		plateBack.Parent = plateGui
		corner(plateBack, 0.3)
		stroke(plateBack, 5)
		local plate = label(plateBack, "PlayerName", "", NAVY, Enum.TextXAlignment.Center)
		plate.Size = UDim2.fromScale(0.9, 0.8)
		plate.Position = UDim2.fromScale(0.05, 0.1)
		table.insert(plates, plate)
		trophy(
			model,
			`Trophy{i}`,
			root * CFrame.new(spec.x, spec.h + 0.2, -PODIUM_Z),
			color,
			if i == 1 then 1.15 else 0.9
		)
	end

	model.Parent = workspace

	local wall = {} :: Wall
	wall.model = model

	function wall.setRows(rows: { Row })
		for i, cell in rowLabels do
			local row = rows[i]
			cell.name.Text = if row then row.name else ""
			cell.wins.Text = if row then `{BoardRules.short(row.wins)} 🏆` else ""
			cell.rank.Visible = row ~= nil or i <= 3
		end
		for i, plate in plates do
			local row = rows[i]
			plate.Text = if row then row.name else "???"
		end
		if #rows == 0 then
			wall.setStatus("Win a match to get on the board!")
		else
			wall.setStatus("")
		end
	end

	function wall.setStatus(text: string)
		status.Text = text
		status.Visible = text ~= ""
	end

	return wall
end

return TrophyWall
