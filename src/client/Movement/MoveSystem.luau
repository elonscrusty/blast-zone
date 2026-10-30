--!strict
-- Walking, turning and sliding for the local player.
--   * Walk: piece 10's Controls give (right, forward); this turns that into a ground direction
--     using the camera heading and calls Humanoid:Move.
--   * Turn: the body faces the aim (Controls.getAimWorld), or the way it walks when nothing aims.
--   * Slide: on the "slide" action, start sliding at once (using the same rules the server uses)
--     and ask the server. The server decides: if it says no the slide is cancelled, and if the
--     distance differs this slide is stretched or cut to match.
--   * Hop (piece 44): the same Slide button hops over low cover when a hoppable thing is right in
--     front (the server plans it too and can say no). Sprint is a toggle the server enforces.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ids = require(Shared.Ids)
local MoveRules = require(Shared.Movement.MoveRules)
local SlideCast = require(Shared.Movement.SlideCast)
local SlideMotion = require(Shared.Movement.SlideMotion)
local SlideRules = require(Shared.Movement.SlideRules)
local VaultCast = require(Shared.Movement.VaultCast)
local VaultMotion = require(Shared.Movement.VaultMotion)
local Net = require(script.Parent.Parent.Core.Net)
local MoveState = require("./MoveState")
local SlideTrail = require("./SlideTrail")

local MoveSystem = {}
MoveSystem.order = 110

local BIND_NAME = "BlastZoneMove"
local player = Players.LocalPlayer
local ownId = Ids.player(player.UserId)

type Controls = {
	getMove: () -> any,
	getAimWorld: (() -> Vector3?)?,
	Action: { connect: (any, (string) -> ()) -> any },
}

local controls: Controls? = nil
local readyAt = 0 -- server time the slide is available again
local slide: SlideMotion.Handle? = nil
local hop: VaultMotion.Handle? = nil
local hopReadyAt = 0 -- os.clock() time the next hop may start (the server keeps the real one)
local facing: { root: BasePart, align: AlignOrientation }? = nil

local function loadControls()
	local folder = script.Parent.Parent:WaitForChild("Controls", 15)
	local module = if folder then folder:WaitForChild("Controls", 15) else nil
	if module == nil or not module:IsA("ModuleScript") then
		warn("[movement] Controls not found: walking and sliding stay on Roblox defaults")
		return
	end
	local ok, result = pcall(require, module)
	if not ok then
		warn(`[movement] Controls failed to load: {result}`)
		return
	end
	controls = result :: any
	controls.Action:connect(function(name: string)
		if name == "slide" then
			MoveSystem.requestSlide()
		elseif name == "sprint" then
			MoveSystem.toggleSprint()
		end
	end)
end

-- Controls.getMove returns (right, forward); accept a Vector2 too in case that is what it hands back.
local function readMove(c: Controls): (number, number)
	local packed = table.pack(c.getMove())
	local first: any = packed[1]
	if typeof(first) == "Vector2" then
		return first.X, first.Y
	elseif type(first) == "number" and type(packed[2]) == "number" then
		return first, packed[2]
	elseif type(first) == "table" then
		return first.x or first.X or 0, first.y or first.Y or 0
	end
	return 0, 0
end

local function bodyOfPlayer(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if character == nil then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function ensureFacing(root: BasePart): AlignOrientation
	local current = facing
	if current and current.root == root and current.align.Parent ~= nil then
		return current.align
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "BlastZoneFacingAttachment"
	attachment.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = "BlastZoneFacing"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = false
	align.Responsiveness = 60
	align.MaxTorque = 1e7
	align.MaxAngularVelocity = math.huge
	align.CFrame = root.CFrame.Rotation
	align.Parent = root
	facing = { root = root, align = align }
	return align
end

local function step()
	local c = controls
	local character, humanoid, root = bodyOfPlayer()
	if c == nil or character == nil or humanoid == nil or root == nil then
		return
	end
	if humanoid.Health <= 0 then
		if slide then
			slide.cancel()
		end
		if hop then
			hop.cancel()
		end
		return
	end

	local right, forward = readMove(c)
	local wx, wz = MoveRules.moveToWorld(right, forward, Config.Camera.yawDegrees)
	humanoid:Move(Vector3.new(wx, 0, wz), false)

	local aim: Vector3? = nil
	local getAim = c.getAimWorld
	if getAim then
		aim = getAim()
	end
	local ax, az = SlideRules.normalize(if aim then aim.X else wx, if aim then aim.Z else wz)
	if ax ~= nil and az ~= nil then
		ensureFacing(root).CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(ax, 0, az))
	end
end

local function cancelSlide()
	local running = slide
	if running then
		running.cancel()
	end
end

local function cancelHop()
	local running = hop
	if running then
		running.cancel()
	end
end

-- Hops over cover when something hoppable is right ahead. Returns true when a hop started.
local function tryHop(
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	dx: number,
	dz: number
): boolean
	if (hop and hop.isRunning()) or os.clock() < hopReadyAt then
		return false
	end
	local plan = VaultCast.plan(character, root, humanoid.HipHeight, dx, dz, nil)
	if plan == nil then
		return false
	end
	hopReadyAt = os.clock() + Config.Vault.cooldownSeconds
	Net.send("VaultRequest", Vector3.new(dx, 0, dz))
	hop = VaultMotion.run(character, root, plan.toPos, plan.peak, plan.duration)
	return true
end

function MoveSystem.toggleSprint()
	local _, humanoid = bodyOfPlayer()
	if humanoid == nil or humanoid.Health <= 0 then
		return
	end
	Net.send("SprintRequest", MoveState.toggleSprint())
end

function MoveSystem.requestSlide()
	local c = controls
	local character, humanoid, root = bodyOfPlayer()
	if c == nil or character == nil or humanoid == nil or root == nil then
		return
	end
	if humanoid.Health <= 0 or (slide and slide.isRunning()) or (hop and hop.isRunning()) then
		return
	end

	local right, forward = readMove(c)
	local mx, mz = MoveRules.moveToWorld(right, forward, Config.Camera.yawDegrees)
	local look = root.CFrame.LookVector
	local dx, dz = SlideRules.direction(mx, mz, look.X, look.Z)
	if dx == nil or dz == nil then
		return
	end

	if tryHop(character, humanoid, root, dx, dz) then
		return
	end
	if workspace:GetServerTimeNow() < readyAt then
		return
	end

	local distance =
		SlideCast.resolve(character, root, humanoid.HipHeight, dx, dz, Config.Slide.distance, nil)
	if distance < Config.Slide.minDistance then
		return -- a wall right there; the server would say no too
	end

	Net.send("SlideRequest", Vector3.new(dx, 0, dz))
	local duration = Config.Slide.duration
	slide = SlideMotion.run(root, dx, dz, distance, duration)
	SlideTrail.play(character, duration)
end

function MoveSystem.start()
	task.spawn(loadControls)

	Net.on(
		"SlideState",
		function(state: { cooldownEndsAt: number, charges: number?, maxCharges: number? })
			if type(state) ~= "table" then
				return
			end
			if type(state.cooldownEndsAt) == "number" then
				readyAt = state.cooldownEndsAt
			end
			if type(state.charges) == "number" and type(state.maxCharges) == "number" then
				MoveState.setSlide(state.charges, state.maxCharges)
			end
		end
	)
	Net.on("SlideDenied", cancelSlide)
	Net.on("VaultDenied", cancelHop)
	Net.on("SprintState", function(state: { stamina: number, running: boolean, locked: boolean })
		if
			type(state) == "table"
			and type(state.stamina) == "number"
			and type(state.running) == "boolean"
			and type(state.locked) == "boolean"
		then
			MoveState.setSprint(state.stamina, state.running, state.locked)
		end
	end)
	Net.on(
		"SlideFx",
		function(fx: { participantId: string, fromPos: Vector3, toPos: Vector3, duration: number })
			if type(fx) ~= "table" or fx.participantId ~= ownId then
				return
			end
			local running = slide
			if running and running.isRunning() then
				-- The server's numbers win (an upgrade may have changed the distance).
				running.retarget((fx.toPos - fx.fromPos).Magnitude, fx.duration)
			end
		end
	)

	-- No jumping in the combat design: turn the jump state off on every new body.
	local function onCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.AutoRotate = false
			for _, state in
				{
					Enum.HumanoidStateType.Jumping,
					Enum.HumanoidStateType.Climbing,
					Enum.HumanoidStateType.FallingDown,
				}
			do
				pcall(function()
					humanoid:SetStateEnabled(state, false)
				end)
			end
			humanoid.Died:Connect(function()
				cancelSlide()
				cancelHop()
			end)
		end
	end
	player.CharacterAdded:Connect(function(character)
		cancelSlide()
		cancelHop()
		MoveState.clearSprint()
		facing = nil
		onCharacter(character)
	end)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Character.Value, step)
end

return MoveSystem
