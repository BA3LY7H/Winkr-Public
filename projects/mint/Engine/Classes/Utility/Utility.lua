local unlocker,
---@class mint
mint = ...

---@class Utility
local Utility = {}
Utility.__index = Utility

function Utility:TableMerge(table1, table2)
	local result = {};
	for k, v in pairs(table1) do
		if type(v) == 'table' then
			if table2[k] then
				result[k] = self:TableMerge(v, table2[k]);
			else
				result[k] = v;
			end
		else
			result[k] = table2[k] or table1[k];
		end
	end

	for k, v in pairs(table2) do
		if not result[k] then
			result[k] = v;
		end
	end

	return result;
end

return Utility