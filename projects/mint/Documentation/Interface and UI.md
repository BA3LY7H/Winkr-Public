# Interface & UI System

> MINT's settings window, widget library, and page-building API.

**Key Sources:**
- `Engine/Interface/API/API.lua` — Interface class, main window, quickbar
- `Engine/Interface/API/Page.lua`, `Row.lua`, `Element.lua` — Page-building API
- `Engine/Interface/StdUi*.lua` — Widget factory and layout engine
- `Engine/Interface/widgets/` — Individual widget implementations
- `Engine/Interface/pages/` — Built-in settings pages

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│  Interface (API/API.lua)                                  │
│  ┌────────────┐  ┌─────────────┐  ┌───────────────────┐ │
│  │  Quickbar   │  │  TabPanel   │  │  Page/Row/Element │ │
│  │  (toggles)  │  │  (window)   │  │  (builder API)    │ │
│  └────────────┘  └─────────────┘  └───────────────────┘ │
│                         │                                 │
│              ┌──────────▼──────────┐                      │
│              │      StdUi          │                      │
│              │  Widget Factory     │                      │
│              │  Layout Engine      │                      │
│              │  Position Helpers   │                      │
│              └─────────────────────┘                      │
│                         │                                 │
│              ┌──────────▼──────────┐                      │
│              │  Widgets (20+)      │                      │
│              │  Button, Checkbox,  │                      │
│              │  Dropdown, Slider…  │                      │
│              └─────────────────────┘                      │
└──────────────────────────────────────────────────────────┘
```

---

## Interface Class

**File:** `Engine/Interface/API/API.lua`

The central controller for MINT's UI. Created once during initialization.

### Constructor: `Interface:New()`

1. Creates font objects (`MintFontSmall`, `MintFontNormal`, `MintFontLarge`)
2. Creates a `StdUi` instance with the stylesheet from `Constants.Stylesheet`
3. Initializes the builder queue (`builder.pages`, `builder.quickbuttons`)
4. Registers default quickbar buttons (Toggle, CDs, Kicks, Defs, Dispels, Purge — class-dependent)

### Key Properties

| Property | Type | Description |
|----------|------|-------------|
| `factory` | StdUi | Widget factory instance |
| `window` | Frame | Main options window |
| `quickbar` | Frame | Draggable toggle bar |
| `menu_panel` | TabPanel | Vertical tab panel in main window |
| `pages` | table | `{key = frame}` map of page frames |
| `builder` | table | Queue of pages/buttons to build |
| `toggles` | table | Checkbox references |
| `dropdowns` | table | Dropdown references |
| `sliders` | table | Slider references |
| `quickbuttons` | table | QuickButton references |
| `tables` | table | ScrollTable references |
| `buttons` | table | Button references |
| `labels` | table | Label references |
| `ui_config` | table | `Settings.global.ui` — persisted UI state |

### Key Methods

| Method | Description |
|--------|-------------|
| `AddQuickButton(icon, name, label, cb)` | Queue a quickbar button for building |
| `BuildQuickbar()` | Create the draggable quickbar frame with all queued buttons |
| `BuildOptions()` | Create the main window, TabPanel, and invoke all page callbacks |
| `InitPage(callback)` | Execute a callback with `self` (the Interface instance) |
| `TriggerRefresh()` | Refresh UI state after config changes |
| `RegisterRefreshCallback(cb)` | Register a function to run on refresh |

### Quickbar

The quickbar is a draggable panel with icon toggle buttons. Each button fires an event via `mint.events:TriggerEvent()`.

**Persistence:**
- Position saved to `Settings.global.ui.quickbar_anchor`
- Button toggle states saved to `Settings.global.ui.button_states`
- Both persisted via `Settings:SaveGlobal()` on change

---

## Page Builder API

The Page/Row/Element API provides a declarative way to define settings pages. Pages are queued during init and built when `BuildOptions()` runs.

### Page (`Engine/Interface/API/Page.lua`)

```lua
-- Spec-based page (rotation settings)
local page = Interface.Page:New(name, class, spec, is_custom_page, callback)

-- Custom page (general settings, keybinds, etc.)
local page = Interface.Page:NewCustom(name, key, callback)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | string | Display title in tab |
| `class` | string | Class identifier (e.g., `"hunter"`) |
| `spec` | string | Spec identifier (e.g., `"beastmastery"`) |
| `key` | string | For custom pages, the unique key |
| `is_custom_page` | boolean | If true, uses callback for custom rendering |
| `callback` | function | `function(interface)` called during `BuildOptions()` |

**Key Methods:**

| Method | Description |
|--------|-------------|
| `page:AddRow(mt, mr, mb, ml)` | Add a row with margins. Returns a `Row` |
| `page:AddLayout(layout)` | Set a declarative layout table (auto-built by StdUi Builder) |
| `page:AddDefaults(defaults)` | Register default values via `Settings:VerifyDefaults(key, defaults)` |

The `key` for spec-based pages is formatted as `class.spec` (e.g., `"hunter.beastmastery"`).

### Row (`Engine/Interface/API/Row.lua`)

```lua
local row = page:AddRow(0, 0, 5, 0)  -- top, right, bottom, left margins
```

**Methods:**

| Method | Description | Returns |
|--------|-------------|---------|
| `row:AddToggle({ name, default, cols })` | Checkbox toggle | Element |
| `row:AddDropDown({ name, options, width, multi, placeholder, cols })` | Dropdown selector | Element |
| `row:AddSlider({ name, default, min, max, width, cols })` | Numeric slider | Element |

### Element (`Engine/Interface/API/Element.lua`)

Elements are lightweight handles that proxy to the actual StdUi widgets stored in `Interface.toggles`, `Interface.sliders`, `Interface.dropdowns`.

```lua
local toggle = row:AddToggle({ name = "smart_target", default = true })

-- Later, in rotation code:
if toggle:IsChecked() then ... end
```

**Methods:**

| Method | Widget Type | Returns |
|--------|-------------|---------|
| `element:IsChecked()` | Toggle/Checkbox | `boolean` |
| `element:GetValue()` | Slider | `number` (falls back to `config.default`) |
| `element:IsSelected(value)` | Dropdown | `boolean` |
| `element:GetSelected()` | Dropdown | Selected value |

Element keys are formatted as `{page.key}_{element.name}` (e.g., `"hunter.beastmastery"` + `"smart_target"` → `"hunter.beastmastery_smart_target"`).

---

## Declarative Layout System

Pages can use a **declarative layout table** instead of manual widget creation. The table is processed by `StdUi:BuildWindow()`.

### Layout Table Structure

```lua
local layout = {
    layoutConfig = { padding = { top = 15 } },
    database = settings.profile.general,  -- auto-bind values here
    rows = {
        {   -- Row 1
            header = {
                type = 'header',
                label = 'General Settings'
            }
        },
        {   -- Row 2
            margins = { margin = { top = 10 } },
            smart_target = {
                key = 'smart_target',        -- database key
                type = 'checkbox',
                label = 'Smart Targeting',
                tooltip = 'Auto-select target.',
                column = 6,                  -- out of 12-col grid
                order = 1                    -- render order in row
            },
        },
    },
}

page:AddLayout(layout)
```

### Element Types Available in Layouts

| Type | Description | Key Options |
|------|-------------|-------------|
| `checkbox` | Toggle with label | `label`, `tooltip` |
| `editBox` | Single-line text input | |
| `multiLineBox` | Multi-line text area | |
| `dropdown` | Selection dropdown | `options`, `initialValue`, `multi`, `assoc` |
| `playerDropdown` | Auto-updating party/raid dropdown | `options`, `initialValue`, `multi`, `assoc` |
| `autocomplete` | Searchable input | `validator`, `transformer`, `items` |
| `slider` / `sliderWithBox` | Numeric slider with edit box | `min`, `max`, `precision` |
| `color` | Color picker | `color` |
| `button` | Clickable button | `text`, `onClick` |
| `header` | Section header text | `label` |
| `subheader` | Sub-section header | `label` |
| `label` | Static text | `label`, `size` |
| `texture` | Image/icon display | `texture`, `width`, `height` |
| `panel` | Container frame | |
| `scroll` | Scroll frame container | `scrollChild` |
| `fauxScroll` | Virtual scroll frame | `displayCount`, `lineHeight`, `scrollChild` |
| `tab` | Nested tab panel | `tabs`, `vertical`, `buttonWidth`, `buttonHeight` |
| `custom` | User-defined | `createFunction(frame, row, info, dataKey, db)` |

### Database Binding

When `database` is set in the layout, the Builder:
1. Reads initial values from `database[key]`
2. Sets each widget's value from the database
3. Binds `OnValueChanged` to write back: `database[key] = newValue`

The Builder supports **dot-notation keys** (e.g., `"healing.threshold"`) for nested database paths.

---

## StdUi Widget System

**File:** `Engine/Interface/StdUi.lua` + module files

StdUi is a modular widget factory. Each module registers via `StdUi:RegisterModule(name, version)` with built-in version gating to prevent downgrades.

### Core Methods

| Method | Description |
|--------|-------------|
| `StdUi:NewInstance()` | Create a new StdUi instance with independent config |
| `StdUi:RegisterWidget(name, func)` | Register a custom widget constructor |
| `StdUi:InitWidget(widget)` | Mark frame as widget, add `GetChildrenWidgets()` |
| `StdUi:SetObjSize(obj, w, h)` | Set width/height (nil-safe) |
| `StdUi:ApplyBackdrop(frame, type, border)` | Apply themed backdrop from config |
| `StdUi:MakeDraggable(frame, handle)` | Enable drag-to-move |
| `StdUi:MakeResizable(frame, direction)` | Enable resize from edge/corner |

### Modules

| Module | Version | File | Purpose |
|--------|---------|------|---------|
| Config | 5 | `StdUiConfig.lua` | Theme/stylesheet configuration |
| Position | 2 | `StdUiPosition.lua` | Glue-based positioning helpers |
| Util | 12 | `StdUiUtil.lua` | Validators, formatters, table utilities |
| Layout | 3 | `StdUiLayout.lua` | 12-column grid layout engine |
| Grid | 4 | `StdUiGrid.lua` | List and grid rendering |
| Builder | 6 | `StdUiBuilder.lua` | Declarative layout builder |
| Basic | 4 | `widgets/Basic.lua` | Frame, Panel, Texture |
| Label | 3 | `widgets/Label.lua` | FontString, Label, Header |
| Button | 6 | `widgets/Button.lua` | Button, SquareButton, DropdownButton |
| Checkbox | 5 | `widgets/Checkbox.lua` | Checkbox, Radio, RadioGroup |
| Dropdown | 4 | `widgets/Dropdown.lua` | Dropdown, PlayerDropdown |
| EditBox | 9 | `widgets/EditBox.lua` | EditBox, NumericBox, MultiLineBox |
| Slider | 7 | `widgets/Slider.lua` | Slider, SliderWithBox, ScrollBar |
| Scroll | 6 | `widgets/Scroll.lua` | ScrollFrame, FauxScrollFrame, HybridScrollFrame |
| ScrollTable | 7 | `widgets/ScrollTable.lua` | Sortable data tables |
| Tab | 4 | `widgets/Tab.lua` | TabPanel, ScrollTabPanel |
| Window | 6 | `widgets/Window.lua` | Window, Dialog, Confirm |
| Tooltip | 3 | `widgets/Tooltip.lua` | Tooltip, FrameTooltip |
| Autocomplete | 5 | `widgets/Autocomplete.lua` | Searchable input with dropdown suggestions |
| ColorPicker | 7 | `widgets/ColorPicker.lua` | ColorPicker, ColorInput |
| ContextMenu | 4 | `widgets/ContextMenu.lua` | Right-click context menus |
| ProgressBar | 4 | `widgets/ProgressBar.lua` | StatusBar-based progress display |
| ScrollDictionary | 1 | `widgets/ScrollDictionary.lua` | Key-value scrollable list |
| Spell | 3 | `widgets/Spell.lua` | Spell input with validation |
| Table | 2 | `widgets/Table.lua` | Static data table |

---

## Widget Reference

### Frame / Panel
```lua
local frame = stdUi:Frame(parent, width, height)
local panel = stdUi:Panel(parent, width, height)      -- with panel backdrop
local titled = stdUi:PanelWithTitle(parent, w, h, "Title")
```

### Button
```lua
local btn = stdUi:Button(parent, width, height, "Click Me")
btn:SetScript('OnClick', function() ... end)
```
Methods: `SetFontSize(size)`, auto-sizing via `stdUi:ButtonAutoWidth(btn, padding)`.

Variants: `HighlightButton`, `SquareButton` (icon buttons with predefined coordinates: UP, DOWN, LEFT, RIGHT, DELETE), `DropdownButton`.

### Checkbox
```lua
local cb = stdUi:Checkbox(parent, "Enable Feature", width, height, "Tooltip text")
cb:SetChecked(true)
cb.OnValueChanged = function(self, isChecked) ... end
```
Methods: `SetChecked(flag, internal)`, `GetChecked()`, `SetValue(v)`, `GetValue()`, `AutoWidth()`, `Enable()`, `Disable()`.

The `internal` flag on `SetChecked` suppresses `OnValueChanged`.

Variants: `IconCheckbox(parent, icon, text, w, h, iconSize)`, `Radio(parent, text, groupName, w, h)`.

### Dropdown
```lua
local options = {
    { text = "Option A", value = "a" },
    { text = "Option B", value = "b" },
}
local dd = stdUi:Dropdown(parent, 200, 30, options, initialValue, multi, assoc)
dd:SetPlaceholder("-- Select --")
dd.OnValueChanged = function(self, value, text) ... end
```
Methods: `SetValue(v, text)`, `GetValue()`, `SetOptions(opts)`, `SetPlaceholder(text)`, `ShowOptions()`, `HideOptions()`, `ToggleValue(v, state)` (multi-select), `IsSelected(v)`.

**PlayerDropdown:** Auto-updates options with party/raid members via `GROUP_ROSTER_UPDATE`.

### Slider / SliderWithBox
```lua
local slider = stdUi:SliderWithBox(parent, width, 32, value, min, max)
slider:SetPrecision(1)
slider:SetValue(50)
slider.OnValueChanged = function(self, value) ... end
```
Methods: `SetValue(v)`, `GetValue()`, `SetMinMaxValues(min, max)`, `SetPrecision(n)`, `SetValueStep(step)`.

### EditBox
```lua
local edit = stdUi:EditBox(parent, width, height, "default text")
edit.OnValueChanged = function(self, value) ... end
```
Has built-in OK button that appears on text change. Validates on Enter press.

Variants: `SimpleEditBox` (no validation), `NumericBox` (numeric only, min/max), `MoneyBox`, `MultiLineBox`, `SearchEditBox`.

### ScrollTable
```lua
local columns = {
    { name = "Name", width = 200, index = "name" },
    { name = "Value", width = 100, index = "value", sortable = true },
    { name = "Icon", width = 40, index = "icon", format = "icon" },
}
local st = stdUi:ScrollTable(parent, columns, numRows, rowHeight, config)
st:SetData(data)
st:EnableSelection(true)
```
Column `format` options: `icon`, `money`, `moneyShort`, `time`, `number`, `checkbox`, `bindCheckbox`, `iconCheckbox`, `dropdown`, `custom` (requires `renderer`), or a function. Omit `format` for plain text.

Cell-level event hooks: `OnEnter`, `OnLeave`, `OnClick`. Supports sortable columns and row selection.

### TabPanel
```lua
local tabs = {
    { name = "general", title = "General" },
    { name = "advanced", title = "Advanced" },
}
local tp = stdUi:TabPanel(parent, width, height, tabs, vertical, buttonWidth, buttonHeight)
local tab = tp:GetTabByName("general")
-- tab.frame is the content frame for that tab
```
Methods: `SelectTab(name)`, `GetTabByName(name)`, `GetSelectedTab()`, `Update(newTabs)`, `HideAllFrames()`.

Variant: `ScrollTabPanel` — each tab frame is a `FauxScrollFrame`.

### Window / Dialog
```lua
local win = stdUi:Window(parent, 700, 500, "Title")
-- Draggable, has close button, clamped to screen

local dlg = stdUi:Confirm("Title", "Are you sure?", {
    ok = { text = "OK", onClick = function() ... end },
    cancel = { text = "Cancel", onClick = function(self) self.window:Hide() end },
})
```

### Label / Header
```lua
local label = stdUi:Label(parent, "Text", fontSize, inherit, width, height, colorType, tooltip)
local header = stdUi:Header(parent, "Section Title")
local sub = stdUi:SubHeader(parent, "Subsection")
stdUi:AddLabel(parent, widget, "Label Text", "TOP")  -- position: TOP, RIGHT, BOTTOM, LEFT
```

### QuickButton
```lua
local qb = mint.QuickButton:New(parent, 50, 50, "Interface\\Icons\\icon_name", "ButtonName", callback)
```
Toggle button with dimmed (inactive) and bright (active) icon states. Tracks `state.active`.

### ColorInput
```lua
local ci = stdUi:ColorInput(parent, "Label", width, height, { r=1, g=0, b=0, a=1 })
ci.OnValueChanged = function(self, color) ... end
```
Clickable color swatch that opens a full `ColorPicker` dialog. Methods: `SetColor(colorTable)`, `GetColor(type)` (returns `{r,g,b,a}` by default, or `r,g,b,a` with `type="rgba"`).

### ProgressBar
```lua
local bar = stdUi:ProgressBar(parent, width, height, vertical)
bar:SetMinMaxValues(0, 100)
bar:SetValue(75)
```
StatusBar-based progress indicator. Displays percentage text by default. Override `bar:TextUpdate(min, max, value)` to customize.

---

## Position Helpers

**File:** `Engine/Interface/StdUiPosition.lua`

All `StdUi:Glue*` methods attach one frame relative to another using WoW anchor points.

| Method | Behavior |
|--------|----------|
| `GlueBelow(obj, ref, x, y, align)` | Below reference. `align`: `"LEFT"`, `"RIGHT"`, or center |
| `GlueAbove(obj, ref, x, y, align)` | Above reference |
| `GlueTop(obj, ref, x, y, align)` | Aligned to top of reference |
| `GlueBottom(obj, ref, x, y, align)` | Aligned to bottom of reference |
| `GlueRight(obj, ref, x, y, inside)` | Right of (or inside-right if `inside=true`) |
| `GlueLeft(obj, ref, x, y, inside)` | Left of (or inside-left if `inside=true`) |
| `GlueAfter(obj, ref, topX, topY, botX, botY)` | To the right, spanning height |
| `GlueBefore(obj, ref, topX, topY, botX, botY)` | To the left, spanning height |
| `GlueAcross(obj, ref, tlX, tlY, brX, brY)` | Stretch across reference (TOPLEFT + BOTTOMRIGHT) |
| `GlueOpposite(obj, ref, x, y, anchor)` | Opposite side of given anchor |

---

## Layout Engine

**File:** `Engine/Interface/StdUiLayout.lua`

A **12-column grid** layout system inspired by Bootstrap.

### Usage

```lua
stdUi:EasyLayout(parentFrame, {
    gutter = 10,
    columns = 12,
    padding = { top = 0, right = 10, left = 10, bottom = 10 }
})

local row = parentFrame:AddRow({ margin = { top = 5, bottom = 5 } })
row:AddElement(widget1, { column = 6 })   -- half width
row:AddElement(widget2, { column = 6 })   -- half width

parentFrame:DoLayout()  -- compute positions
```

### Row Options

| Option | Type | Description |
|--------|------|-------------|
| `column` | number | Columns to occupy (1–12) |
| `fullSize` | boolean | Stretch to fill entire parent |
| `fullHeight` | boolean | Extend to bottom of parent |
| `margin` | table | `{top, right, bottom, left}` |

### `AddElements` Shortcut

```lua
row:AddElements(widget1, widget2, widget3, { column = 'even' })
-- Auto-calculates: 12 / 3 = 4 columns each
```

---

## Configuration & Theming

**File:** `Engine/Interface/StdUiConfig.lua`

The default theme uses a dark panel style with gold accents. Configuration is stored in `stdUi.config`:

```lua
config = {
    font = {
        family = "TeaFontNormal",
        size = 10,
        titleSize = 14,
        color = {
            normal = { r=1, g=0.82, b=0, a=1 },      -- Gold
            disabled = { r=1, g=1, b=1, a=1 },        -- White
            header = { r=1, g=0.9, b=0, a=1 },        -- Bright gold
        }
    },
    backdrop = {
        texture = [[Interface\Buttons\WHITE8X8]],
        panel = { r=0.0588, g=0.0588, b=0, a=0.8 },  -- Near-black
        button = { r=0.20, g=0.20, b=0.20, a=1 },
        border = { r=0, g=0, b=0, a=1 },
        -- ... more backdrop types
    },
}
```

MINT overrides this via `Constants.Stylesheet` when creating the Interface's StdUi instance.

---

## Database / Persistence

Settings persistence is handled by the `Settings` system (see [state-and-data.md](state-and-data.md)).

**How widgets bind to settings:**

1. **Declarative layouts:** Set `database = settings.profile.general` in the layout table. The Builder reads initial values and writes changes automatically.
2. **Manual binding:** Use `widget.OnValueChanged` to write to `Settings`:
   ```lua
   checkbox.OnValueChanged = function(self, value)
       settings.profile.general.smart_target = value
       Settings:Save()
   end
   ```

**UI-specific persistence** (quickbar position, button states) uses `Settings.global.ui`, saved via `Settings:SaveGlobal()`.

**Defaults registration:**

```lua
page:AddDefaults({
    smart_target = true,
    indicator_color = "cyan",
    indicator_opacity = 80,
})
-- Calls Settings:VerifyDefaults(page.key, defaults) under the hood
```

---

## Creating a New Settings Page

### Method 1: Declarative Layout (Recommended for simple pages)

```lua
-- In your rotation's settings file
local settings = mint.Settings
local Interface = mint.Interface

-- 1. Create the page
local page = Interface.Page:New("My Spec", "class", "spec")

-- 2. Register defaults
page:AddDefaults({
    use_cooldowns = true,
    burst_threshold = 80,
    interrupt_mode = "smart",
})

-- 3. Define layout
local layout = {
    layoutConfig = { padding = { top = 15 } },
    database = settings.profile["class.spec"],
    rows = {
        {
            header = {
                type = 'header',
                label = 'Rotation Settings'
            }
        },
        {
            use_cooldowns = {
                key = 'use_cooldowns',
                type = 'checkbox',
                label = 'Use Cooldowns',
                tooltip = 'Enable offensive cooldown usage.',
                column = 6,
                order = 1
            },
            burst_threshold = {
                key = 'burst_threshold',
                type = 'slider',
                label = 'Burst HP Threshold',
                min = 0, max = 100,
                precision = 1,
                column = 6,
                order = 2
            },
        },
        {
            interrupt_mode = {
                key = 'interrupt_mode',
                type = 'dropdown',
                label = 'Interrupt Mode',
                options = {
                    { text = "Smart", value = "smart" },
                    { text = "Always", value = "always" },
                    { text = "Never", value = "never" },
                },
                column = 6,
                order = 1
            },
        },
    },
}

-- 4. Attach layout
page:AddLayout(layout)
```

### Method 2: Custom Callback (For complex pages like Keybinds)

```lua
Interface.Page:NewCustom("My Page", "my_page", function(self)
    -- self = the Interface instance
    local factory = self.factory

    -- Apply layout engine to the page frame
    factory:EasyLayout(self.pages.my_page, { padding = { top = 15 } })

    -- Create widgets manually
    local checkbox = factory:Checkbox(self.pages.my_page, "Enable Feature")
    local button = factory:Button(self.pages.my_page, 100, 20, "Do Thing")

    button:SetScript('OnClick', function()
        -- custom logic
    end)

    -- Add to layout rows
    local row1 = self.pages.my_page:AddRow({ margin = { top = 10 } })
    row1:AddElement(checkbox, { column = 6 })
    row1:AddElement(button, { column = 6 })

    -- Finalize layout
    self.pages.my_page:DoLayout()
end)
```

### Pattern Checklist

1. ✅ Create page with `Page:New()` or `Page:NewCustom()`
2. ✅ Register defaults with `page:AddDefaults()`
3. ✅ Define layout table OR use callback for manual construction
4. ✅ Use 12-column grid: `column = N` per element
5. ✅ Set `order` for element rendering within a row
6. ✅ Call `DoLayout()` at the end of custom callbacks
7. ✅ Store widget references in `Interface.toggles`, `Interface.dropdowns`, etc. for cross-system access

---

## Utility Functions

**File:** `Engine/Interface/StdUiUtil.lua`

| Function | Description |
|----------|-------------|
| `StdUi.Util.editBoxValidator(self)` | Default validator — accepts any text |
| `StdUi.Util.numericBoxValidator(self)` | Validates numeric input with min/max |
| `StdUi.Util.spellValidator(self)` | Validates spell name/ID, sets icon |
| `StdUi.Util.formatMoney(money, excludeCopper)` | Formats copper amount to `Xg Xs Xc` |
| `StdUi.Util.parseMoney(text)` | Parses money string |
| `StdUi.Util.formatTime(totalTime)` | Formats to `Xd Xh Xm Xs` |
| `StdUi.Util.stripColors(text)` | Removes WoW color codes |
| `StdUi.Util.WrapTextInColor(text, r,g,b,a)` | Wraps text in color code |
| `StdUi.Util.tableMerge(default, new)` | Deep merge tables |
| `StdUi.Util.tableCount(tab)` | Count entries (handles non-sequential) |
| `StdUi.Util.orderedPairs(t)` | Iterate by `.order` field |
| `StdUi.Util.roundPrecision(value, precision)` | Round to N decimal places |
| `StdUi:MarkAsValid(frame, valid)` | Red border on invalid, normal on valid |
