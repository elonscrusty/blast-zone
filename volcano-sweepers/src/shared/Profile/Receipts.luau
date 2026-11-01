--!strict
-- Receipts make a grant happen once. A receipt key is saved in the SAME write as the reward, so a
-- repeat (double tap, retried request, two servers racing for the same day) finds the key and pays
-- nothing. Only the newest `keep` receipts are remembered. Pure Luau.
--
-- Receipts live next to the profile in the saved record, not inside Types.Profile, so the profile
-- shape stays exactly what the rest of the game sees.

local Receipts = {}

Receipts.MAX_KEY = 100

export type Book = { [string]: number } -- key -> time it was paid (os.time)

function Receipts.isValidKey(key: any): boolean
	return type(key) == "string"
		and #key >= 1
		and #key <= Receipts.MAX_KEY
		and string.match(key, "^[%w_:%.%-]+$") ~= nil
end

-- Key for the daily reward of one UTC day (days since 1970): pays once per day.
function Receipts.dailyKey(day: number): string
	return "daily:" .. tostring(math.floor(day))
end

function Receipts.newBook(): Book
	return {}
end

-- A clean book from whatever was stored: only valid keys with finite numbers survive.
function Receipts.clean(raw: any, keep: number): Book
	local book: Book = {}
	if type(raw) ~= "table" then
		return book
	end
	for k, v in raw :: { [any]: any } do
		if Receipts.isValidKey(k) and type(v) == "number" and v == v and math.abs(v) < 1e15 then
			book[k :: string] = v
		end
	end
	Receipts.trim(book, keep)
	return book
end

function Receipts.has(book: Book, key: string): boolean
	return book[key] ~= nil
end

-- Forget the oldest receipts until `keep` remain. Oldest first; ties by name so the result never
-- depends on table order.
function Receipts.trim(book: Book, keep: number)
	local keys: { string } = {}
	for k in book do
		table.insert(keys, k)
	end
	if #keys <= keep then
		return
	end
	table.sort(keys, function(a: string, b: string): boolean
		if book[a] ~= book[b] then
			return book[a] < book[b]
		end
		return a < b
	end)
	for i = 1, #keys - keep do
		book[keys[i]] = nil
	end
end

function Receipts.add(book: Book, key: string, now: number, keep: number)
	book[key] = now
	Receipts.trim(book, keep)
end

return Receipts
