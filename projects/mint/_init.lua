WINKR_MODS_DIR = "C:\\mods\\mint"

local content = winkr_ReadFile(WINKR_MODS_DIR .. "\\loader.lua")
if content then
    local fn, err = loadstring(content, "@loader.lua")
    if fn then
        -- loader.lua expects (name, mint, unlocker). Pass an empty table for mint so it isn't nil.
        fn("retail", {}, nil)
    else
        print("Winkr Init Error: loader.lua compilation failed - ", err)
    end
else
    print("Winkr Init Error: Could not read " .. WINKR_MODS_DIR .. "\\loader.lua")
end
