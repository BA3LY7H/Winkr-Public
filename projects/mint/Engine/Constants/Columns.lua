local unlocker,
---@class mint
mint = ...

---@class Constants
---@field WhitelistCols table
local Constants = mint.Constants

Constants.WhitelistCols = {
    {
        name     = 'Icon',
        width    = 40,
        align    = 'CENTER',
        index    = 'icon',
        format   = 'icon',
        sortable = false,
        events   = {
            OnEnter = function(table, cellFrame, rowFrame, rowData, columnData, rowIndex)
                showTooltip(cellFrame, true, rowData.spellId);
                return false;
            end,
            OnLeave = function(rowFrame, cellFrame)
                showTooltip(cellFrame, false);
                return false;
            end
        },
    },
    {
        name   = 'Spell',
        width  = 170,
        align  = 'LEFT',
        index  = 'name',
        format = 'string',
        color  = function(table, value, rowData, columnData)
            local enabled = rowData.enabled

            if enabled then
                return { r = 1, g = 0.82, b = 0, a = 1 };
            else
                return { r = 1, g = 0.82, b = 0, a = 0.5 };
            end
        end
    },
    {
        name   = 'Enabled',
        width  = 60,
        align  = 'LEFT',
        index  = 'enabled',
        format = 'bindCheckbox',
        sortable = false,
    },
}