--!strict
-- The Sweeper Cart: a small ride-on sweeper (builder, not wired in yet: the cart look is not picked).
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

-- Only ever touches the AshHeap part (its Size, and its place on the cart). On a welded cart the
-- place is the heap's own PartWeld.C0, so no other part and not the whole cart can move. On an
-- anchored cart (build with weld = false) the heap is a free anchored part, so its CFrame is set.
function SweeperCart.setFill(model: Model, fill: number)
	local heap = model:FindFirstChild("AshHeap")
	local root = model.PrimaryPart
	if heap == nil or not heap:IsA("BasePart") or root == nil then
		return
	end
	local size, y = CartSpecs.heap(fill)
	local weld = heap:FindFirstChild("PartWeld")
	-- the heap's position on the cart (x and z never change; only the height does)
	local at = root.CFrame:ToObjectSpace(heap.CFrame).Position
	if weld ~= nil and weld:IsA("Weld") then
		at = weld.C0.Position
	end
	local place = CFrame.new(at.X, y, at.Z) * CFrame.Angles(0, 0, math.pi / 2)
	heap.Size = Vector3.new(size[2], size[1], size[3]) -- a Roblox cylinder's axis is X
	if weld ~= nil and weld:IsA("Weld") then
		weld.C0 = place
	else
		heap.CFrame = root.CFrame * place
	end
end

return SweeperCart
