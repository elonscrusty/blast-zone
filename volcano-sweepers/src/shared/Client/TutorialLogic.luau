--!strict
-- Pure stage machine for the first-time hints (client/Core/Tutorial draws them). No Roblox types.
--
-- A 7-year-old must get through it without reading much, so every stage says ONE short thing,
-- shows a glowing line on the ground when they need to walk somewhere, and points a finger at the
-- one button they need. The stages advance on what really happened (ash in the backpack, a sale, a
-- purchase), never on a button press.
--
--   find   no ash in reach            "Walk to the grey ash!"   + line to the nearest ash
--   sweep  ash in reach                "Hold SWEEP!"              + finger on SWEEP (touch, Auto off)
--   fill   ash went in the backpack    "Fill your backpack!"     (+ finger on AUTO once, touch only)
--   sell   backpack half full          "Walk to the Trade Hut!"  + line to the hut
--                                      "Tap SELL!" / "Press F to SELL!" at the hut
--   buy    first sale done             "Tap 🛠 to get stronger!" + finger on the Upgrades button
--   done
--
--   TutorialLogic.new(now) -> State
--   TutorialLogic.step(state, facts) -> Hint      advances state.stage, returns what to show
--   TutorialLogic.onSold(state, now)               the server confirmed a sale
--   TutorialLogic.onBought(state, now)             something was bought (upgrade, tool, zone)

export type Stage = "find" | "sweep" | "fill" | "sell" | "buy" | "cheer" | "done"

export type State = {
	stage: Stage,
	stageAt: number, -- when the current stage began
	startedAt: number,
	noAshSince: number?, -- in "sweep"/"find": when ash was last NOT in reach
	autoTipShown: boolean,
	sold: boolean,
}

export type Facts = {
	now: number,
	carried: number,
	fraction: number, -- backpack 0..1
	ashInReach: boolean,
	nearHut: boolean,
	canBuy: boolean, -- some upgrade is affordable right now
	panelOpen: boolean,
	autoOn: boolean,
	touch: boolean, -- phone / tablet without a keyboard
}

export type Beam = "ash" | "hut"
export type Point = "sweep" | "auto" | "sell" | "upgrades"

export type Hint = {
	text: string?,
	beam: Beam?,
	point: Point?,
}

local TutorialLogic = {}

TutorialLogic.SHOW_AFTER = 1 -- seconds before the first hint
TutorialLogic.NO_ASH_GRACE = 1.5 -- seconds without ash in reach before "walk to the ash"
TutorialLogic.SELL_FRACTION = 0.5
TutorialLogic.FILL_TEXT_SECONDS = 4
TutorialLogic.AUTO_TIP_AFTER = 5 -- seconds into "fill" before the AUTO tip (touch, Auto off)
TutorialLogic.AUTO_TIP_SECONDS = 6
TutorialLogic.BUY_GIVE_UP = 180 -- stop nagging about the shop after this long
TutorialLogic.CHEER_SECONDS = 2.5

local NONE: Hint = table.freeze({})

function TutorialLogic.new(now: number): State
	return {
		stage = "find",
		stageAt = now,
		startedAt = now,
		noAshSince = nil,
		autoTipShown = false,
		sold = false,
	}
end

local function go(state: State, stage: Stage, now: number)
	if state.stage ~= stage then
		state.stage = stage
		state.stageAt = now
	end
end

function TutorialLogic.onSold(state: State, now: number)
	state.sold = true
	if state.stage ~= "done" and state.stage ~= "cheer" then
		go(state, "buy", now)
	end
end

function TutorialLogic.onBought(state: State, now: number)
	if state.stage == "buy" then
		go(state, "cheer", now)
	elseif state.sold and state.stage ~= "cheer" then
		go(state, "done", now)
	end
end

local function sweepText(f: Facts): string
	if f.autoOn then
		return "Walk into the ash!"
	end
	if f.touch then
		return "Hold SWEEP!"
	end
	return "Hold E or click to SWEEP!"
end

function TutorialLogic.step(state: State, f: Facts): Hint
	local now = f.now
	local stage = state.stage

	-- ash already in the pack moves on from the first two stages whatever else happens
	if (stage == "find" or stage == "sweep") and f.carried > 0 then
		go(state, "fill", now)
		stage = state.stage
	end

	if stage == "find" or stage == "sweep" then
		if f.ashInReach then
			state.noAshSince = nil
			go(state, "sweep", now)
		else
			if state.noAshSince == nil then
				state.noAshSince = now
			end
			if now - (state.noAshSince :: number) >= TutorialLogic.NO_ASH_GRACE then
				go(state, "find", now)
			end
		end
		if now - state.startedAt < TutorialLogic.SHOW_AFTER then
			return NONE
		end
		if state.stage == "find" then
			return { text = "Walk to the grey ash!", beam = "ash" }
		end
		return {
			text = sweepText(f),
			point = if f.touch and not f.autoOn then "sweep" else nil,
		}
	elseif stage == "fill" then
		if f.fraction >= TutorialLogic.SELL_FRACTION then
			go(state, "sell", now)
			return TutorialLogic.step(state, f)
		end
		local t = now - state.stageAt
		if
			f.touch
			and not f.autoOn
			and not state.autoTipShown
			and t >= TutorialLogic.AUTO_TIP_AFTER
		then
			if t < TutorialLogic.AUTO_TIP_AFTER + TutorialLogic.AUTO_TIP_SECONDS then
				return { text = "Tap AUTO to sweep by walking!", point = "auto" }
			end
			state.autoTipShown = true
		end
		if t < TutorialLogic.FILL_TEXT_SECONDS then
			return { text = "Fill your backpack!" }
		end
		return NONE
	elseif stage == "sell" then
		if f.nearHut then
			return {
				text = if f.touch then "Tap SELL!" else "Press F to SELL!",
				point = if f.touch then "sell" else nil,
			}
		end
		return { text = "Walk to the Trade Hut!", beam = "hut" }
	elseif stage == "buy" then
		if now - state.stageAt >= TutorialLogic.BUY_GIVE_UP then
			go(state, "done", now)
			return NONE
		end
		if not f.canBuy then
			return NONE -- keep sweeping; the hint comes back once something is affordable
		end
		if f.panelOpen then
			return { text = nil } -- the shop is open: let them look (no finger over the cards)
		end
		return { text = "Tap 🛠 to get stronger!", point = "upgrades" }
	elseif stage == "cheer" then
		if now - state.stageAt >= TutorialLogic.CHEER_SECONDS then
			go(state, "done", now)
			return NONE
		end
		return { text = "You got stronger!" }
	end
	return NONE
end

return TutorialLogic
