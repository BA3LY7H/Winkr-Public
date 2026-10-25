local unlocker, ---@class mint
mint, addon = ...

local settings      = mint.Settings
local settings_page = addon.shaman.enhancement:GetUI()

-- Default values for the database
local defaults = {
    engage_only         = true,
    rotation_strategy   = 1, -- 1: Auto, 2: Raid (ST), 3: Mythic+ (AoE)
    hero_spec           = 1, -- 1: Totemic, 2: Stormbringer
    use_sundering       = true,
    use_pwave           = true,
    maelstrom_threshold = 5,
}

-- Ensure these defaults are registered in the setting database
settings_page:AddDefaults(defaults)

-- Data-driven UI Layout
addon.shaman.settings["Enhancement"] = {
    page = {
        layoutConfig = { padding = { top = 15 } },
        database = settings.profile.shaman.enhancement,
        rows = {
            -- Header
            {
                header = {
                    type = 'header',
                    label = '|TInterface\\Icons\\spell_nature_lightning:18:18|t Enhancement Shaman'
                }
            },
            -- General Options
            {
                margins = { margin = { top = 20 }, order = 0 },
                engage_only = {
                    key = 'engage_only',
                    type = 'checkbox',
                    label = 'Only Attack Engaged',
                    tooltip = 'If enabled, the rotation will only attack targets that are already in combat with you or your party.',
                    column = 3,
                    order = 1
                },
                rotation_strategy = {
                    key = 'rotation_strategy',
                    type = 'dropdown',
                    label = 'Rotation Strategy',
                    options = {
                        { label = 'Auto', value = 1 },
                        { label = 'Raid (ST)', value = 2 },
                        { label = 'Mythic+ (AoE)', value = 3 },
                    },
                    column = 6,
                    order = 2
                },
            },
            -- Hero Specialization
            {
                margins = { margin = { top = 10 }, order = 1 },
                hero_spec = {
                    key = 'hero_spec',
                    type = 'dropdown',
                    label = 'Hero Specialization',
                    options = {
                        { label = 'Totemic', value = 1 },
                        { label = 'Stormbringer', value = 2 },
                    },
                    column = 6,
                    order = 1
                },
            },
            -- Ability Toggles
            {
                margins = { margin = { top = 10 }, order = 2 },
                use_sundering = {
                    key = 'use_sundering',
                    type = 'checkbox',
                    label = 'Use Sundering',
                    column = 3,
                    order = 1
                },
                use_pwave = {
                    key = 'use_pwave',
                    type = 'checkbox',
                    label = 'Use Primordial Wave',
                    column = 3,
                    order = 2
                },
                maelstrom_threshold = {
                    key = 'maelstrom_threshold',
                    type = 'slider',
                    label = 'Maelstrom Spend Threshold',
                    min = 5,
                    max = 10,
                    column = 6,
                    order = 3
                },
            },
        },
    }
}

-- Apply the layout to the page
settings_page:AddLayout(addon.shaman.settings["Enhancement"].page)
