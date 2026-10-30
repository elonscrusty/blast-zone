--!strict
-- Emotes and winner poses, drawn from code like the rest of the body (no animation assets, so no ids).
-- Plain numbers only, so Lune can test them. Each emote fills a Pose (see Pose.luau for what the keys mean and
-- the angle convention); CharacterAnimSystem and the results banner put it on the rig.
--
-- Three sets of four (carter's emote tries A Street, B Hype, C Chill). Each set also has a winner pose.
-- Which set is free and which open on the coin track is EmoteRules' job, not this file's.
-- Ids are saved nowhere yet, but treat them as permanent: never rename one.

local Pose = require("./Pose")

local Emotes = {}

export type SetKey = "A" | "B" | "C"

export type Def = {
	id: string,
	name: string,
	set: SetKey,
	slot: number, -- 1..4 inside its set (1 and 2 are the easy ones)
}

local function clamp(x: number, a: number, b: number): number
	return math.max(a, math.min(b, x))
end

local function smooth(x: number): number
	x = clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Arms hanging loose, a slow breath.
local function stand(p: Pose.Pose, t: number)
	p.hy = math.sin(t * 2) * 0.03
	p.aRx, p.aRz, p.eRx = 0.05, 0.12, -0.25
	p.aLx, p.aLz, p.eLx = 0.05, 0.12, -0.25
end

-- ===== A Street =====

local function wave(p: Pose.Pose, t: number)
	stand(p, t)
	local k = smooth(t / 0.25)
	p.aLx = -2.75 * k
	p.aLz = (0.35 + math.sin(t * 9) * 0.35) * k
	p.eLx = -0.35 * k
	p.hrz = math.sin(t * 9) * 0.04
	p.ty, p.hdy = -0.15, -0.1
end

local function shuffle(p: Pose.Pose, t: number)
	local s = math.sin(t * 7)
	p.hy = -math.abs(s) * 0.2 - 0.05
	p.hrz = s * 0.12
	p.lLz = 0.12 + math.max(0, s) * 0.5
	p.lRz = -0.12 + math.min(0, s) * 0.5
	p.sLx, p.sRx = math.max(0, s) * 0.7, math.max(0, -s) * 0.7
	p.aRx, p.aLx = -1.0 + s * 0.6, -1.0 - s * 0.6
	p.eRx, p.eLx = -1.5, -1.5
	p.aRz, p.aLz = -0.2, 0.2
	p.ty, p.hdy = s * 0.3, -s * 0.2
end

local function flex(p: Pose.Pose, t: number)
	local k = smooth(t / 0.3)
	local pulse = math.sin(t * 5) * 0.5 + 0.5
	p.aRx, p.aRz, p.eRx = -1.57 * k, -1.35 * k, -(1.3 + 0.5 * pulse) * k
	p.aLx, p.aLz, p.eLx = -1.57 * k, 1.35 * k, -(1.3 + 0.5 * pulse) * k
	p.lRz, p.lLz = -0.2, 0.2
	p.sRx, p.sLx = 0.25 * pulse, 0.25 * pulse
	p.lRx, p.lLx = -0.12 * pulse, -0.12 * pulse
	p.hy, p.tx, p.hdx = -0.12 * pulse, -0.1, -0.15
end

-- "You're next": points at the camera, other hand on the hip.
local function point(p: Pose.Pose, t: number)
	local k = smooth(t / 0.25)
	local jab = math.max(0, math.sin(t * 6)) * 0.15
	p.aRx, p.aRz, p.eRx = -1.55 * k - jab, 0.05, -0.05
	p.aLx, p.aLz, p.eLx = 0.25, 0.75 * k, -1.7 * k
	p.ty, p.hdy = 0.2 * k, -0.15 * k
	p.hdx = -0.1 + math.sin(t * 6) * 0.06
	p.hrz = -0.06
	p.lRz, p.lLz = -0.12, 0.12
end

-- ===== B Hype =====

local function clap(p: Pose.Pose, t: number)
	local c = math.sin(t * 10) * 0.5 + 0.5
	local bounce = math.abs(math.sin(t * 5))
	p.aRx, p.aLx = -1.25, -1.25
	p.aRz, p.aLz = 0.55 - 0.85 * c, -(0.55 - 0.85 * c)
	p.eRx, p.eLx = -0.9, -0.9
	p.hy = -bounce * 0.12
	p.sRx, p.sLx = bounce * 0.3, bounce * 0.3
	p.lRx, p.lLx = -bounce * 0.12, -bounce * 0.12
	p.hdx = -0.1
end

local function cheer(p: Pose.Pose, t: number)
	local h = math.abs(math.sin(t * 4))
	local wig = math.sin(t * 8) * 0.12
	p.hy = h * 0.7
	p.aRx, p.aRz, p.eRx = -2.9, -0.45 - wig, -0.2
	p.aLx, p.aLz, p.eLx = -2.9, 0.45 + wig, -0.2
	p.sRx, p.sLx = 0.8 * (1 - h), 0.8 * (1 - h)
	p.lRx, p.lLx = -0.35 * (1 - h), -0.35 * (1 - h)
	p.hdx, p.tx = -0.3, -0.08
end

-- Snaps between four stiff poses; the body's smoothing does the "click".
local ROBOT = {
	{ -1.57, -1.57, 0, 0, 0.35 },
	{ 0, 0, -1.57, -1.57, -0.35 },
	{ -1.57, 0, -1.57, 0, 0 },
	{ 0, -1.57, 0, -1.57, 0 },
}
local function robot(p: Pose.Pose, t: number)
	local r = ROBOT[(math.floor(t * 2.5) % 4) + 1]
	p.aRx, p.eRx, p.aLx, p.eLx = r[1], r[2], r[3], r[4]
	p.ty, p.hdy = r[5], -r[5]
	p.aRz, p.aLz = 0.1, 0.1
	p.hy = (math.floor(t * 5) % 2) * -0.06
end

local function salute(p: Pose.Pose, t: number)
	stand(p, t)
	local k = smooth(t / 0.3)
	p.aRx, p.aRz, p.eRx = -1.3 * k, -1.05 * k, -2.35 * k
	p.hdx, p.tx = -0.12 * k, -0.06 * k
	p.lRz, p.lLz = -0.04, 0.04
end

-- ===== C Chill =====

local function shrug(p: Pose.Pose, t: number)
	local u = t % 1.6
	local c = smooth(u / 0.35) * (1 - smooth((u - 1.0) / 0.4))
	p.aRx, p.aRz, p.eRx = -0.35 * c, -0.55 * c + 0.1, -1.4 * c - 0.2
	p.aLx, p.aLz, p.eLx = -0.35 * c, 0.55 * c + 0.1, -1.4 * c - 0.2
	p.hy, p.hdy, p.hdx, p.ty = 0.06 * c, 0.25 * c, -0.12 * c, -0.1 * c
end

local function thumbs(p: Pose.Pose, t: number)
	stand(p, t)
	local k = smooth(t / 0.25)
	local pump = math.max(0, math.sin(t * 5)) * 0.18
	p.aLx, p.aLz, p.eLx = -1.15 * k - pump, -0.1, -1.25 * k
	p.hdx = -0.08 + math.sin(t * 5) * 0.07
	p.ty, p.hdy = -0.2 * k, 0.05
end

local function bob(p: Pose.Pose, t: number)
	local s = math.sin(t * 6)
	local a = math.abs(s)
	p.hrx, p.tx = 0.08, -0.12
	p.hdx = 0.22 * math.max(0, s) - 0.12
	p.hy = -a * 0.08
	p.sRx, p.sLx = a * 0.25, a * 0.25
	p.lRx, p.lLx = -a * 0.1, -a * 0.1
	p.aRx, p.aRz, p.eRx = 0.15, 0.2, -0.4 - a * 0.2
	p.aLx, p.aLz, p.eLx = 0.15, 0.2, -0.4 - a * 0.2
	p.ty = math.sin(t * 3) * 0.12
	p.lRz, p.lLz = -0.12, 0.12
end

local function bow(p: Pose.Pose, t: number)
	local u = t % 2.4
	local k = smooth(u / 0.45) * (1 - smooth((u - 1.5) / 0.5))
	p.tx, p.hrx, p.hdx = 0.85 * k, 0.15 * k, 0.35 * k
	p.aRx, p.aRz, p.eRx = -0.65 * k, 0.75 * k, -1.5 * k
	p.aLx, p.aLz, p.eLx = 0.65 * k, 0.3 * k, -0.2
	p.lRx, p.lLx = -0.1 * k, 0.25 * k
end

-- ===== winner poses (one per set) =====

-- A: jump with the gun to the sky (same moves as the character piece's victory).
local function winSky(p: Pose.Pose, t: number)
	local h = math.abs(math.sin(t * 4.5))
	p.hy = h * 0.6
	p.aRx, p.aRz, p.eRx = -3.0 + math.sin(t * 9) * 0.22, -0.3, -0.25
	p.aLx, p.aLz, p.eLx = -2.9, 0.35, -0.2
	p.lRx, p.lLx = -0.25, 0.25
	p.sRx, p.sLx = 0.5 * (1 - h), 0.7 * (1 - h)
	p.hdx, p.ty, p.tx = -0.25, math.sin(t * 2.2) * 0.35, -0.1
end

-- B: stomp and fist pump, gun resting on the shoulder.
local function winPump(p: Pose.Pose, t: number)
	local pump = math.abs(math.sin(t * 5))
	local stomp = math.max(0, math.sin(t * 5))
	p.aLx, p.aLz, p.eLx = -2.5 - 0.45 * pump, 0.3, -1.2 * (1 - pump) - 0.1
	p.aRx, p.aRz, p.eRx = -2.3, -0.75, -2.2
	p.lRx, p.sRx = -0.6 * stomp, 0.9 * stomp
	p.hy = -0.1 * (1 - stomp) + 0.12 * stomp
	p.lLz, p.tx, p.hdx, p.ty = 0.12, -0.15, -0.3, -0.15
end

-- C: arms crossed, slow nod.
local function winCool(p: Pose.Pose, t: number)
	p.aRx, p.aRz, p.eRx = -1.25, 0.75, -1.85
	p.aLx, p.aLz, p.eLx = -1.1, -0.75, -1.85
	p.hrx, p.tx = 0.06, -0.08
	p.hdx, p.hdy = -0.12 + math.sin(t * 3) * 0.1, 0.15
	p.lRz, p.lLz = -0.16, 0.16
	p.hy = math.sin(t * 2) * 0.02
end

-- ===== tables =====

Emotes.SETS = { "A", "B", "C" } :: { SetKey }
Emotes.SET_NAMES = { A = "Street", B = "Hype", C = "Chill" } :: { [string]: string }

local DRAW: { [string]: (Pose.Pose, number) -> () } = {}

Emotes.LIST = {} :: { Def }
local byId: { [string]: Def } = {}

local function add(
	id: string,
	name: string,
	set: SetKey,
	slot: number,
	draw: (Pose.Pose, number) -> ()
)
	local def: Def = { id = id, name = name, set = set, slot = slot }
	table.insert(Emotes.LIST, def)
	byId[id] = def
	DRAW[id] = draw
end

add("wave", "Wave", "A", 1, wave)
add("shuffle", "Shuffle", "A", 2, shuffle)
add("flex", "Flex", "A", 3, flex)
add("point", "You Next", "A", 4, point)
add("clap", "Clap", "B", 1, clap)
add("cheer", "Cheer", "B", 2, cheer)
add("robot", "Robot", "B", 3, robot)
add("salute", "Salute", "B", 4, salute)
add("shrug", "Shrug", "C", 1, shrug)
add("thumbs", "Thumbs Up", "C", 2, thumbs)
add("bob", "Head Bob", "C", 3, bob)
add("bow", "Bow", "C", 4, bow)

local WIN: { [SetKey]: (Pose.Pose, number) -> () } = { A = winSky, B = winPump, C = winCool }
Emotes.WIN_NAMES =
	{ A = "Gun to the Sky", B = "Fist Pump", C = "Arms Crossed" } :: { [string]: string }

function Emotes.get(id: string): Def?
	return byId[id]
end

function Emotes.isSet(key: any): boolean
	return key == "A" or key == "B" or key == "C"
end

-- The pose for an emote `t` seconds after it started. Nil for an unknown id.
function Emotes.compute(id: string, t: number): Pose.Pose?
	local draw = DRAW[id]
	if draw == nil then
		return nil
	end
	local p = Pose.zero()
	draw(p, math.max(0, t))
	return p
end

-- The winner pose of a set (an unknown set falls back to A).
function Emotes.win(set: string, t: number): Pose.Pose
	local draw = WIN[set :: SetKey] or winSky
	local p = Pose.zero()
	draw(p, math.max(0, t))
	return p
end

return Emotes
