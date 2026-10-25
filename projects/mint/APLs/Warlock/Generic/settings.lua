local unlocker, ---@class mint
mint, addon = ...

-- Minimal settings for generic warlock
local function Init()
    if not mint.Settings.profile.warlock then mint.Settings.profile.warlock = {} end
    if not mint.Settings.profile.warlock.generic then mint.Settings.profile.warlock.generic = {} end
end

Init()
