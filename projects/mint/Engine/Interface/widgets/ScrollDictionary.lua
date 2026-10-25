local Unlocker, mint = ...

---@class StdUi
local StdUi = mint.StdUi

if not StdUi then return end

local module, version = 'ScrollDictionary', 1;
if not StdUi:UpgradeNeeded(module, version) then
	return
end

local TableInsert = tinsert;
local TableSort = table.sort;
local padding = 2.5;

-- Function to convert a dictionary to a sorted array
local function DictionaryToSortedArray(dict)
	local array = {};
	for k, v in pairs(dict) do
		-- Store the key within the value for reference
		if type(v) == "table" then
			v._key = k;
			TableInsert(array, v);
		else
			TableInsert(array, { _key = k, _value = v });
		end
	end
	return array;
end

-- Function to get all keys from a dictionary
local function GetDictionaryKeys(dict)
	local keys = {};
	for k, _ in pairs(dict) do
		TableInsert(keys, k);
	end
	return keys;
end

--- Public methods of ScrollDictionary
local methods = {

	-------------------------------------------------------------
	--- Basic Methods
	-------------------------------------------------------------

	SetAutoHeight     = function(self)
		self:SetHeight((self.numberOfRows * self.rowHeight) + 10);
		self:Refresh();
	end,

	SetAutoWidth      = function(self)
		local width = 13;
		for _, col in pairs(self.columns) do
			width = width + col.width;
		end
		self:SetWidth(width + 20);
		self:Refresh();
	end,

	ScrollToLine      = function(self, line)
		line = Clamp(line, 1, #self.filtered - self.numberOfRows + 1);

		self:DoVerticalScroll(
			self.rowHeight * (line - 1),
			self.rowHeight, function(s)
				s:Refresh();
			end
		);
	end,

	ScrollToKey      = function(self, key)
		for i, rowData in ipairs(self.sortedData) do
			if rowData._key == key then
				local line = i;
				line = Clamp(line, 1, #self.filtered - self.numberOfRows + 1);
				
				self:DoVerticalScroll(
					self.rowHeight * (line - 1),
					self.rowHeight, function(s)
						s:Refresh();
					end
				);
				return;
			end
		end
	end,

	-------------------------------------------------------------
	--- Drawing Methods
	-------------------------------------------------------------

	--- Set the column info for the scrolling table
	--- @usage st:SetColumns(columns)
	SetColumns        = function(self, columns)
		local table = self; -- reference saved for closure
		self.columns = columns;

		local columnHeadFrame = self.head;

		if not columnHeadFrame then
			columnHeadFrame = CreateFrame('Frame', nil, self);
			columnHeadFrame:SetPoint('BOTTOMLEFT', self, 'TOPLEFT', 4, 0);
			columnHeadFrame:SetPoint('BOTTOMRIGHT', self, 'TOPRIGHT', -4, 0);
			columnHeadFrame:SetHeight(self.rowHeight);
			columnHeadFrame.columns = {};
			self.head = columnHeadFrame;
		end

		for i = 1, #columns do
			local column = self.columns[i];
			local columnFrame = columnHeadFrame.columns[i];
			if not columnHeadFrame.columns[i] then
				columnFrame = self.stdUi:HighlightButton(columnHeadFrame);
				columnFrame:SetPushedTextOffset(0, 0);

				columnFrame.arrow = self.stdUi:Texture(columnFrame, 8, 8, [[Interface\Buttons\UI-SortArrow]]);
				columnFrame.arrow:Hide();

				if self.headerEvents then
					for event, handler in pairs(self.headerEvents) do
						columnFrame:SetScript(event, function(cellFrame, ...)
							table:FireHeaderEvent(event, handler, columnFrame, columnHeadFrame, i, ...);
						end);
					end
				end

				columnFrame.storedValues = column.storedValues or {}

				columnHeadFrame.columns[i] = columnFrame;

				-- Add column head reference to it's column
				column.head = columnFrame;

				-- Create a table of empty column cell references
				column.cells = {};
			end

			local align = columns[i].align or 'LEFT';
			columnFrame.text:SetJustifyH(align);
			columnFrame.text:SetText(columns[i].name);

			if align == 'LEFT' then
				columnFrame.arrow:ClearAllPoints();
				self.stdUi:GlueRight(columnFrame.arrow, columnFrame, 0, 0, true);
			else
				columnFrame.arrow:ClearAllPoints();
				self.stdUi:GlueLeft(columnFrame.arrow, columnFrame, 5, 0, true);
			end

			if columns[i].sortable == false and columns[i].sortable ~= nil then

			else

			end

			if i > 1 then
				columnFrame:SetPoint('LEFT', columnHeadFrame.columns[i - 1], 'RIGHT', 0, 0);
			else
				columnFrame:SetPoint('LEFT', columnHeadFrame, 'LEFT', 2, 0);
			end

			columnFrame:SetHeight(self.rowHeight);
			columnFrame:SetWidth(columns[i].width);

			--- Set the width of a column
			--- @usage st.columns[i]:SetWidth(width)
			function column:SetWidth(width)
				-- Update the column's width value
				column.width = width;

				-- Set the width of the column's head
				column.head:SetWidth(width);

				-- Set the width of each cell in the column
				for j = 1, #column.cells do
					column.cells[j]:SetWidth(width)
				end
			end
		end

		self:SetDisplayRows(self.numberOfRows, self.rowHeight);
		self:SetAutoWidth();
	end,

	--- Set the number and height of displayed rows
	--- @usage st:SetDisplayRows(10, 15)
	SetDisplayRows    = function(self, numberOfRows, rowHeight)
		local table = self; -- reference saved for closure
		-- should always set columns first
		self.numberOfRows = numberOfRows;
		self.rowHeight = rowHeight;

		if not self.rows then
			self.rows = {};
		end

		for i = 1, numberOfRows do
			local rowFrame = self.rows[i];

			if not rowFrame then
				rowFrame = CreateFrame('Button', nil, self);
				self.rows[i] = rowFrame;

				if i > 1 then
					rowFrame:SetPoint('TOPLEFT', self.rows[i - 1], 'BOTTOMLEFT', 0, 0);
					rowFrame:SetPoint('TOPRIGHT', self.rows[i - 1], 'BOTTOMRIGHT', 0, 0);
				else
					rowFrame:SetPoint('TOPLEFT', self.scrollFrame, 'TOPLEFT', 1, -1);
					rowFrame:SetPoint('TOPRIGHT', self.scrollFrame, 'TOPRIGHT', -1, -1);
				end

				rowFrame:SetHeight(rowHeight);
			end

			if not rowFrame.columns then
				rowFrame.columns = {};
			end

			for j = 1, #self.columns do
				local columnData = self.columns[j];

				local cell = rowFrame.columns[j];
				if not cell then
					cell = CreateFrame('Button', nil, rowFrame);
					cell.text = self.stdUi:FontString(cell, '');

					rowFrame.columns[j] = cell;

					-- Add cell reference to column
					self.columns[j].cells[i] = cell;

					local align = columnData.align or 'LEFT';

					cell.text:SetJustifyH(align);
					cell:EnableMouse(true);
					cell:RegisterForClicks('AnyUp');

					if self.cellEvents then
						for event, handler in pairs(self.cellEvents) do
							cell:SetScript(event, function(cellFrame, ...)
								if table.offset then
									local rowIndex = table.filtered[i + table.offset];
									local rowData = table:GetRow(rowIndex);
									table:FireCellEvent(event, handler, cellFrame, rowFrame, rowData, columnData,
										rowIndex, ...);
								end
							end);
						end
					end

					-- override a column based events
					if columnData.events then
						for event, handler in pairs(columnData.events) do

							cell:SetScript(event, function(cellFrame, ...)
								if table.offset then
									local rowIndex = table.filtered[i + table.offset];
									local rowData = table:GetRow(rowIndex);
									table:FireCellEvent(event, handler, cellFrame, rowFrame, rowData, columnData,
										rowIndex, ...);
								end
							end);
						end
					end
				end

				if j > 1 then
					cell:SetPoint('LEFT', rowFrame.columns[j - 1], 'RIGHT', 0, 0);
				else
					cell:SetPoint('LEFT', rowFrame, 'LEFT', 2, 0);
				end

				cell:SetHeight(rowHeight);
				cell:SetWidth(self.columns[j].width);

				cell.text:SetPoint('TOP', cell, 'TOP', 0, 0);
				cell.text:SetPoint('BOTTOM', cell, 'BOTTOM', 0, 0);
				cell.text:SetWidth(self.columns[j].width - 2 * padding);
			end

			local j = #self.columns + 1;
			local col = rowFrame.columns[j];
			while col do
				col:Hide();
				j = j + 1;
				col = rowFrame.columns[j];
			end
		end

		for i = numberOfRows + 1, #self.rows do
			self.rows[i]:Hide();
		end

		self:SetAutoHeight();
	end,

	--- Set the width of a column
	--- @usage st:SetColumnWidth(2, 65)
	SetColumnWidth   = function(self, columnNumber, width)
		self.columns[columnNumber]:SetWidth(width);
	end,

	-------------------------------------------------------------
	--- Dictionary Specific Methods
	-------------------------------------------------------------

	--- Get a value from the dictionary using its key
	--- @usage st:GetValueByKey(key)
	GetValueByKey = function(self, key)
		return self.data[key];
	end,

	--- Set a value in the dictionary by key
	--- @usage st:SetValueByKey(key, value)
	SetValueByKey = function(self, key, value)
		self.data[key] = value;
		self:UpdateSortedData();
		self:SortData();
	end,

	--- Remove a key from the dictionary
	--- @usage st:RemoveKey(key)
	RemoveKey = function(self, key)
		if self.data[key] then
			self.data[key] = nil;
			self:UpdateSortedData();
			self:SortData();
		end
	end,

	--- Update the internal sorted data array from the dictionary
	UpdateSortedData = function(self)
		self.sortedData = DictionaryToSortedArray(self.data);
	end,

	-------------------------------------------------------------
	--- Sorting Methods
	-------------------------------------------------------------

	--- Resorts the table using the rules specified in the table column info.
	--- @usage st:SortData()
	SortData          = function(self, sortBy)
		-- sanity check
		if not self.sortedData then
			self:UpdateSortedData();
		end

		-- Make sure sortTable has the correct size
		if not (self.sortTable) or (#self.sortTable ~= #self.sortedData) then
			self.sortTable = {};
		end

		if #self.sortTable ~= #self.sortedData then
			for i = 1, #self.sortedData do
				self.sortTable[i] = i;
			end
		end

		-- go on sorting
		if not sortBy then
			local i = 1;
			while i <= #self.columns and not sortBy do
				if self.columns[i].sort then
					sortBy = i;
				end
				i = i + 1;
			end
		end

		if sortBy then
			TableSort(self.sortTable, function(rowA, rowB)
				local column = self.columns[sortBy];
				if column.compareSort then
					return column.compareSort(self, rowA, rowB, sortBy);
				else
					return self:CompareSort(rowA, rowB, sortBy);
				end
			end);
		end

		self.filtered = self:DoFilter();
		self:Refresh();
		self:UpdateSortArrows(sortBy);
	end,

	--- CompareSort function used to determine how to sort column values. Can be overridden in column data or table data.
	--- @usage used internally.
	CompareSort       = function(self, rowA, rowB, sortBy)
		local a = self:GetRow(rowA);
		local b = self:GetRow(rowB);
		local column = self.columns[sortBy];
		local idx = column.index;

		local direction = column.sort or column.defaultSort or 'asc';

		if direction:lower() == 'asc' then
			return a[idx] > b[idx];
		else
			return a[idx] < b[idx];
		end
	end,

	Filter            = function(self, rowData)
		return true;
	end,

	--- Set a display filter for the table.
	--- @usage st:SetFilter( function (self, ...) return true end )
	SetFilter         = function(self, filter, noSort)
		self.Filter = filter;
		if not noSort then
			self:SortData();
		end
	end,

	DoFilter          = function(self)
		local result = {};

		for row = 1, #self.sortedData do
			local realRow = self.sortTable[row];
			local rowData = self:GetRow(realRow);

			if self:Filter(rowData) then
				TableInsert(result, realRow);
			end
		end

		return result;
	end,

	-------------------------------------------------------------
	--- Highlight Methods
	-------------------------------------------------------------

	--- Set the row highlight color of a frame ( cell or row )
	--- @usage st:SetHighLightColor(rowFrame, color)
	SetHighLightColor = function(self, frame, color)
		if not frame.highlight then
			frame.highlight = frame:CreateTexture(nil, 'OVERLAY');
			frame.highlight:SetAllPoints(frame);
		end

		if not color then
			frame.highlight:SetColorTexture(0, 0, 0, 0);
		else
			frame.highlight:SetColorTexture(color.r, color.g, color.b, color.a);
		end
	end,

	ClearHighlightedRows = function(self)
		self.highlightedRows = {};
		self:Refresh();
	end,

	HighlightRows = function(self, rowIndexes)
		self.highlightedRows = rowIndexes;
		self:Refresh();
	end,

	-------------------------------------------------------------
	--- Selection Methods
	-------------------------------------------------------------

	--- Turn on or off selection on a table according to flag. Will not refresh the table display.
	--- @usage st:EnableSelection(true)
	EnableSelection   = function(self, flag)
		self.selectionEnabled = flag;
	end,

	--- Clear the currently selected row. You should not need to refresh the table.
	--- @usage st:ClearSelection()
	ClearSelection    = function(self)
		self:SetSelection(nil);
	end,

	--- Sets the currently selected row to 'realRow'. RealRow is the unaltered index of the data row in your table.
	--- You should not need to refresh the table.
	--- @usage st:SetSelection(12)
	SetSelection      = function(self, rowIndex)
		self.selected = rowIndex;
		self:Refresh();
	end,

	--- Gets the currently selected row.
	--- Return will be the unaltered index of the data row that is selected.
	--- @usage st:GetSelection()
	GetSelection      = function(self)
		return self.selected;
	end,

	--- Gets the currently selected row data.
	--- @usage st:GetSelectedItem()
	GetSelectedItem   = function(self)
		return self:GetRow(self.selected);
	end,

	--- Gets the key of the currently selected row
	--- @usage st:GetSelectedKey()
	GetSelectedKey = function(self)
		local selectedItem = self:GetSelectedItem();
		if selectedItem then
			return selectedItem._key;
		end
		return nil;
	end,

	-------------------------------------------------------------
	--- Data Methods
	-------------------------------------------------------------

	--- Sets the data for the scrolling dictionary
	--- @usage st:SetData(datatable)
	SetData           = function(self, data)
		self.data = data;
		self:UpdateSortedData();
		self:SortData();
	end,

	--- Returns the data row of the table from the given data row index
	--- @usage used internally.
	GetRow            = function(self, rowIndex)
		return self.sortedData[rowIndex];
	end,

	--- Returns the cell data of the given row from the given row and column index
	--- @usage used internally.
	GetCell           = function(self, row, col)
		local rowData = row;
		if type(row) == 'number' then
			rowData = self:GetRow(row);
		end

		return rowData[col];
	end,

	--- Checks if a row is currently being shown
	--- @usage st:IsRowVisible(realrow)
	IsRowVisible      = function(self, rowIndex)
		return (rowIndex > self.offset and rowIndex <= (self.numberOfRows + self.offset));
	end,

	-------------------------------------------------------------
	--- Update Internal Methods
	-------------------------------------------------------------

	--- Cell update function used to paint each cell. Can be overridden in column data or table data.
	--- @usage used internally.
	DoCellUpdate = function(table, shouldShow, rowFrame, cellFrame, value, columnData, rowData, rowIndex)
		if shouldShow then
			local format = columnData.format;
			
			-- For all formats, first ensure the cell is visible
			cellFrame:Show()
			
			if type(format) == 'function' then
				cellFrame.text:SetText(format(value, rowData, columnData));
			elseif format == 'money' then
				value = table.stdUi.Util.formatMoney(value);
				cellFrame.text:SetText(value);
			elseif format == 'moneyShort' then
				value = table.stdUi.Util.formatMoney(value, true);
				cellFrame.text:SetText(value);
			elseif format == 'time' then
				value = table.stdUi.Util.formatTime(value);
				cellFrame.text:SetText(value);
			elseif format == 'number' then
				value = tostring(value);
				cellFrame.text:SetText(value);
			elseif format == 'key' then
				-- Special format to display the dictionary key
				value = tostring(rowData._key);
				-- cellFrame.text:SetText("");
				cellFrame.text:SetText(value);
			elseif format == 'icon' then
				if cellFrame.texture then
					cellFrame.texture:SetTexture(value);
					cellFrame.texture:Show();
				else
					local iconSize = columnData.iconSize or table.rowHeight;
					cellFrame.texture = table.stdUi:Texture(cellFrame, iconSize, iconSize, value);
					cellFrame.texture:SetPoint('CENTER', 0, 0);
				end
			elseif format == 'bindCheckbox' then
		
				if not cellFrame.checkbox then
					cellFrame.checkbox = table.stdUi:Checkbox(cellFrame, '');
					cellFrame.checkbox:SetPoint('CENTER', 0, 0);
					
					cellFrame.checkbox.OnValueChanged = function(this, val)
						if rowIndex and table.sortedData[rowIndex] then
							local key = table.sortedData[rowIndex]._key;
							if table.data[key] then
								if type(table.data[key]) == "table" then
									table.data[key][columnData.index] = val;
								else
									-- If it's not a table, we need to create a table structure
									local oldValue = table.data[key];
									table.data[key] = { _value = oldValue, [columnData.index] = val };
								end
								table:UpdateSortedData();
							end
						end
					end
				else
					-- Ensure checkbox is visible
					cellFrame.checkbox:Show();
				end

				cellFrame.checkbox:SetChecked(value, true);
				
				-- Check if the button is disabled
				if rowData and rowData.disabled then
					cellFrame.checkbox:Disable();
				end
			elseif format == 'checkbox' then
				if not cellFrame.checkbox then
					cellFrame.checkbox = table.stdUi:Checkbox(cellFrame, '');
					cellFrame.checkbox:SetPoint('CENTER', 0, 0);
					
					cellFrame.checkbox.OnValueChanged = function(this, val)
						if rowIndex and table.sortedData[rowIndex] then
							local key = table.sortedData[rowIndex]._key;
							if table.data[key] then
								if type(table.data[key]) == "table" then
									table.data[key][columnData.index] = val;
								else
									-- If it's not a table, we need to create a table structure
									local oldValue = table.data[key];
									table.data[key] = { _value = oldValue, [columnData.index] = val };
								end
								table:UpdateSortedData();
							end
						end
					end
				else
					-- Ensure checkbox is visible
					cellFrame.checkbox:Show();
				end

				cellFrame.checkbox:SetChecked(value, true);
				
				-- Check if the button is disabled
				if rowData and rowData.disabled then
					cellFrame.checkbox:Disable();
				end
			elseif format == 'iconCheckbox' then
				if not cellFrame.checkbox then
					cellFrame.checkbox = table.stdUi:Checkbox(cellFrame, '');
					cellFrame.checkbox:SetPoint('LEFT', cellFrame, "LEFT", 2, 0);
					cellFrame.checkbox:SetChecked(value);

					-- Check if the button is disabled
					if rowData.stop then
						local spell_id = columnData.storedValues.spellId

						if rowData[spell_id .. "_disabled"] then
							cellFrame.checkbox:Disable();
						end
					end
					
					if rowData.disabled then
						cellFrame.checkbox:Disable();
						return
					end

					cellFrame.checkbox.OnValueChanged = function(this, val)
						if rowIndex and table.sortedData[rowIndex] then
							local key = table.sortedData[rowIndex]._key;
							if table.data[key] then
								if type(table.data[key]) == "table" then
									table.data[key][columnData.index] = val;
								else
									-- If it's not a table, we need to create a table structure
									local oldValue = table.data[key];
									table.data[key] = { _value = oldValue, [columnData.index] = val };
								end
								table:UpdateSortedData();
							end
						end
					end
				else
					-- Ensure checkbox is visible and has correct value
					cellFrame.checkbox:Show();
					cellFrame.checkbox:SetChecked(value);

					-- This ensures consistency during scrolling
					if cellFrame.checkbox:GetChecked() ~= value then
						-- Temporarily disable the OnValueChanged handler
						local oldHandler = cellFrame.checkbox.OnValueChanged;
						cellFrame.checkbox.OnValueChanged = nil;
						
						-- Update the checkbox state
						cellFrame.checkbox:SetChecked(value);
						
						-- Restore the handler
						cellFrame.checkbox.OnValueChanged = oldHandler;
					end
					
					-- Re-apply disabled state
					if rowData.disabled then
						cellFrame.checkbox:Disable();
					else
						cellFrame.checkbox:Enable();
					end
				end
			elseif format == 'dropdown' then
				if not cellFrame.dropdown then
					cellFrame.dropdown = table.stdUi:DropdownSmall(cellFrame, 90, 20, columnData.options, value, false);
					cellFrame.dropdown.text:SetText(value);

					cellFrame.dropdown.OnValueChanged = function(this, val)
						if rowIndex and table.sortedData[rowIndex] then
							local key = table.sortedData[rowIndex]._key;
							if table.data[key] then
								if type(table.data[key]) == "table" then
									table.data[key][columnData.index] = val;
								else
									-- If it's not a table, we need to create a table structure
									local oldValue = table.data[key];
									table.data[key] = { _value = oldValue, [columnData.index] = val };
								end
								table:UpdateSortedData();
							end
						end
						cellFrame.dropdown.text:SetText(val);
					end
				else
					-- Ensure dropdown is visible and has correct value
					cellFrame.dropdown:Show();
					cellFrame.dropdown.text:SetText(value);
				end
			elseif format == 'custom' then
				columnData.renderer(cellFrame, value, rowData, columnData);
			else
				cellFrame.text:SetText(value);
			end

			local color;
			if rowData.color then
				color = rowData.color;
			elseif columnData.color then
				color = columnData.color;
			end

			if type(color) == 'function' then
				color = color(table, value, rowData, columnData);
			end

			if color then
				cellFrame.text:SetTextColor(color.r, color.g, color.b, color.a);
			else
				table.stdUi:SetTextColor(cellFrame.text, 'normal');
			end

			if table.selectionEnabled then
				if table.selected == rowIndex then
					table:SetHighLightColor(rowFrame, table.stdUi.config.tables.select);
				else
					table:SetHighLightColor(rowFrame, nil);
				end
			else
				if tContains(table.highlightedRows, rowIndex) then
					table:SetHighLightColor(rowFrame, table.stdUi.config.highlight.color);
				else
					table:SetHighLightColor(rowFrame, nil);
				end
			end
		else
			-- When a row is not shown, properly hide all its components
			cellFrame.text:SetText('');
			
			-- Hide relevant UI elements based on format
			local format = columnData.format;
			
			if format == "icon" and cellFrame.texture then
				cellFrame.texture:Hide();
			elseif format == "bindCheckbox" and cellFrame.checkbox then
				cellFrame.checkbox:Hide();
			elseif format == "checkbox" and cellFrame.checkbox then
				cellFrame.checkbox:Hide();
			elseif format == "iconCheckbox" and cellFrame.checkbox then
				cellFrame.checkbox:Hide();
			elseif format == "dropdown" and cellFrame.dropdown then
				cellFrame.dropdown:Hide();
			end
		end
	end,

	Refresh = function(self)
		self:Update(#self.filtered, self.numberOfRows, self.rowHeight);
		
		local o = self:GetOffset();
		self.offset = o;
		
		for i = 1, self.numberOfRows do
			local row = i + o;
			
			if self.rows then
				local rowFrame = self.rows[i];
				
				local rowIndex = self.filtered[row];
				local rowData = self:GetRow(rowIndex);
				local shouldShow = rowData ~= nil;
				
				-- First set visibility of the entire row
				if shouldShow then
					rowFrame:Show();
				else
					rowFrame:Hide();
				end
				
				for col = 1, #self.columns do
					local cellFrame = rowFrame.columns[col];
					local columnData = self.columns[col];
					local value;
					local fnDoCellUpdate = self.DoCellUpdate;
					
					if rowData then
						-- If the format is "key", the value is the row's _key property
						if columnData.format == "key" then
							value = rowData._key;
						-- If the index is "_key", it's also the dictionary key
						elseif columnData.index == "_key" then
							value = rowData._key;
						-- If the index is "_value" and the row has that property, use it
						elseif columnData.index == "_value" and rowData._value ~= nil then
							value = rowData._value;
						else
							value = rowData[columnData.index];
						end
						
						-- Store the current data index on the cell frame for reference
						cellFrame.dataIndex = rowIndex;

						if rowData.doCellUpdate then
							fnDoCellUpdate = rowData.doCellUpdate;
						elseif columnData.doCellUpdate then
							fnDoCellUpdate = columnData.doCellUpdate;
						end
						
						-- Use our fixed cell update function
						fnDoCellUpdate(self, shouldShow, rowFrame, cellFrame, value, columnData, rowData, rowIndex);
					else
						-- If no data, ensure cell is hidden
						fnDoCellUpdate(self, false, rowFrame, cellFrame, nil, columnData, nil, nil);
					end
				end
			end
		end
	end,

	-------------------------------------------------------------
	--- Private Methods
	-------------------------------------------------------------

	UpdateSortArrows  = function(self, sortBy)
		if not self.head then
			return
		end

		for i = 1, #self.columns do
			local col = self.head.columns[i];
			if col then
				if i == sortBy then
					local column = self.columns[sortBy];
					local direction = column.sort or column.defaultSort or 'asc';
					if direction == 'asc' then
						col.arrow:SetTexCoord(0, 0.5625, 0, 1);
					else
						col.arrow:SetTexCoord(0, 0.5625, 1, 0);
					end

					col.arrow:Show();
				else
					col.arrow:Hide();
				end
			end
		end
	end,

	FireCellEvent     = function(self, event, handler, ...)
		if not handler(self, ...) then
			if self.cellEvents[event] then
				self.cellEvents[event](self, ...);
			end
		end
	end,

	FireHeaderEvent   = function(self, event, handler, ...)
		if not handler(self, ...) then
			if self.headerEvents[event] then
				self.headerEvents[event](self, ...);
			end
		end
	end,

	--- Set the event handlers for various ui events for each cell.
	--- @usage st:RegisterEvents(events, true)
	RegisterEvents    = function(self, cellEvents, headerEvents, removeOldEvents)
		local table = self; -- save for closure later

		if cellEvents then
			-- Register events for each cell
			for i, rowFrame in ipairs(self.rows) do
				for j, cell in ipairs(rowFrame.columns) do

					local columnData = self.columns[j];

					-- unregister old events.
					if removeOldEvents and self.cellEvents then
						for event, handler in pairs(self.cellEvents) do
							cell:SetScript(event, nil);
						end
					end

					-- register new ones.
					for event, handler in pairs(cellEvents) do
						cell:SetScript(event, function(cellFrame, ...)
							local rowIndex = table.filtered[i + table.offset];
							local rowData = table:GetRow(rowIndex);
							table:FireCellEvent(event, handler, cellFrame, rowFrame, rowData, columnData,
								rowIndex, ...);
						end);
					end

					-- override a column based events
					if columnData.events then
						for event, handler in pairs(self.columns[j].events) do
							cell:SetScript(event, function(cellFrame, ...)
								if table.offset then
									local rowIndex = table.filtered[i + table.offset];
									local rowData = table:GetRow(rowIndex);
									table:FireCellEvent(event, handler, cellFrame, rowFrame, rowData, columnData,
										rowIndex, ...);
								end
							end);
						end
					end
				end
			end
		end

		if headerEvents then
			-- Register events on column headers
			for columnIndex, columnFrame in ipairs(self.head.columns) do
				-- unregister old events.
				if removeOldEvents and self.headerEvents then
					for event, _ in pairs(self.headerEvents) do
						columnFrame:SetScript(event, nil);
					end
				end

				-- register new ones.
				for event, handler in pairs(headerEvents) do
					columnFrame:SetScript(event, function(cellFrame, ...)
						table:FireHeaderEvent(event, handler, columnFrame, self.head, columnIndex, ...);
					end);
				end
			end
		end
	end,
};

local cellEvents = {
	OnEnter = function(table, cellFrame, rowFrame, rowData, columnData, rowIndex)
		table:SetHighLightColor(rowFrame, table.stdUi.config.tables.hover);
		return true;
	end,

	OnLeave = function(table, cellFrame, rowFrame, rowData, columnData, rowIndex)
		if rowIndex ~= table.selected or not table.selectionEnabled then
			table:SetHighLightColor(rowFrame, nil);
		end

		return true;
	end,

	OnClick = function(table, cellFrame, rowFrame, rowData, columnData, rowIndex, button)
		if button == 'LeftButton' then
			if table:GetSelection() == rowIndex then
				table:ClearSelection();
			else
				table:SetSelection(rowIndex);
			end

			return true;
		end
	end,
};

local headerEvents = {
	OnClick = function(table, columnFrame, columnHeadFrame, columnIndex, button, ...)
		if button == 'LeftButton' then

			local columns = table.columns;
			local column = columns[columnIndex];

			if not column.sortable then
				return false;
			end

			-- clear sort for other columns
			for i, _ in ipairs(columnHeadFrame.columns) do
				if i ~= columnIndex then
					columns[i].sort = nil;
				end
			end

			local sortOrder = 'asc';

			if not column.sort and column.defaultSort then
				-- sort by columns default sort first;
				sortOrder = column.defaultSort;
			elseif column.sort and column.sort:lower() == 'asc' then
				sortOrder = 'dsc';
			end

			column.sort = sortOrder;
			table:SortData();

			return true;
		end
	end
};

local ScrollDictionaryUpdateFn = function(self)
	self:Refresh();
end

local ScrollDictionaryOnVerticalScroll = function(self, offset)
	local scrollDict = self.panel;
	-- LS: putting st:Refresh() in a function call passes the st as the 1st arg which lets you
	-- reference the st if you decide to hook the refresh
	scrollDict:DoVerticalScroll(offset, scrollDict.rowHeight, ScrollDictionaryUpdateFn);
end

function StdUi:ScrollDictionary(parent, columns, numRows, rowHeight, config)
	local scrollDict = self:FauxScrollFrame(parent, 100, 100, rowHeight or 15);
	local scrollFrame = scrollDict.scrollFrame;

	scrollDict.config = config;

	scrollDict.stdUi = self;
	scrollDict.numberOfRows = numRows or 12;
	scrollDict.rowHeight = rowHeight or 15;
	scrollDict.columns = columns;
	scrollDict.data = {};
	scrollDict.sortedData = {};
	scrollDict.cellEvents = cellEvents;
	scrollDict.headerEvents = headerEvents;
	scrollDict.highlightedRows = {};

	-- Add all methods
	for methodName, method in pairs(methods) do
		scrollDict[methodName] = method;
	end

	scrollFrame:SetScript('OnVerticalScroll', ScrollDictionaryOnVerticalScroll);
	scrollDict:UpdateSortedData();
	scrollDict:SortData();
	scrollDict:SetColumns(scrollDict.columns);
	scrollDict:UpdateSortArrows();
	scrollDict:RegisterEvents(scrollDict.cellEvents, scrollDict.headerEvents);
	-- no need to assign it once again and override all column events

	return scrollDict;
end

StdUi:RegisterModule(module, version);