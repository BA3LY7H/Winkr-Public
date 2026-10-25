-- local unlocker,
-- ---@class mint
-- mint = ...

-- ---@class Interface
-- local Interface     = mint.Interface

-- ----------------------------
-- --- Constants/Locals
-- ----------------------------
-- local Constants     	= mint.Constants or {}
-- local ProfileManager 	= mint.ProfileManager

-- ----------------------------
-- --- Local Functions
-- ----------------------------

-- ----------------------------
-- --- Page Creation
-- ----------------------------
-- Interface.Page:New("Profiles", "profiles", true, function(self)
-- 	self.factory:EasyLayout(self.pages.profiles, { padding = { top = 5 } });

-- 	local profile_list = {}

-- 	for k, v in pairs(ProfileManager:GetAllProfileNames()) do
-- 		table.insert(profile_list, { text = v, value = v })
-- 	end

-- 	local active_name = ProfileManager:GetActiveProfileName()

-- 	self.dropdowns.profile_select = self.factory:Dropdown(self.pages.profiles, 200, 30, profile_list, active_name, false);

-- 	self.dropdowns.profile_select:SetPlaceholder('-- Select Profile --')
-- 	self.labels.current_profile = self.factory:AddLabel(self.pages.profiles, self.dropdowns.profile_select, 'Current: ' .. active_name, 'TOP')

-- 	-- self.dropdowns.profile_select.OnValueChanged = function(this, value)
-- 	-- 	ProfileManager:UpdateActiveProfile(value)
-- 	-- 	self:UpdateProfile()
-- 	-- end

-- 		--! Import Profile Button !--
-- 		self.buttons.import_profile = self.factory:Button(self.pages.profiles, 100, 20, 'Import')

-- 		-- self.buttons.import_profile:SetScript('OnClick', function()
-- 		-- 	local selected = self.dropdowns.profile_select:GetValue()
	
-- 		-- 	if selected == ProfileManager:GetActiveProfileName() then
-- 		-- 		return
-- 		-- 	end
	
-- 		-- 	if not selected then
-- 		-- 		mint:Log("You must select a profile to activate.")
-- 		-- 		return
-- 		-- 	end
	
-- 		-- 	ProfileManager:UpdateActiveProfile(selected)
-- 		-- 	self:UpdateProfile()
-- 		-- end)
	
-- 		--! Export Profile Button !--
-- 		self.buttons.export_profile = self.factory:Button(self.pages.profiles, 100, 20, 'Export')
	
-- 		-- self.buttons.export_profile:SetScript('OnClick', function()
-- 		-- 	local selected = self.dropdowns.profile_select:GetValue()
	
-- 		-- 	if selected == ProfileManager:GetActiveProfileName() then
-- 		-- 		mint:Log("You cannot delete the active profile.")
-- 		-- 		return
-- 		-- 	end
	
-- 		-- 	if not selected then
-- 		-- 		mint:Log("You must select a profile to delete.")
-- 		-- 		return
-- 		-- 	end
	
-- 		-- 	ProfileManager:DeleteProfileByName(selected)
-- 		-- end)


-- 	local profiles_row_1 = self.pages.profiles:AddRow({ margin = { top = 20 } });
-- 	profiles_row_1:AddElement(self.dropdowns.profile_select, { column = 5 });
-- 	profiles_row_1:AddElement(self.factory:Frame(self.pages.profiles, 0, 0), { column = 3 });
-- 	profiles_row_1:AddElement(self.buttons.import_profile, { column = 2 });
-- 	profiles_row_1:AddElement(self.buttons.export_profile, { column = 2 });

-- 	--! Select Profile Button !--
-- 	self.buttons.select_profile = self.factory:Button(self.pages.profiles, 100, 20, 'Load Selected')

-- 	self.buttons.select_profile:SetScript('OnClick', function()
-- 		local selected = self.dropdowns.profile_select:GetValue()

-- 		if selected == ProfileManager:GetActiveProfileName() then
-- 			return
-- 		end

-- 		if not selected then
-- 			mint:Log("You must select a profile to activate.")
-- 			return
-- 		end

-- 		ProfileManager:UpdateActiveProfile(selected)
-- 		self:UpdateProfile()
-- 	end)

-- 	--! Delete Profile Button !--
-- 	self.buttons.del_profile = self.factory:Button(self.pages.profiles, 100, 20, 'Delete')

-- 	self.buttons.del_profile:SetScript('OnClick', function()
-- 		local selected = self.dropdowns.profile_select:GetValue()

-- 		if selected == ProfileManager:GetActiveProfileName() then
-- 			mint:Log("You cannot delete the active profile.")
-- 			return
-- 		end

-- 		if not selected then
-- 			mint:Log("You must select a profile to delete.")
-- 			return
-- 		end

-- 		ProfileManager:DeleteProfileByName(selected)
-- 	end)

-- 	local profiles_row_2 = self.pages.profiles:AddRow({ margin = { top = 5 } });
-- 	profiles_row_2:AddElement(self.buttons.select_profile, { column = 4 });
-- 	profiles_row_2:AddElement(self.buttons.del_profile, { column = 2 });


-- 	--! Create Profile Name !--
-- 	local new_profile_name = self.factory:SimpleEditBox(self.pages.profiles, 150, 24, 'Create New Profile');
-- 	self.factory:GlueTop(new_profile_name, self.pages.profiles, 10, -40, 'LEFT');

-- 	--! Create Profile Button !--
-- 	self.buttons.new_profile = self.factory:Button(self.pages.profiles, 100, 20, 'Create')

-- 	self.buttons.new_profile:SetScript('OnClick', function()
-- 		local name = new_profile_name:GetText()

-- 		if not name or name == '' or name == 'Create New Profile' then
-- 			mint:Log("You must enter a name for the new profile.")
-- 			return
-- 		end

-- 		ProfileManager:CreateNewProfile(name)
-- 		self:UpdateProfile()
-- 	end)

-- 	local profiles_row_3 = self.pages.profiles:AddRow({ margin = { top = 25 } });
-- 	profiles_row_3:AddElement(new_profile_name, { column = 5 });

-- 	local profiles_row_4 = self.pages.profiles:AddRow({ margin = { top = 5 } });
-- 	profiles_row_4:AddElement(self.buttons.new_profile, { column = 2 });

-- 	--! Duplicate Profile Name !--
-- 	local copy_profile_name = self.factory:SimpleEditBox(self.pages.profiles, 150, 24, 'Copy Active Profile');
-- 	self.factory:GlueTop(copy_profile_name, self.pages.profiles, 10, -40, 'LEFT');

-- 	--! Duplicate Profile Button !--
-- 	self.buttons.dupe_profile = self.factory:Button(self.pages.profiles, 100, 20, 'Duplicate')

-- 	self.buttons.dupe_profile:SetScript('OnClick', function()
-- 		local name = copy_profile_name:GetText()

-- 		if not name or name == '' or name == 'Copy Active Profile' then
-- 			mint:Log("You must enter a name for the new profile.")
-- 			return
-- 		end

-- 		ProfileManager:DuplicateProfile(name, ProfileManager:GetActiveProfileName())
-- 		self:UpdateProfile()
-- 	end)

-- 	local profiles_row_5 = self.pages.profiles:AddRow({ margin = { top = 25 } });
-- 	profiles_row_5:AddElement(copy_profile_name, { column = 5 });


-- 	local profiles_row_6 = self.pages.profiles:AddRow({ margin = { top = 5 } });
-- 	profiles_row_6:AddElement(self.buttons.dupe_profile, { column = 2 });

-- 	--! Actually populate the tab !--
-- 	self.pages.profiles:DoLayout();
-- end)