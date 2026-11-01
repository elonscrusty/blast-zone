--!strict
-- The client's copy of the player's state (the View from Shared/Types). The server sends partial
-- updates on the `State` remote; they are merged by top-level key (see Shared/Client/StoreLogic).
-- The client never decides anything: it only displays what is here.
--
--   Store.get(key)                       -> value or nil
--   Store.view()                         -> the live table (do not write to it)
--   Store.subscribe(key, fn(value, old)) -> disconnect function. Also calls fn once now if the value
--                                           already exists (old is nil then).
--   Store.subscribeAll(fn(key, value, old)) -> disconnect function
--   Store.ready                          -> true after the first State payload
--   Store.onReady(fn)                    -> runs fn once the store is ready (now, if it already is)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StoreLogic = require(Shared.Client.StoreLogic)
local Net = require(script.Parent.Net)

local inner = StoreLogic.new()

local Store = {}
Store.ready = false

function Store.get(key: string): any
	return inner.view[key]
end

function Store.view(): { [string]: any }
	return inner.view
end

function Store.subscribe(key: string, fn: (value: any, old: any) -> ()): () -> ()
	return inner.subscribe(key, fn)
end

function Store.subscribeAll(fn: (key: string, value: any, old: any) -> ()): () -> ()
	return inner.subscribeAll(fn)
end

function Store.onReady(fn: () -> ())
	inner.onReady(fn)
end

inner.onReady(function()
	Store.ready = true
end)

Net.on("State", function(patch: any)
	if type(patch) == "table" then
		inner.apply(patch)
	end
end)

return Store
