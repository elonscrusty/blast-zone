--!strict
-- Receipts make a grant happen once. A receipt key is written in the SAME save as the reward, so
-- a repeat (double tap, retried request, match reported twice) finds the key and pays nothing.
-- Only the newest `keep` receipts are remembered. Pure Luau.

local Receipts = {}

Receipts.MAX_KEY = 100

function Receipts.isValidKey(key: any): boolean
	return type(key) == "string"
		and #key >= 1
		and #key <= Receipts.MAX_KEY
		and string.match(key, "^[%w_:%.%-]+$") ~= nil
end

-- Match matchId restarts at 1 on every server, so the server's JobId must be part of the key.
function Receipts.matchKey(jobId: string, matchId: number): string
	local job = if jobId == "" then "studio" else jobId
	return "m:" .. job .. ":" .. tostring(math.floor(matchId))
end

function Receipts.has(data: { [string]: any }, key: string): boolean
	local r = data.receipts
	return type(r) == "table" and r[key] ~= nil
end

function Receipts.add(data: { [string]: any }, key: string, now: number, keep: number)
	if type(data.receipts) ~= "table" then
		data.receipts = {}
	end
	local r = data.receipts :: { [string]: number }
	r[key] = now
	local keys: { string } = {}
	for k in r do
		table.insert(keys, k)
	end
	if #keys <= keep then
		return
	end
	-- Oldest first; ties by name so the result never depends on table order.
	table.sort(keys, function(a: string, b: string): boolean
		if r[a] ~= r[b] then
			return r[a] < r[b]
		end
		return a < b
	end)
	for i = 1, #keys - keep do
		r[keys[i]] = nil
	end
end

return Receipts
