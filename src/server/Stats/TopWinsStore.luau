--!strict
-- The global top-wins list in an OrderedDataStore (piece 24). Server only.
-- Saved wins come from the player's profile (piece 17); this list only mirrors them for the board.
-- Every call goes through SaveRetry (tries again, waits longer each time). A write never lowers a value.
--
--   TopWinsStore.queue(userId, wins)   -- remember the newest saved win count; written on the next flush
--   TopWinsStore.flush()               -- yields: writes up to Config.Stats.board.writesPerFlush entries
--   TopWinsStore.readTop() -> (ok, rows)  -- yields: the best players, names filled in

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local SaveRetry = require(Shared.SaveRetry)
local BoardRules = require(Shared.Stats.BoardRules)

local TopWinsStore = {}

local cfg = Config.Stats.board
local store: OrderedDataStore? = nil
local pending = BoardRules.newQueue()
local names: { [number]: string } = {}
local lastError: string? = nil
local accessOff = false -- a 403 (API access off, e.g. Studio): stop calling until the server restarts

local function noteError(err: string?)
	lastError = err
	if err and string.find(err, "403", 1, true) then
		accessOff = true
	end
end

local function say(text: string)
	warn("[TopWins] " .. text)
end

local function getStore(): OrderedDataStore?
	if store == nil then
		local ok, result = pcall(function()
			return DataStoreService:GetOrderedDataStore(cfg.storeName)
		end)
		if ok then
			store = result
		else
			lastError = tostring(result)
			say(`no store: {lastError}`)
		end
	end
	return store
end

-- Text from the last failed read or write (for the board status line), or nil.
function TopWinsStore.lastError(): string?
	return lastError
end

function TopWinsStore.queue(userId: number, wins: number)
	pending:put(userId, wins)
end

function TopWinsStore.pendingCount(): number
	return pending:size()
end

-- True once a call came back 403: the store is never asked again on this server.
function TopWinsStore.isOff(): boolean
	return accessOff
end

function TopWinsStore.flush()
	local s = getStore()
	if s == nil or accessOff or pending:size() == 0 then
		return
	end
	for _, item in pending:take(cfg.writesPerFlush) do
		local ok, _, err = SaveRetry.run(function()
			return s:UpdateAsync(BoardRules.keyFor(item.userId), function(old: any): any
				local value = BoardRules.merge(old, item.wins)
				if value == old then
					return nil -- nothing to change: cancel the write
				end
				return value
			end)
		end, task.wait)
		if not ok then
			noteError(err)
			say(`write failed for {item.userId}: {err or "?"}`)
			if accessOff then
				return -- API access is off (Studio): no more writes on this server
			end
			pending:put(item.userId, item.wins) -- try again next time
		end
	end
end

local function nameOf(userId: number): string?
	local known = names[userId]
	if known then
		return known
	end
	local here = Players:GetPlayerByUserId(userId)
	if here then
		names[userId] = here.Name -- user names everywhere, so a row looks the same online and offline
		return here.Name
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(result) == "string" then
		names[userId] = result
		return result
	end
	return nil
end

function TopWinsStore.readTop(): (boolean, { BoardRules.Row })
	local s = getStore()
	if s == nil or accessOff then
		return false, {}
	end
	local ok, page, err = SaveRetry.run(function()
		local pages = s:GetSortedAsync(false, cfg.rows)
		return pages:GetCurrentPage()
	end, task.wait)
	if not ok then
		noteError(err)
		say(`read failed: {err or "?"}`)
		return false, {}
	end
	lastError = nil
	return true, BoardRules.rows(page, nameOf, cfg.rows)
end

return TopWinsStore
