--!strict
-- Tries a DataStore call again after a failure, waiting longer each time. Pure (the waiting is
-- passed in) so Lune can test it. A "no access" error (API access off in Studio, unpublished
-- place) can never fix itself: trying again only makes the player wait, so it stops at once.
-- Only those exact shapes count: an error that merely CONTAINS the digits 403 somewhere (a request
-- id, a key name) is an ordinary failure and is tried again.

local SaveRetry = {}

SaveRetry.TRIES = 4

-- true when the error text means "this DataStore can never be reached from here".
function SaveRetry.isPermanent(text: string?): boolean
	if type(text) ~= "string" then
		return false
	end
	local lower = string.lower(text)
	if string.find(lower, "^%s*403") ~= nil then
		return true -- "403: ..." (Roblox) and "403 ..." (our own Profiles glue)
	end
	if string.find(lower, "http 403", 1, true) ~= nil then
		return true
	end
	if string.find(lower, "studio access", 1, true) ~= nil then
		return true
	end
	if string.find(lower, "studioaccesstoapisnotallowed", 1, true) ~= nil then
		return true
	end
	return false
end

-- Returns ok, result and (on failure) the last error text. `wait` is task.wait; `onFail` hears each failure (try number, error).
function SaveRetry.run(
	fn: () -> any,
	wait: (number) -> any,
	onFail: ((number, string) -> ())?,
	tries: number?
): (boolean, any, string?)
	local n = tries or SaveRetry.TRIES
	local last: string? = nil
	for i = 1, n do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		last = tostring(result)
		if onFail then
			onFail(i, last)
		end
		if SaveRetry.isPermanent(last) then
			break
		end
		if i < n then
			wait(2 ^ i)
		end
	end
	return false, nil, last
end

return SaveRetry
