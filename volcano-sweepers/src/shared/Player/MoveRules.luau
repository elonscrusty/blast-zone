--!strict
-- How far a character may move between two looks, so server rules never trust a teleport.
-- Pure: positions, times and walk speed are passed in (server/Core/MoveWatch feeds it ~5 times a
-- second from os.clock and the HumanoidRootPart). Only the flat X/Z matters: falling is fine.
--
-- The idea: a "bank" of studs fills at allowedSpeed (1.5 x walk speed + 10, so jumps, knockbacks
-- and physics nudges are fine) up to a few seconds' worth. Every look spends the distance moved.
--   * Normal walking, a laggy client that stalls then catches up a few seconds later: always paid
--     from the bank -> "ok", the TRUSTED position follows the character.
--   * A teleport or a speed hack: the move costs more than the bank. The trusted position only
--     follows at the player's own walk speed ("clamped"), and the player is "suspect" until it caught
--     up. While suspect, Sweep / Sell / gems / gates use the trusted spot (or refuse).
--   * Repeated fresh jumps (3 in 20 s) or one absurd jump (> SNAP_GAP studs) ask the glue to put the
--     character back on the trusted spot. A single lag spike never does.
-- Respawns and server-side moves call reset() (with a short grace where anything is accepted).

local MoveRules = {}

MoveRules.SPEED_MULT = 1.5 -- x walk speed ...
MoveRules.SPEED_EXTRA = 10 -- ... + studs/s, the most a body may honestly move
MoveRules.BANK_SECONDS = 2.5 -- the bank holds this many seconds of allowed movement ...
MoveRules.SLACK = 12 -- ... plus these studs (replication jitter)
MoveRules.SUSPECT_SECONDS = 1 -- suspect this long after the last over-budget look
MoveRules.STRIKE_WINDOW = 20
MoveRules.STRIKES_TO_SNAP = 3
MoveRules.SNAP_GAP = 120 -- studs between trusted and real: nobody walks that in a lag spike
MoveRules.MAX_DT = 5 -- a long server hitch never counts for more than this

export type Track = {
	x: number, -- trusted (last known good) position
	z: number,
	t: number, -- time of the last look
	bank: number, -- studs that may still be moved without question
	graceUntil: number,
	suspectUntil: number,
	strikes: { number }, -- times of fresh over-budget jumps
}

local function finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

-- Studs per second a character may move with this walk speed.
function MoveRules.allowedSpeed(walkSpeed: number): number
	local w = if finite(walkSpeed) and walkSpeed > 0 then walkSpeed else 16
	return w * MoveRules.SPEED_MULT + MoveRules.SPEED_EXTRA
end

local function bankCap(speed: number): number
	return speed * MoveRules.BANK_SECONDS + MoveRules.SLACK
end

function MoveRules.new(x: number, z: number, now: number, graceSeconds: number?): Track
	return {
		x = if finite(x) then x else 0,
		z = if finite(z) then z else 0,
		t = now,
		bank = bankCap(MoveRules.allowedSpeed(16)),
		graceUntil = now + (graceSeconds or 0),
		suspectUntil = -math.huge,
		strikes = {},
	}
end

-- A respawn or a server-side move: trust (x, z) and accept anything for `graceSeconds`.
function MoveRules.reset(track: Track, x: number, z: number, now: number, graceSeconds: number?)
	if finite(x) and finite(z) then
		track.x, track.z = x, z
	end
	track.t = now
	track.graceUntil = math.max(track.graceUntil, now + (graceSeconds or 0))
	track.suspectUntil = -math.huge
	track.bank = bankCap(MoveRules.allowedSpeed(16))
end

function MoveRules.isSuspect(track: Track, now: number): boolean
	return now < track.suspectUntil
end

-- One look at the real position. Returns "ok", "clamped" (moved more than allowed; the trusted spot
-- moved toward it at walk speed only) or "bad" (non-finite input, ignored).
function MoveRules.observe(
	track: Track,
	x: number,
	z: number,
	now: number,
	walkSpeed: number
): "ok" | "clamped" | "bad"
	if not (finite(x) and finite(z) and finite(now)) then
		return "bad"
	end
	local dt = math.clamp(now - track.t, 0, MoveRules.MAX_DT)
	track.t = now
	local speed = MoveRules.allowedSpeed(walkSpeed)
	local suspect = now < track.suspectUntil
	-- while catching up after a jump, the trusted spot only moves at plain walking speed
	local walk = (speed - MoveRules.SPEED_EXTRA) / MoveRules.SPEED_MULT
	local refill = if suspect then walk else speed
	track.bank = math.min(bankCap(speed), track.bank + refill * dt)
	if now < track.graceUntil then
		track.x, track.z = x, z
		track.bank = bankCap(speed)
		return "ok"
	end
	local dx, dz = x - track.x, z - track.z
	local d = math.sqrt(dx * dx + dz * dz)
	if d <= track.bank then
		track.x, track.z = x, z
		track.bank -= d
		return "ok"
	end
	-- over budget: follow as far as the bank allows, no further
	local k = track.bank / d
	track.x += dx * k
	track.z += dz * k
	track.bank = 0
	if not suspect then
		table.insert(track.strikes, now)
	end
	track.suspectUntil = now + MoveRules.SUSPECT_SECONDS
	return "clamped"
end

-- Should the glue put the character back on the trusted spot? (Clears the strikes when yes.)
function MoveRules.shouldSnap(track: Track, x: number, z: number, now: number): boolean
	local strikes = track.strikes
	local keep: { number } = {}
	for _, t in strikes do
		if now - t <= MoveRules.STRIKE_WINDOW then
			table.insert(keep, t)
		end
	end
	track.strikes = keep
	local dx, dz = x - track.x, z - track.z
	local far = finite(dx) and finite(dz) and dx * dx + dz * dz > MoveRules.SNAP_GAP ^ 2
	if far or #keep >= MoveRules.STRIKES_TO_SNAP then
		track.strikes = {}
		return true
	end
	return false
end

-- Where a server rule should believe the player is RIGHT NOW, without changing the track:
-- the real (x, z) when it is reachable from the trusted spot since the last look, else the trusted
-- spot. The third result is false when the player is suspect or the real spot was not reachable.
function MoveRules.check(
	track: Track,
	x: number,
	z: number,
	now: number,
	walkSpeed: number
): (number, number, boolean)
	if not (finite(x) and finite(z)) then
		return track.x, track.z, false
	end
	if now < track.graceUntil then
		return x, z, true
	end
	if now < track.suspectUntil then
		return track.x, track.z, false
	end
	local speed = MoveRules.allowedSpeed(walkSpeed)
	local budget = math.min(
		bankCap(speed),
		track.bank + speed * math.clamp(now - track.t, 0, MoveRules.MAX_DT)
	)
	local dx, dz = x - track.x, z - track.z
	if dx * dx + dz * dz <= budget * budget then
		return x, z, true
	end
	return track.x, track.z, false
end

return MoveRules
