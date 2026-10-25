local unlocker, mint, addon = ...
local blood = addon.deathknight.blood
local ui = blood:GetUI()
local settings = mint.Settings

-- Default Settings Integration
local defaults = {
    death_strike_hp   = 70,
    death_strike_rp   = 75,
    vampiric_blood_hp = 40,
    icebound_hp       = 30,
    ams_hp            = 50,
    death_pact_hp     = 25,
    auto_ghoul        = true,
    maintain_cleave   = true,
    bone_shield_min   = 6,
}

ui:AddDefaults(defaults)

addon.deathknight.settings["Blood"] = {
    page = {
        layoutConfig = { padding = { top = 15 } },
        database = settings.profile.deathknight.blood,
        rows = {
            {
                header = {
                    type = 'header',
                    label = '|TInterface\\Icons\\spell_deathknight_bloodpresence:18:18|t Blood Death Knight'
                }
            },
            {
                stop_label = {
                    type = 'label',
                    label = '|TInterface\\Icons\\spell_deathknight_deathstrike:18:18|t Resource Management',
                    size = 13,
                }
            },
            {
                death_strike_hp = {
                    key = 'death_strike_hp',
                    type = 'slider',
                    label = 'Death Strike HP %',
                    min = 10, max = 100, column = 6, order = 1
                },
                death_strike_rp = {
                    key = 'death_strike_rp',
                    type = 'slider',
                    label = 'Death Strike RP Trigger',
                    min = 40, max = 95, column = 6, order = 2
                },
            },
            {
                bone_shield_min = {
                    key = 'bone_shield_min',
                    type = 'slider',
                    label = 'Min Bone Shield Stacks',
                    min = 0, max = 10, column = 6, order = 1
                },
            },
            {
                def_label = {
                    type = 'label',
                    label = '|TInterface\\Icons\\spell_deathknight_iceboundfortitude:18:18|t Defensives',
                    size = 13,
                }
            },
            {
                vampiric_blood_hp = {
                    key = 'vampiric_blood_hp',
                    type = 'slider',
                    label = 'Vampiric Blood HP %',
                    min = 10, max = 100, column = 6, order = 1
                },
                icebound_hp = {
                    key = 'icebound_hp',
                    type = 'slider',
                    label = 'Icebound HP %',
                    min = 10, max = 100, column = 6, order = 2
                },
            },
            {
                ams_hp = {
                    key = 'ams_hp',
                    type = 'slider',
                    label = 'Anti-Magic Shell HP %',
                    min = 10, max = 100, column = 6, order = 1
                },
                death_pact_hp = {
                    key = 'death_pact_hp',
                    type = 'slider',
                    label = 'Death Pact HP %',
                    min = 10, max = 100, column = 6, order = 2
                },
            },
            {
                auto_label = {
                    type = 'label',
                    label = 'Automation',
                    size = 13,
                }
            },
            {
                auto_ghoul = {
                    key = 'auto_ghoul',
                    type = 'checkbox',
                    label = 'Auto-Ghoul (Raise Dead)',
                    column = 6, order = 1
                },
                maintain_cleave = {
                    key = 'maintain_cleave',
                    type = 'checkbox',
                    label = 'Maintain Cleaving Strikes (DnD)',
                    column = 6, order = 2
                },
            }
        }
    }
}

ui:AddLayout(addon.deathknight.settings["Blood"].page)
