--!strict
-- Carries a body over cover along an arc (piece 44). Used by the client for its own character (the
-- owner moves it). For the length of the hop the body's parts join the "Vaulting" collision group,
-- which touches nothing, and a velocity constraint steers the body along the arc, so walls and
-- gravity do not matter until it lands. Groups are put back when the hop ends or is cancelled.

local RunService = game:GetService("RunService")

local Shared = script.Parent.Parent
local Config = require(Shared.Config)
local VaultRules = require("./VaultRules")

local VaultMotion = {}

export type Handle = {
	cancel: () -> (),
	isRunning: () -> boolean,
}

local MAX_FORCE = 1e7
local MAX_SPEED = 90 -- studs/s the steering may ask for in one step

function VaultMotion.run(
	character: Model,
	root: BasePart,
	toPos: Vector3,
	peak: number,
	duration: number,
	onDone: (() -> ())?
): Handle
	local from = root.Position
	local saved: { [BasePart]: string } = {}
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			saved[d] = d.CollisionGroup
			pcall(function()
				d.CollisionGroup = Config.CollisionGroups.Vaulting
			end)
		end
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "VaultAttachment"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "VaultVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.VectorVelocity = Vector3.zero
	velocity.MaxForce = MAX_FORCE
	velocity.Parent = root

	local running = true
	local elapsed = 0
	local connection: RBXScriptConnection? = nil

	local function finish()
		if not running then
			return
		end
		running = false
		if connection then
			connection:Disconnect()
			connection = nil
		end
		velocity:Destroy()
		attachment:Destroy()
		for part, group in saved do
			if part.Parent ~= nil then
				pcall(function()
					part.CollisionGroup = group
				end)
			end
		end
		if root.Parent ~= nil then
			root.AssemblyLinearVelocity = Vector3.zero -- land crisply, do not skate on
		end
		if onDone then
			onDone()
		end
	end

	connection = RunService.PreSimulation:Connect(function(dt: number)
		if root.Parent == nil then
			finish()
			return
		end
		elapsed += dt
		local u = elapsed / math.max(duration, 0.05)
		if u >= 1 then
			finish()
			return
		end
		local x, y, z = VaultRules.arc(from.X, from.Y, from.Z, toPos.X, toPos.Y, toPos.Z, peak, u)
		local want = (Vector3.new(x, y, z) - root.Position) / math.max(dt, 1 / 120)
		if want.Magnitude > MAX_SPEED then
			want = want.Unit * MAX_SPEED
		end
		velocity.VectorVelocity = want
	end)

	return {
		cancel = finish,
		isRunning = function()
			return running
		end,
	}
end

return VaultMotion
