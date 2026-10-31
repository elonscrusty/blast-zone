--!strict
-- Where the pieces of the results card sit inside its Column, as fractions of the Column.
-- Pure numbers, so Lune can turn them into pixels for any screen and check nothing overlaps or gets too small.
-- ResultsClientSystem builds the card from these same numbers. Change a number here and the test follows.

local ResultsLayout = {}

export type Span = { top: number, height: number }

-- The Column itself: fractions of the screen, then capped in pixels (UISizeConstraint).
ResultsLayout.column = {
	x = 0.5, -- centre
	y = 0.17, -- starts under the save-message strip
	width = 0.86,
	height = 0.55, -- ends at 0.72 of the screen: the "progress not loaded" note starts at 0.735
	maxWidth = 760,
	maxHeight = 420,
}

-- Top and height of each row, as a fraction of the Column height. Rows must not overlap.
ResultsLayout.rows = {
	title = { top = 0, height = 0.34 },
	sub = { top = 0.36, height = 0.11 },
	pills = { top = 0.49, height = 0.17 },
	extras = { top = 0.675, height = 0.08 },
	buttons = { top = 0.76, height = 0.21 },
} :: { [string]: Span }

-- The order the rows read, top to bottom.
ResultsLayout.order = { "title", "sub", "pills", "extras", "buttons" }

-- The note under the card starts here (fraction of the screen height).
ResultsLayout.noteTop = 0.735

-- The Column in pixels on a screen of this size.
function ResultsLayout.columnPixels(
	width: number,
	height: number
): { top: number, height: number, width: number }
	local c = ResultsLayout.column
	return {
		top = c.y * height,
		height = math.min(c.height * height, c.maxHeight),
		width = math.min(c.width * width, c.maxWidth),
	}
end

-- One row in screen pixels: top edge and height.
function ResultsLayout.rowPixels(name: string, width: number, height: number): Span
	local col = ResultsLayout.columnPixels(width, height)
	local row = ResultsLayout.rows[name]
	return { top = col.top + row.top * col.height, height = row.height * col.height }
end

return ResultsLayout
