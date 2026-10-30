--!strict
-- Starts the ranked listener (gap 23). No screen yet on purpose: Claude Design draws the rank card and the
-- ranked switch from RankedClient (use UiLayers for every DisplayOrder, and a LobbyMenu slot for the switch).

local RankedClient = require(script.Parent.RankedClient)

local RankedClientSystem = {}
RankedClientSystem.order = 225

function RankedClientSystem.start()
	RankedClient.ensureStarted()
end

return RankedClientSystem
