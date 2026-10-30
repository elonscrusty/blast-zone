--!strict
-- Pure match rules: placement and ties, spawn picking, coin rewards, the once-only reward ledger,
-- spectate cycling and time text. No Roblox objects, so Lune can test all of it.

export type Point = { x: number, y: number, z: number }

export type RankEntry = {
	id: string,
	alive: boolean,
	left: boolean,
	eliminatedAt: number?, -- server time; a leaver counts as out at the moment they left
}

export type RankResult = {
	order: { string }, -- best first
	place: { [string]: number }, -- 1 = winner; ties share a number (1, 1, 3)
	topIds: { string }, -- everyone sharing first place
	outcome: string, -- "win" | "draw" | "abandoned"
	winnerId: string?, -- only for "win"
}

export type RewardConfig = {
	participation: number,
	perElimination: number,
	placementBonus: { number },
}

local MatchRules = {}

-- Placement (brief §11: one clear policy for simultaneous finals, leavers and disconnects).
--  * Alive at the end beats everyone. Otherwise the later you went out, the better.
--  * Eliminations within `tieWindow` seconds of each other tie, so two players who finish each other off
--    together share first place: a DRAW, never a coin flip.
--  * A leaver is out at the moment they left. If the best finisher is a leaver nobody beat, the match is
--    "abandoned": nobody is crowned, everyone still gets their placement.
function MatchRules.rank(entries: { RankEntry }, finishedAt: number, tieWindow: number): RankResult
	local sorted: { RankEntry } = table.clone(entries)
	local function lastTime(e: RankEntry): number
		if e.alive then
			return math.huge
		end
		return e.eliminatedAt or finishedAt
	end
	table.sort(sorted, function(a: RankEntry, b: RankEntry)
		local ta, tb = lastTime(a), lastTime(b)
		if ta ~= tb then
			return ta > tb
		end
		return a.id < b.id
	end)

	local order: { string } = {}
	local place: { [string]: number } = {}
	local groupStartTime: number? = nil
	local groupPlace = 0
	for i, e in sorted do
		local t = lastTime(e)
		-- Alive entries (math.huge) only tie with other alive entries; the dead tie within the window of the
		-- first of their group.
		local sameGroup = groupStartTime ~= nil
			and (
				(t == math.huge and groupStartTime == math.huge)
				or (
					t ~= math.huge
					and groupStartTime ~= math.huge
					and (groupStartTime :: number) - t <= tieWindow
				)
			)
		if not sameGroup then
			groupStartTime = t
			groupPlace = i
		end
		place[e.id] = groupPlace
		table.insert(order, e.id)
	end

	local topIds: { string } = {}
	local byId: { [string]: RankEntry } = {}
	for _, e in sorted do
		byId[e.id] = e
	end
	for _, id in order do
		if place[id] == 1 then
			table.insert(topIds, id)
		end
	end

	local outcome = "draw"
	local winnerId: string? = nil
	if #topIds == 1 then
		if byId[topIds[1]].left then
			outcome = "abandoned"
		else
			outcome = "win"
			winnerId = topIds[1]
		end
	end
	return { order = order, place = place, topIds = topIds, outcome = outcome, winnerId = winnerId }
end

local function distance(a: Point, b: Point): number
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end
MatchRules.distance = distance

export type SpawnPick = {
	points: { Point },
	minDistance: number, -- closest pair of chosen spawns (math.huge for one)
	usedFallback: boolean, -- true when the arena had too few spawn points and a ring was added
}

-- Pick `count` spawns that are as far apart as the arena allows (farthest-point picking). If the arena has
-- fewer points than players, the rest go on a ring around `center`. `rng(n)` returns a whole number 1..n.
function MatchRules.pickSpawns(
	available: { Point },
	count: number,
	center: Point,
	ringRadius: number,
	rng: (number) -> number
): SpawnPick
	local pool: { Point } = table.clone(available)
	local chosen: { Point } = {}
	if #pool > 0 and count > 0 then
		table.insert(chosen, table.remove(pool, rng(#pool)) :: Point)
	end
	while #chosen < count and #pool > 0 do
		local bestIndex, bestScore = 1, -1.0
		for i, candidate in pool do
			local nearest = math.huge
			for _, c in chosen do
				nearest = math.min(nearest, distance(candidate, c))
			end
			if nearest > bestScore then
				bestIndex, bestScore = i, nearest
			end
		end
		table.insert(chosen, table.remove(pool, bestIndex) :: Point)
	end

	local usedFallback = false
	if #chosen < count then
		usedFallback = true
		local missing = count - #chosen
		for i = 1, missing do
			local angle = (i - 1) / missing * math.pi * 2
			table.insert(chosen, {
				x = center.x + math.cos(angle) * ringRadius,
				y = center.y,
				z = center.z + math.sin(angle) * ringRadius,
			})
		end
	end

	local minDistance = math.huge
	for i = 1, #chosen do
		for j = i + 1, #chosen do
			minDistance = math.min(minDistance, distance(chosen[i], chosen[j]))
		end
	end
	return { points = chosen, minDistance = minDistance, usedFallback = usedFallback }
end

-- Credits for one finished match (Config.Rewards). Leavers and bots get none (the caller skips them).
function MatchRules.rewardFor(place: number, kills: number, cfg: RewardConfig): number
	return cfg.participation + (cfg.placementBonus[place] or 0) + kills * cfg.perElimination
end

-- Remembers which (match, player) rewards were already granted, so a repeated request pays nothing twice.
export type Ledger = {
	commit: (self: Ledger, matchId: number, id: string, amount: number) -> boolean,
	has: (self: Ledger, matchId: number, id: string) -> boolean,
	forgetBefore: (self: Ledger, matchId: number) -> (),
}

function MatchRules.newLedger(): Ledger
	local granted: { [number]: { [string]: number } } = {}
	local ledger = {} :: Ledger
	function ledger.commit(_self: Ledger, matchId: number, id: string, amount: number): boolean
		local forMatch = granted[matchId]
		if forMatch == nil then
			forMatch = {}
			granted[matchId] = forMatch
		end
		if forMatch[id] ~= nil then
			return false
		end
		forMatch[id] = amount
		return true
	end
	function ledger.has(_self: Ledger, matchId: number, id: string): boolean
		local forMatch = granted[matchId]
		return forMatch ~= nil and forMatch[id] ~= nil
	end
	function ledger.forgetBefore(_self: Ledger, matchId: number)
		for key in granted do
			if key < matchId then
				granted[key] = nil
			end
		end
	end
	return ledger
end

-- Next/previous living target to watch. Returns nil if nobody is alive. An unknown current id starts at the first.
function MatchRules.cycleTarget(
	aliveIds: { string },
	currentId: string?,
	direction: number
): string?
	local n = #aliveIds
	if n == 0 then
		return nil
	end
	local index = 0
	for i, id in aliveIds do
		if id == currentId then
			index = i
			break
		end
	end
	if index == 0 then
		return aliveIds[1]
	end
	local step = if direction < 0 then -1 else 1
	return aliveIds[(index - 1 + step) % n + 1]
end

-- 125.4 -> "2:05"
function MatchRules.formatTime(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", total // 60, total % 60)
end

return MatchRules
