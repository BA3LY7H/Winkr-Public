local Unlocker, mint = ...

---@class StdUi
local StdUi = mint.StdUi

if not StdUi then return end

local module, version = 'Label', 3;
if not StdUi:UpgradeNeeded(module, version) then return end;

----------------------------------------------------
--- FontString
----------------------------------------------------

local FontStringMethods = {
	SetFontSize = function(self, newSize)
		self:SetFont(self:GetFont(), newSize);
	end
}

--- @return FontString
function StdUi:FontString(parent, text, inherit)
	local fs = parent:CreateFontString(nil, self.config.font.strata, inherit or self.config.font.family);

	fs:SetText(text);
	fs:SetJustifyH('LEFT');
	fs:SetJustifyV('MIDDLE');

	for k, v in pairs(FontStringMethods) do
		fs[k] = v;
	end

	return fs;
end

----------------------------------------------------
--- Label
----------------------------------------------------

--- @return FontString
function StdUi:Label(parent, text, size, inherit, width, height, colorType, tooltip)
	local fs = self:FontString(parent, text, inherit);
	if size then
		fs:SetFontSize(size);
	end

	self:SetTextColor(fs, colorType or 'normal');
	self:SetObjSize(fs, width, height);

	if (tooltip) then
		self:FrameTooltip(fs, tooltip, 'mintTip', 'TOP', true)
	end

	return fs;
end

--- @return FontString
function StdUi:ElementLabel(parent, text, size, inherit, width, height)
	local fs = self:FontString(parent, text, inherit);
	if size then
		fs:SetFontSize(size);
	end

	self:SetTextColor(fs, 'element');
	self:SetObjSize(fs, width, height);

	return fs;
end

----------------------------------------------------
--- Header
----------------------------------------------------

--- @return FontString
function StdUi:Header(parent, text, size, inherit, width, height)
	local fs = self:Label(parent, text, size, inherit or 'GameFontNormalLarge', width, height);

	self:SetTextColor(fs, 'header');

	return fs;
end

--- @return FontString
function StdUi:SubHeader(parent, text, size, inherit, width, height)
	local fs = self:Label(parent, text, size, inherit or 'GameFontNormal', width, height);

	self:SetTextColor(fs, 'header');

	return fs;
end

----------------------------------------------------
--- AddLabel
----------------------------------------------------

--- @return FontString
function StdUi:AddLabel(parent, object, text, labelPosition, labelWidth, colorType)
	local labelHeight = (self.config.font.size) + 4;
	local label = self:Label(parent, text, self.config.font.size, nil, labelWidth, labelHeight, colorType);

	if labelPosition == 'TOP' or labelPosition == nil then
		self:GlueAbove(label, object, 0, 4, 'LEFT');
	elseif labelPosition == 'RIGHT' then
		self:GlueRight(label, object, 4, 0);
	elseif labelPosition == 'BOTTOM' then
		self:GlueBelow(label, object, 0, -2, 'LEFT');
	else -- labelPosition == 'LEFT'
		label:SetWidth(labelWidth or label:GetStringWidth())
		self:GlueLeft(label, object, -4, 0);
	end

	object.label = label;

	return label;
end

StdUi:RegisterModule(module, version);