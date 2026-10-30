--!strict
-- What the top bar shows, as plain data (piece G17). No Roblox, so Lune tests it. The drawing (WalletBarSystem)
-- is a placeholder (client/Wallet/WalletBarSystem); Claude Design restyles it and keeps this.

local MatchPhase = require("../MatchPhase")
local Types = require("../Types")

export type Row = { id: string, label: string, text: string, amount: number }
export type Rise = { id: string, delta: number }

local WalletBarModel = {}

-- Short text for a counter. Rounds DOWN so the bar never claims more than the player has:
-- 999 -> "999", 1234 -> "1.2K", 12345 -> "12K", 1500000 -> "1.5M".
function WalletBarModel.compact(n: number): string
	local v = math.max(0, math.floor(n))
	if v < 1000 then
		return tostring(v)
	end
	local function scaled(div: number, suffix: string): string
		local tenths = math.floor(v / (div / 10))
		if tenths < 100 then
			return `{tenths // 10}.{tenths % 10}{suffix}`
		end
		return `{tenths // 10}{suffix}`
	end
	if v < 1000000 then
		return scaled(1000, "K")
	end
	return scaled(1000000, "M")
end

function WalletBarModel.rows(state: Types.WalletState?): { Row }
	local rows: { Row } = {}
	if state == nil then
		return rows
	end
	for _, item in state.items do
		table.insert(rows, {
			id = item.id,
			label = item.short,
			text = WalletBarModel.compact(item.amount),
			amount = item.amount,
		})
	end
	return rows
end

-- Counters that went UP between two states (for a little pop). A counter that first appears counts as a rise
-- only when `old` exists, so the first state after joining does not pop.
function WalletBarModel.rises(old: Types.WalletState?, new: Types.WalletState): { Rise }
	local rises: { Rise } = {}
	if old == nil then
		return rises
	end
	local before: { [string]: number } = {}
	for _, item in old.items do
		before[item.id] = item.amount
	end
	for _, item in new.items do
		local was = before[item.id] or 0
		if item.amount > was then
			table.insert(rises, { id = item.id, delta = item.amount - was })
		end
	end
	return rises
end

-- Saved data not loaded yet, or not being saved: a small note under the bar ("" = nothing to say).
function WalletBarModel.note(state: Types.WalletState?): string
	if state == nil or state.status == "ready" then
		return ""
	end
	if state.status == "temporary" then
		return "Test mode: not saved"
	end
	if state.status == "loading" then
		return "Loading..."
	end
	return "Not saved right now"
end

-- The bar belongs to the calm times: lobby, results, between matches. Not while fighting.
function WalletBarModel.visible(phase: string?): boolean
	return phase ~= MatchPhase.Spawning
		and phase ~= MatchPhase.Active
		and phase ~= MatchPhase.FinalPressure
end

return WalletBarModel
