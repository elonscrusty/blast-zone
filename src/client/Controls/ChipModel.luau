--!strict
-- Which upgrade pick chips are showing, from the same messages the cards get. Pure, so Lune can
-- check it. The chips only send a tap as the action "upgradeN"; the cards and the server decide
-- whether it counts.

export type State = { offerId: string?, count: number }

local ChipModel = {}

local MAX_CHIPS = 3

function ChipModel.new(): State
	return { offerId = nil, count = 0 }
end

-- An `UpgradeOffer` message. nil or anything malformed closes the chips.
function ChipModel.applyOffer(s: State, payload: any): number
	s.offerId = nil
	s.count = 0
	if type(payload) ~= "table" then
		return 0
	end
	local offer = payload :: { [string]: any }
	local options = offer.options
	if type(offer.offerId) ~= "string" or type(options) ~= "table" then
		return 0
	end
	s.offerId = offer.offerId
	s.count = math.min(#(options :: { any }), MAX_CHIPS)
	return s.count
end

-- Picked, match over, eliminated: nothing to pick any more.
function ChipModel.clear(s: State)
	s.offerId = nil
	s.count = 0
end

-- Is the match in a phase where cards can show?
function ChipModel.fighting(phase: any): boolean
	return phase == "Active" or phase == "FinalPressure"
end

function ChipModel.visible(s: State, index: number): boolean
	return index >= 1 and index <= s.count
end

return ChipModel
