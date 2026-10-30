--!strict
-- Prints every held-gun part list as JSON for the preview page:  lune run tools/gun_json
local serde = require("@lune/serde")
local WeaponModels = require("../src/client/Combat/WeaponModels")
print(serde.encode("json", WeaponModels.models, false))
