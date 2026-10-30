--!strict
-- One step of a slow shell. Pure: walls come in as a function so Lune can test it.

local Ballistics = require("./Ballistics")

local ShellFlight = {}

export type Shell = {
	x: number,
	z: number,
	dx: number, -- unit direction on the ground plane
	dz: number,
	speed: number,
	remaining: number, -- studs of flight left
}

export type Burst = { x: number, z: number, reason: "target" | "wall" | "range", targetId: string? }

-- A shell that touches a wall bursts this far in front of it, so the blast centre is never inside the wall.
ShellFlight.WALL_BACKOFF = 0.4

-- Moves the shell by dt. Returns a Burst when it ends, otherwise nil.
-- wallDistance(x, z, dx, dz, dist) -> studs to the nearest wall within dist, or nil.
-- `targets` should already leave out the shell's owner (a shell never bursts on the person who fired it).
function ShellFlight.step(
	shell: Shell,
	dt: number,
	wallDistance: (number, number, number, number, number) -> number?,
	targets: { Ballistics.Target }
): Burst?
	local dist = math.min(shell.speed * dt, shell.remaining)
	if dist <= 0 then
		return { x = shell.x, z = shell.z, reason = "range" }
	end
	local wall = wallDistance(shell.x, shell.z, shell.dx, shell.dz, dist)
	local hit = Ballistics.firstHit(shell.x, shell.z, shell.dx, shell.dz, dist, wall, targets)
	if hit.kind == "target" then
		return {
			x = shell.x + shell.dx * hit.dist,
			z = shell.z + shell.dz * hit.dist,
			reason = "target",
			targetId = hit.id,
		}
	elseif hit.kind == "wall" then
		local back = math.max(0, hit.dist - ShellFlight.WALL_BACKOFF)
		return { x = shell.x + shell.dx * back, z = shell.z + shell.dz * back, reason = "wall" }
	end
	shell.x += shell.dx * dist
	shell.z += shell.dz * dist
	shell.remaining -= dist
	if shell.remaining <= 1e-6 then
		return { x = shell.x, z = shell.z, reason = "range" }
	end
	return nil
end

return ShellFlight
