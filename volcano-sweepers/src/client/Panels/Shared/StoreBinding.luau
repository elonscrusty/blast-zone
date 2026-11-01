--!strict
-- Keeps a panel in step with the client store. Several keys can change in the same moment (a
-- purchase changes coins AND upgrades), so the callback is coalesced into ONE call per frame.
-- The store may not be there yet when a panel opens: this keeps retrying quietly and then calls
-- back once. Everything it connects is released by destroy().
--
--   local binding = StoreBinding.new({ "coins", "upgrades" }, function() repaint() end)
--   binding.destroy()

local Bridge = require(script.Parent.Parent.Parent.Ui.Bridge)

local StoreBinding = {}

export type Binding = {
	destroy: () -> (),
	poke: () -> (), -- ask for a repaint on the next frame
}

local RETRY_SECONDS = 0.5

function StoreBinding.new(keys: { string }, onChange: () -> ()): Binding
	local disconnects: { () -> () } = {}
	local pending: { string } = table.clone(keys)
	local destroyed = false
	local queued = false

	local function poke()
		if queued or destroyed then
			return
		end
		queued = true
		task.defer(function()
			queued = false
			if destroyed then
				return
			end
			local ok, err = pcall(onChange)
			if not ok then
				warn(`[Panel] repaint failed: {err}`)
			end
		end)
	end

	-- Subscribes every key that is still missing; true when none are left.
	local function attach(): boolean
		local stillMissing: { string } = {}
		for _, key in pending do
			local disconnect = Bridge.subscribe(key, function()
				poke()
			end)
			if disconnect ~= nil then
				table.insert(disconnects, disconnect)
			else
				table.insert(stillMissing, key)
			end
		end
		pending = stillMissing
		return #pending == 0
	end

	if not attach() then
		task.spawn(function()
			while not destroyed and #pending > 0 do
				task.wait(RETRY_SECONDS)
				if destroyed then
					return
				end
				if attach() then
					break
				end
			end
			poke()
		end)
	end
	poke() -- the first paint never waits for a store change

	return {
		poke = poke,
		destroy = function()
			if destroyed then
				return
			end
			destroyed = true
			for _, disconnect in disconnects do
				pcall(disconnect)
			end
			table.clear(disconnects)
		end,
	}
end

return StoreBinding
