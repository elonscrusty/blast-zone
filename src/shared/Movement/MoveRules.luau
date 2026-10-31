--!strict
-- Walking maths as plain numbers (no Roblox types) so Lune can test it.

local CameraRules = require("./CameraRules")

local MoveRules = {}

-- What the stat sheet says, held between zero and the hard cap so a stack of upgrades cannot
-- make the camera or the collision misbehave.
function MoveRules.clampSpeed(value: number, base: number, maxMultiplier: number): number
	if value ~= value then
		return base
	end
	return math.clamp(value, 0, base * maxMultiplier)
end

-- The speed for a fighter: the plaza between matches is walked at a brisker pace than the arena (video-feel
-- pass: the arena run is slow on purpose; a menu walk is not). `inPlaza` comes from where the body stands
-- (LobbyLayout.contains), so it is right in every phase: the wait, the countdown, a reset, someone who joins
-- mid-match. This is the ONE place the plaza pace is decided: apply, setSpeed and the sprint tick all call it.
-- `cfg` is Config.Movement (walkSpeed, lobbyWalkSpeed, maxSpeedUpgradeMultiplier).
export type SpeedConfig = {
	walkSpeed: number,
	lobbyWalkSpeed: number,
	maxSpeedUpgradeMultiplier: number,
}

function MoveRules.lobbyScale(inPlaza: boolean, walkSpeed: number, lobbyWalkSpeed: number): number
	if not inPlaza then
		return 1
	end
	if
		walkSpeed ~= walkSpeed
		or lobbyWalkSpeed ~= lobbyWalkSpeed
		or walkSpeed <= 0
		or lobbyWalkSpeed <= 0
	then
		return 1
	end
	return lobbyWalkSpeed / walkSpeed
end

-- The walk speed to give the humanoid: the stat sheet's speed, plaza-scaled, clamped to the hard cap.
function MoveRules.walkSpeed(inPlaza: boolean, moveSpeed: number, cfg: SpeedConfig): number
	local k = MoveRules.lobbyScale(inPlaza, cfg.walkSpeed, cfg.lobbyWalkSpeed)
	return MoveRules.clampSpeed(moveSpeed * k, cfg.walkSpeed * k, cfg.maxSpeedUpgradeMultiplier)
end

-- The same with the sprint boost on top while running. The boost has its own hard cap, which also follows
-- the plaza scale, so an upgrade stack can never push the run past it.
function MoveRules.sprintWalkSpeed(
	inPlaza: boolean,
	moveSpeed: number,
	running: boolean,
	cfg: SpeedConfig,
	sprintMultiplier: number
): number
	local k = MoveRules.lobbyScale(inPlaza, cfg.walkSpeed, cfg.lobbyWalkSpeed)
	local normal = MoveRules.walkSpeed(inPlaza, moveSpeed, cfg)
	local cap = cfg.walkSpeed * k * cfg.maxSpeedUpgradeMultiplier * sprintMultiplier
	if not running then
		return normal
	end
	return math.min(normal * sprintMultiplier, cap)
end

-- The controls give (right, forward) with length <= 1, forward = up the screen. Returns the
-- ground direction (x, z) for Humanoid:Move; the length is kept so a gentle push walks slower.
function MoveRules.moveToWorld(right: number, forward: number, headingDeg: number): (number, number)
	local rx, rz = CameraRules.right(headingDeg)
	local fx, fz = CameraRules.forward(headingDeg)
	return rx * right + fx * forward, rz * right + fz * forward
end

return MoveRules
