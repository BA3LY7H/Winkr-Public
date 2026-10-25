local unlocker, mint, addon = ...

local Actor = mint.Actor

addon.evoker = {}
addon.evoker.settings = {
	devastation = {},
    augmentation = {},
    preservation = {}
}

addon.evoker.data = {
	vars = {},
	devastation = {},
    augmentation = {},
    preservation = {},
}

-- Devastation Actor
local dpe_actor = Actor.New({ spec = 1, class = "evoker"}) -- 1 is Devastation
addon.evoker.devastation = dpe_actor

-- Augmentation Actor
local aug_actor = Actor.New({ spec = 3, class = "evoker"}) -- 3 is Augmentation
addon.evoker.augmentation = aug_actor

-- Shared Unit Finders
addon.evoker.GetKickTarget = function()
    local best = mint.UnitManager:Get("none")
    local lowest_pct = 100
    
    mint.ObjectManager.combat:loop(function(enemy)
        if enemy.is_dead then return false end
        if enemy:IsCastingOrChanneling() and enemy:IsKickable() then
            if enemy:IsWithin(25) then
                local pct = enemy:GetCastPercent()
                if pct > 30 and pct < lowest_pct then
                    best = enemy
                    lowest_pct = pct
                end
            end
        end
        return false -- Keep looping
    end)
    return best
end

-- Preservation Actor
local pre_actor = Actor.New({ spec = 2, class = "evoker"}) -- 2 is Preservation
addon.evoker.preservation = pre_actor

mint.console.log("Evoker Actors sync'd.")
