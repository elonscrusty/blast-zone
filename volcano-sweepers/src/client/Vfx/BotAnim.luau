--!strict
-- Makes the helper bots feel alive on THIS client: their "Spin*" parts turn (the Roller's brush,
-- the Bumble's propeller) and their "Bob*" parts bob (antenna bulb, crater bubbles). The server
-- builds the bots (server/Helpers/BotModel) and never sends these little moves; a Weld C0 written
-- here stays on this client. Purely cosmetic. Only bots within ANIM_RADIUS of the camera move.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HelperBots = require(Shared.Models.HelperBots)

local BotAnim = {}

local FOLDER_NAME = "VSHelpers"
local ANIM_RADIUS = 90 -- studs from the camera
local SCAN_GAP = 0.5 -- seconds between looking for new / gone bots and distance checks
local SPIN_SPEED: { [string]: number } = { A = 14, B = 9, C = 6 } -- radians a second
local BOB_HEIGHT = 0.08 -- studs
local BOB_SPEED = 3 -- radians a second

type Mover = { weld: Weld, base: CFrame, phase: number }
type Rec = {
	root: BasePart,
	axis: Vector3,
	speed: number,
	spin: { Mover },
	bob: { Mover },
	near: boolean,
}

local recs: { [Model]: Rec } = {}

local function movers(parts: { BasePart }): { Mover }
	local out: { Mover } = {}
	for i, p in parts do
		local w = p:FindFirstChild("PartWeld")
		if w ~= nil and w:IsA("Weld") then
			table.insert(out, { weld = w, base = w.C0, phase = i * 1.7 })
		end
	end
	return out
end

local function recFor(model: Model): Rec?
	local root = model.PrimaryPart
	if root == nil then
		return nil -- not streamed in yet: try again on the next scan
	end
	local attr = model:GetAttribute("Look")
	local look = if type(attr) == "string" then attr else HelperBots.defaultLook
	return {
		root = root,
		axis = HelperBots.spinAxis(look),
		speed = SPIN_SPEED[look] or SPIN_SPEED.B,
		spin = movers(HelperBots.spinParts(model)),
		bob = movers(HelperBots.bobParts(model)),
		near = false,
	}
end

local function scan()
	local folder = workspace:FindFirstChild(FOLDER_NAME)
	for model in recs do
		if folder == nil or model.Parent ~= folder then
			recs[model] = nil
		end
	end
	if folder == nil then
		return
	end
	local cam = workspace.CurrentCamera
	local from = if cam ~= nil then cam.CFrame.Position else nil
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			if recs[child] == nil then
				local made = recFor(child) -- nil until the bot has streamed in: try again next scan
				if made ~= nil then
					recs[child] = made
				end
			end
			local rec = recs[child]
			if rec ~= nil then
				rec.near = from ~= nil
					and rec.root.Parent ~= nil
					and (rec.root.Position - from).Magnitude <= ANIM_RADIUS
			end
		end
	end
end

local function animate(t: number)
	for _, rec in recs do
		if rec.near then
			local turn = CFrame.fromAxisAngle(rec.axis, t * rec.speed)
			for _, m in rec.spin do
				-- turn the part about its own centre, around the model-space axis
				m.weld.C0 = CFrame.new(m.base.Position) * turn * m.base.Rotation
			end
			for _, m in rec.bob do
				m.weld.C0 = m.base
					+ Vector3.new(0, BOB_HEIGHT * math.sin(t * BOB_SPEED + m.phase), 0)
			end
		end
	end
end

local scanAcc = SCAN_GAP
RunService.Heartbeat:Connect(function(dt: number)
	scanAcc += dt
	if scanAcc >= SCAN_GAP then
		scanAcc = 0
		local ok, err = pcall(scan)
		if not ok then
			warn(`[BotAnim] {err}`)
		end
	end
	animate(os.clock())
end)

return BotAnim
