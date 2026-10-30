--!strict
-- The timing of a chest reveal (gap 19): the chest shakes, bursts open, the prizes come out, then "tap to
-- continue". Pure numbers and a tiny state machine so Lune can test it; the screen only draws what this says.
-- Three motion tries (A Lid Pop, B Drop Burst, C Card Flip); Config.Chest.revealStyle picks the one used. The
-- other two stay as skins. Claude Design can change how each one LOOKS; the timing here is the placeholder.

local ChestDefs = require("./ChestDefs")

local ChestReveal = {}

export type Style = {
	name: string,
	shake: number, -- seconds the closed chest shakes
	burst: number, -- seconds from the lid opening to the first prize
	gap: number, -- seconds between prizes (ignored when `together`)
	together: boolean, -- all prizes at once
	rarestLast: boolean, -- show the best prize last (for the drum-roll)
}

ChestReveal.styles = {
	A = {
		name = "Lid Pop",
		shake = 1.0,
		burst = 0.3,
		gap = 0.45,
		together = false,
		rarestLast = true,
	},
	B = {
		name = "Drop Burst",
		shake = 0.35,
		burst = 0.15,
		gap = 0,
		together = true,
		rarestLast = false,
	},
	C = {
		name = "Card Flip",
		shake = 0.6,
		burst = 0.2,
		gap = 0.6,
		together = false,
		rarestLast = true,
	},
} :: { [string]: Style }

ChestReveal.TAP_LOCK = 0.35 -- seconds after the last prize before "continue" listens (no accidental double tap)

export type Prize = { rarity: string }

export type Model = {
	style: Style,
	order: { number }, -- prize indexes in the order they are shown
	times: { number }, -- seconds (from start) at which order[i] appears
	elapsed: number,
	doneAt: number,
	skipped: boolean,
}

-- The order prizes are shown in. Rolled order, or best last (a stable sort: ties keep their rolled order).
function ChestReveal.orderOf(style: Style, prizes: { Prize }): { number }
	local order: { number } = {}
	for i = 1, #prizes do
		order[i] = i
	end
	if style.rarestLast then
		table.sort(order, function(a, b)
			local ra, rb =
				ChestDefs.rank(prizes[a].rarity :: any), ChestDefs.rank(prizes[b].rarity :: any)
			if ra ~= rb then
				return ra < rb
			end
			return a < b
		end)
	end
	return order
end

function ChestReveal.new(styleId: string, prizes: { Prize }): Model
	local style = ChestReveal.styles[styleId] or ChestReveal.styles.A
	local order = ChestReveal.orderOf(style, prizes)
	local times: { number } = {}
	local first = style.shake + style.burst
	for i = 1, #order do
		times[i] = if style.together then first else first + style.gap * (i - 1)
	end
	return {
		style = style,
		order = order,
		times = times,
		elapsed = 0,
		doneAt = if #order == 0 then first else times[#order],
		skipped = false,
	}
end

function ChestReveal.tick(m: Model, dt: number)
	if dt > 0 and dt == dt then
		m.elapsed += dt
	end
end

-- "shaking" -> "showing" -> "done". A skip goes straight to "done".
function ChestReveal.phase(m: Model): string
	if m.skipped or m.elapsed >= m.doneAt then
		return "done"
	end
	if m.elapsed < m.style.shake then
		return "shaking"
	end
	return "showing"
end

-- How many prizes are out (in show order).
function ChestReveal.shown(m: Model): number
	if m.skipped then
		return #m.order
	end
	local n = 0
	for i = 1, #m.times do
		if m.elapsed >= m.times[i] then
			n = i
		end
	end
	return n
end

-- A tap while it plays shows everything now. A tap once everything is out (after the short lock) means continue.
function ChestReveal.tap(m: Model): string?
	if ChestReveal.phase(m) ~= "done" then
		m.skipped = true
		m.elapsed = math.max(m.elapsed, m.doneAt)
		return "skipped"
	end
	if m.elapsed >= m.doneAt + ChestReveal.TAP_LOCK then
		return "continue"
	end
	return nil
end

return ChestReveal
