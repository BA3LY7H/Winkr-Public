local unlocker,
---@class mint
mint,
addon = ...

------------------------------
--- Variable Initialization
------------------------------
local RaidEvents   	= mint.RaidEvents
local UnitManager   = mint.UnitManager
local Events        = mint.EventManager.New()
local FriendManager = mint.FriendManager
local Constants     = mint.Constants

local target        = UnitManager:Get("target")
local player        = UnitManager:Get("player")
local none          = UnitManager:Get("none")

--! Addon Locals !--
local settings          = addon.utility["Visions"].settings
local data 			    = addon.utility["Visions"].data
local actor = mint.Actor.New({
    condition = function()
        local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
        return instanceID == 2827 or instanceID == 2828
    end
})

-- Visions data
data = {
    bad_potion_found = false,
    bad_spot = {
        [2827] = mint.Vector3:New(-8673, 823, 97),
        [2828] = mint.Vector3:New(1550, -4321, 25),
    }
}

-- reset the good/bad vial on PLAYER_MAP_CHANGED
Events:RegisterWoWEvent("PLAYER_MAP_CHANGED", function()
    data.bad_potion_found = false
    data.bad_potion = nil
    data.good_potion = nil
end)


-- GameObjects of Note
local vision_ids = {
    ------------------------------
    --- Shared
    ------------------------------
    [341338] = "Blue Potion",
    [341341] = "Red Potion",
    [341339] = "Green Potion",
    [341337] = "Black Potion",
    [341340] = "Purple Potion",
    [343698] = "Void-Touched Skull",

    -- Treasure
    [500098] = "Black Empire Cache",
    [500099] = "Black Empire Cache",
    [500100] = "Black Empire Cache",
    [500101] = "Black Empire Cache",
    [500103] = "Black Empire Cache",
    [500104] = "Black Empire Cache",

    ------------------------------
    --- Stormwind
    ------------------------------
    -- Treasures & Misc Loot
    [326755] = "Mailbox (Searchable)",
    [326924] = "Mailbox (Searchable)",
    [327053] = "Mailbox (Searchable)",
    [326974] = "Mailbox (Searchable)",
    [523452] = "Trash (Searchable)",
    [523456] = "Trash (Searchable)",
    [523457] = "Trash (Searchable)",
    [527691] = "Summon Hogger",         -- Wanted poster to summon hogger
    [499038] = "Cathedral District",    -- Portal to Cathedral District
    [529673] = "Auction House Crate",   -- For bike parts
    -- Horseshoe Mount
    [517344] = "Cursed Horseshoe",
    [517348] = "Cursed Horseshoe",
    [517349] = "Cursed Horseshoe",
    [517350] = "Cursed Horseshoe",
    -- Objectives
    -- Dwarven District
    [334122] = "Bomb Location", -- Place Bombs
    -- Trade District
    [326606] = "Torment Cell", -- Free the captives
    [336708] = "Torment Cell", -- Free the captives
    -- Mage Quarter

    -- Old Town

    ------------------------------
    --- Orgrimmar
    ------------------------------

}

local potion_map = {
    [341341] = 341338, -- Red -> Blue
    [341337] = 341339, -- Black -> Green
    [341338] = 341340, -- Blue -> Purple
    [341339] = 341341, -- Green -> Red
    [341340] = 341337, -- Purple -> Black
}

local vision_objects = {}

actor:Sync(function()
    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    local objects = mint.Objects(8)
    vision_objects = {}

    for _, object in ipairs(objects) do
        local id = mint.ObjectID(object)

        if vision_ids[id] then
            table.insert(vision_objects, object)
        end
    end

    if not data.bad_potion_found then
        for _, object in ipairs(vision_objects) do
            local x, y, z = mint.ObjectPosition(object)
            local pos = mint.Vector3:New(x, y, z)

            if pos:Distance(data.bad_spot[instanceID]) < 5 then
                local id = mint.ObjectID(object)
                local name = mint.ObjectName(object)

                if vision_ids[id] then
                    data.bad_potion_found = true
                    data.bad_potion = id
                    data.good_potion = potion_map[id]
                    print("Found bad potion: " .. name)
                    break
                end
            end
        end
    end
end, 3)

local Draw = mint.Draw:New()

Draw:Sync(function(draw)
    for _, object in ipairs(vision_objects) do
        local x, y, z = mint.ObjectPosition(object)
        if x and y and z then
            local id = mint.ObjectID(object)

            if data.bad_potion_found and id == data.bad_potion then
                draw:SetColor(255, 0, 0, 255)
            elseif id == data.good_potion then
                draw:SetColor(0, 255, 0, 255)
            else
                draw:SetColor(255, 255, 255, 255)
            end

            -- draw:Circle(x, y, z, 1)
            draw:Text(vision_ids[id], mint.Interface.mint_tiny, x, y, z)
        end
    end

    -- local objects = mint.Objects(8)
    -- for _, object in pairs(objects) do
    --     local x, y, z = mint.ObjectPosition(object)
    --     local name = mint.ObjectName(object)
    --     local id = mint.ObjectID(object)
    --     if not vision_ids[id] then
    --         local str = string.format("%s (%d)", name, id)
    --         draw:SetColor(255, 255, 255, 255)
    --         draw:Text(str, "GameFontNormal", x, y, z)
    --     end
    -- end

    -- local px, py, pz = mint.ObjectPosition("player")
    -- local px_trim = math.floor(px)
    -- local py_trim = math.floor(py)
    -- local pz_trim = math.floor(pz)

    -- local str = string.format("Player: %d, %d, %d", px_trim, py_trim, pz_trim)
    -- draw:Text(str, "GameFontNormal", px, py, pz)
end)

Draw:Enable()