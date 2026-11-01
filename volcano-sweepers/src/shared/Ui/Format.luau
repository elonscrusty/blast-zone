--!strict
-- Pure text helpers for the UI: short numbers (1.2K, 3.4M), countdowns, percents.
-- No Roblox types in here, so Lune can test every line.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- "12.0" -> "12", "1.50" -> "1.5"
local function trim(s: string): string
	if string.find(s, ".", 1, true) then
		s = (string.gsub(s, "0+$", ""))
		s = (string.gsub(s, "%.$", ""))
	end
	return s
end

-- Short number for coins and counts: 0..999 plain, then 1.2K, 12.3K, 123K, 1.2M ...
function Format.compact(n: number): string
	if type(n) ~= "number" or n ~= n then
		return "0"
	end
	if n == math.huge then
		return "MAX"
	elseif n == -math.huge then
		return "-MAX"
	end
	local sign = if n < 0 then "-" else ""
	local v = math.abs(n)
	if v < 1000 then
		return sign .. tostring(math.floor(v))
	end
	local idx = 1
	while v >= 1000 and idx < #SUFFIXES do
		v /= 1000
		idx += 1
	end
	local text = if v < 100 then string.format("%.1f", v) else string.format("%.0f", v)
	-- rounding can reach 1000 (999.96K -> "1000.0"): move up one suffix
	if tonumber(text) :: number >= 1000 and idx < #SUFFIXES then
		v /= 1000
		idx += 1
		text = string.format("%.1f", v)
	end
	return sign .. trim(text) .. SUFFIXES[idx]
end

-- Exact number with thousands commas: 1234567 -> "1,234,567".
function Format.commas(n: number): string
	if not finite(n) then
		return "0"
	end
	local sign = if n < 0 then "-" else ""
	local s = string.format("%.0f", math.floor(math.abs(n)))
	local spaced = (string.gsub(string.reverse(s), "(%d%d%d)", "%1,"))
	local out = string.reverse(spaced)
	out = (string.gsub(out, "^,", ""))
	return sign .. out
end

-- Clock text for time left: 7 -> "0:07", 65 -> "1:05", 3725 -> "1:02:05". Rounds UP so it
-- never shows 0:00 while time is still left.
function Format.countdown(seconds: number): string
	if not finite(seconds) or seconds <= 0 then
		return "0:00"
	end
	local s = math.ceil(seconds - 1e-9)
	local h = s // 3600
	local m = (s % 3600) // 60
	local sec = s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, sec)
	end
	return string.format("%d:%02d", m, sec)
end

-- Whole seconds left, rounded up, never below 0 (for the big banner number).
function Format.secondsLeft(seconds: number): number
	if not finite(seconds) or seconds <= 0 then
		return 0
	end
	return math.ceil(seconds - 1e-9)
end

-- 0.456 -> "45%". Never says 100% until it really is 1.
function Format.percent(fraction: number): string
	if not finite(fraction) then
		return "0%"
	end
	local f = math.clamp(fraction, 0, 1)
	return tostring(math.floor(f * 100 + 1e-6)) .. "%"
end

-- "12/30" style pair using compact numbers.
function Format.pair(a: number, b: number): string
	return Format.compact(a) .. "/" .. Format.compact(b)
end

-- Cuts text to at most `maxChars` CHARACTERS (never inside an emoji or "—"), ending on a word with
-- "…" when it had to cut. Bad UTF-8 falls back to a byte cut.
function Format.clip(text: string, maxChars: number): string
	if type(text) ~= "string" then
		return ""
	end
	local limit = math.max(1, math.floor(maxChars))
	local ok, n = pcall(utf8.len, text)
	if not ok or type(n) ~= "number" then
		return string.sub(text, 1, limit)
	end
	if n <= limit then
		return text
	end
	local stop = utf8.offset(text, limit) -- first byte of the last character we may keep
	local head = string.sub(text, 1, (stop or (limit + 1)) - 1)
	local word = string.match(head, "^(.*%S)%s+%S*$")
	if word ~= nil and #word >= #head * 0.6 then
		head = word
	end
	return head .. "…"
end

-- The HUD's small save note. `offline` = this visit's save is not loaded; `retrying` = the server is
-- still trying to load it in the background (it usually comes back on its own, so the words stay
-- calm). nil = no note at all.
function Format.offlineBadge(offline: any, retrying: any): { icon: string, text: string }?
	if offline ~= true then
		return nil
	end
	if retrying == true then
		return { icon = "⏳", text = "Loading your save..." }
	end
	return { icon = "👤", text = "Guest mode — not saving" }
end

return Format
