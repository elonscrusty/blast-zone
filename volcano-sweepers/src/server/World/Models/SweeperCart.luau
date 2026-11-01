--!strict
-- The Sweeper Cart: a small ride-on sweeper (builder, not wired in: the main thread connects it).
--   SweeperCart.build("A")        -> Model. Origin = middle of the ground under it, -Z is forward.
--   SweeperCart.setFill(model, f) -> grows or shrinks the ash heap in the back bin (f = 0..1)
-- Parts named "Spin*" are the front brush (turn it), "Wheel*" roll, "SeatSpot" is a see-through marker
-- where the rider sits (SweeperCart.seatOffset). Looks: A Toy | B Steel | C Candy.

local CartSpecs = require(script.Parent.CartSpecs)
local ModelBuilder = require(script.Parent.ModelBuilder)

local SweeperCart = {}

SweeperCart.looks = { "A", "B", "C" } :: { string }
SweeperCart.seatOffset =
	Vector3.new(CartSpecs.seatSpot[1], CartSpecs.seatSpot[2], CartSpecs.seatSpot[3])

function SweeperCart.build(look: string?, opts: ModelBuilder.Opts?): Model
	local spec = CartSpecs.build(look, opts ~= nil and opts.lite == true)
	local model = ModelBuilder.build("SweeperCart" .. spec.look, spec.parts, opts)
	SweeperCart.setFill(model, 0)
	return model
end

function SweeperCart.setFill(model: Model, fill: number)
	local heap = model:FindFirstChild("AshHeap")
	local root = model.PrimaryPart
	if heap == nil or not heap:IsA("BasePart") or root == nil then
		return
	end
	local size, y = CartSpecs.heap(fill)
	local at = root.CFrame:ToObjectSpace(heap.CFrame).Position
	heap.Size = Vector3.new(size[2], size[1], size[3]) -- a Roblox cylinder's axis is X
	heap.CFrame = root.CFrame * CFrame.new(at.X, y, at.Z) * CFrame.Angles(0, 0, math.pi / 2)
end

return SweeperCart
