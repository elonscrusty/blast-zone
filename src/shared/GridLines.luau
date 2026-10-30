--!strict
-- Where the lines of a floor grid go. Pure maths so Lune can check the count: the lobby plaza draws
-- one glowing line at each offset (synthwave floor from video 3).

local GridLines = {}

-- Offsets from the middle of a span `extent` studs long, one every `spacing` studs, never on the
-- edge. Includes 0 (a line through the middle) and is symmetrical.
function GridLines.offsets(extent: number, spacing: number): { number }
	local out: { number } = {}
	if extent <= 0 or spacing <= 0 then
		return out
	end
	local half = extent / 2
	local steps = math.floor((half - 1e-6) / spacing)
	for i = -steps, steps do
		table.insert(out, i * spacing)
	end
	return out
end

return GridLines
