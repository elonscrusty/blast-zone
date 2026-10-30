--!strict
-- Moves a body along a slide with a temporary velocity constraint. Used by the client for its own
-- character (the owner moves it) and by the server for bots. The constraint is removed when the
-- slide ends, so friction, speed and collision are never changed for good. Walls stop it because
-- it is real physics, not a teleport.

local RunService = game:GetService("RunService")

local SlideRules = require("./SlideRules")

local SlideMotion = {}

export type Handle = {
	cancel: () -> (),
	retarget: (distance: number, duration: number) -> (),
	isRunning: () -> boolean,
}

local MAX_FORCE = 1e7

function SlideMotion.run(
	root: BasePart,
	dirX: number,
	dirZ: number,
	distance: number,
	duration: number,
	onDone: (() -> ())?
): Handle
	local attachment = Instance.new("Attachment")
	attachment.Name = "SlideAttachment"
	attachment.Parent = root

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "SlideVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.PlaneVelocity = Vector2.zero
	velocity.MaxForce = MAX_FORCE
	velocity.Parent = root

	local running = true
	local elapsed = 0
	local travelled = 0
	local lastPos = root.Position
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
		if root.Parent ~= nil then
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0) -- stop crisply, do not skate on
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
		local pos = root.Position
		travelled += math.max(0, (pos.X - lastPos.X) * dirX + (pos.Z - lastPos.Z) * dirZ)
		lastPos = pos
		elapsed += dt
		if elapsed >= duration or travelled >= distance - 0.05 then
			finish()
			return
		end
		-- Never ask for more than is left, so a long frame cannot overshoot the allowed distance.
		local speed = math.min(
			SlideRules.speedAt(distance, duration, elapsed),
			(distance - travelled) / math.max(dt, 1 / 120)
		)
		velocity.PlaneVelocity = Vector2.new(dirX * speed, dirZ * speed)
	end)

	return {
		cancel = finish,
		retarget = function(newDistance: number, newDuration: number)
			distance = newDistance
			duration = newDuration
		end,
		isRunning = function()
			return running
		end,
	}
end

return SlideMotion
