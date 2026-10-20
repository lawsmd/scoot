--------------------------------------------------------------------------------
-- forever/chat/configpage.lua
-- The Settings page under Chat (nav key chatSettings): Blizzard's Chat Config
-- window on the framework's controls, over the model in config.lua. A Window
-- selector first; a line and a Reload button while a change waits on the
-- reload; then tabs in Blizzard's order, Chat, Channels and Other, with
-- Combat Log on the combat log window as a placeholder until its pass; each
-- tab is boxed groups of toggle-and-swatch rows read off Blizzard's own
-- tables; Chat Defaults and Reset Chat Positions close the page. Loads on
-- retail too, where the page writes Blizzard's live windows.
--------------------------------------------------------------------------------

local addonName, addon = ...

local CR = addon.ChatReplica
local Config = CR.Config
local SettingsBuilder = addon.UI.SettingsBuilder

local NAV_KEY = CR.CONFIG_NAV_KEY

-- The window picker: a field a quarter larger than a row's, and wider.
local PICKER_SCALE = 1.25
local PICKER_WIDTH = 340

-- The arrows and the X beside a channel row.
local GLYPH_UP = "UI-HUD-ActionBar-PageUpArrow-Up"
local GLYPH_DOWN = "UI-HUD-ActionBar-PageDownArrow-Up"
local GLYPH_LEAVE = "common-icon-delete"
local GLYPH_SIZE = 16
local GLYPH_GAP = 6

local label = Config.Label

local activeBuilder -- the page's builder while it is drawn

--- A write that changes what waits on the reload re-draws the page, so the
--- reload line follows; one that does not leaves the page as it is.
local function write(builder, fn)
    local before = Config.PendingCount()
    fn()
    if Config.PendingCount() ~= before then builder:DeferredRefreshAll() end
end

--------------------------------------------------------------------------------
-- The boxes
--------------------------------------------------------------------------------

--- One of Blizzard's rows: a row Blizzard hides is skipped, a blank one is
--- a dim line, Additional Colors a swatch alone, the rest a toggle with
--- its swatch, the swatch shown while off since the color is global.
local function addRow(inner, builder, row, id)
    if row.hidden then return end
    if row.blank then
        inner:AddDescription(row.label, { dim = true })
    elseif row.swatchOnly then
        inner:AddColorPicker({
            label = row.label, hasAlpha = false,
            get = function() return Config.Color(row.colorKey) end,
            set = function(r, g, b) Config.SetColor(row.type, r, g, b) end,
        })
    else
        inner:AddToggleColorPicker({
            label = row.label, hasAlpha = false, swatchWhenOff = "shown",
            isDisabled = row.disabled and function() return true end or nil,
            get = function() return Config.Groups(id)[row.group] == true end,
            set = function(on) write(builder, function() Config.SetGroup(id, row.group, on) end) end,
            getColor = function() return Config.Color(row.colorKey) end,
            setColor = function(r, g, b) Config.SetColor(row.type, r, g, b) end,
        })
    end
end

local function addRows(inner, builder, section, id)
    for _, row in ipairs(Config.Rows(section)) do
        addRow(inner, builder, row, id)
    end
end

local function addSection(tab, builder, section, id)
    tab:AddSubPanel({
        componentId = NAV_KEY, sectionKey = section.key,
        title = label(section.header, section.fallback),
        buildContent = function(_, inner)
            addRows(inner, builder, section, id)
            inner:Finalize()
        end,
    })
end

local function sectionsTab(tab, builder, id, tabKey)
    for _, section in ipairs(Config.SECTIONS) do
        if section.tab == tabKey then addSection(tab, builder, section, id) end
    end
    tab:Finalize()
end

--------------------------------------------------------------------------------
-- Channels
--------------------------------------------------------------------------------

--- Up, down and leave, left of the row's swatch. Up and down swap the slot
--- with its neighbour, blank or not, as Blizzard's arrows do.
local function addGlyphs(row, builder, ch, canUp, canDown)
    local Controls = addon.UI.Controls
    local anchor = row._swatch
    local function glyph(atlas, tooltip, onClick)
        local btn = Controls:CreateGlyphButton({ parent = row, atlas = atlas, tooltip = tooltip, size = GLYPH_SIZE, shown = true })
        btn:SetPoint("RIGHT", anchor, "LEFT", -GLYPH_GAP, 0)
        btn:SetScript("OnClick", onClick)
        anchor = btn
    end
    if ch.canLeave then
        glyph(GLYPH_LEAVE, "Leave channel", function()
            Config.LeaveChannel(ch.id)
            builder:DeferredRefreshAll()
        end)
    end
    if canDown then
        glyph(GLYPH_DOWN, "Move down", function()
            if Config.SwapChannels(ch.id, ch.id + 1) then builder:DeferredRefreshAll() end
        end)
    end
    if canUp then
        glyph(GLYPH_UP, "Move up", function()
            if Config.SwapChannels(ch.id, ch.id - 1) then builder:DeferredRefreshAll() end
        end)
    end
end

local function channelsTab(tab, builder, id)
    local list = Config.ChannelList()
    if #list == 0 then
        tab:AddDescription("You are in no chat channel.", { justify = "CENTER" })
        tab:Finalize()
        return
    end
    local Controls = addon.UI.Controls
    local last = list[#list].id
    tab:AddSubPanel({
        componentId = NAV_KEY, sectionKey = "channels",
        title = "Channels",
        buildContent = function(_, inner)
            for _, ch in ipairs(list) do
                if ch.blank then
                    inner:AddDescription(ch.label, { dim = true })
                else
                    local key = "channel" .. ch.id
                    inner:AddToggleColorPicker({
                        key = key,
                        label = ch.label, hasAlpha = false, swatchWhenOff = "shown",
                        isDisabled = ch.disabled and function() return true end or nil,
                        get = function() return Config.HasChannel(id, ch.name) end,
                        set = function(on) write(builder, function() Config.SetChannel(id, ch.name, on) end) end,
                        getColor = function() return Config.Color(ch.colorKey) end,
                        setColor = function(r, g, b) Config.SetColor(ch.colorKey, r, g, b) end,
                    })
                    local row = inner:GetControl(key)
                    if row and row._swatch and Controls and Controls.CreateGlyphButton then
                        addGlyphs(row, builder, ch, ch.id > 1, ch.id < last)
                    end
                end
            end
            inner:Finalize()
        end,
    })
    tab:Finalize()
end

local function combatLogTab(tab)
    tab:AddDescription("The combat log's filters come in a later pass.", { justify = "CENTER" })
    tab:Finalize()
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

local function windowOptions()
    local windows = Config.Windows()
    local values, order = {}, {}
    for _, w in ipairs(windows) do
        local key = tostring(w.id)
        values[key] = w.name
        order[#order + 1] = key
    end
    return windows, values, order
end

local function Render(panel, scrollContent)
    panel:ClearContent()
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    activeBuilder = builder
    builder:SetOnRefresh(function() Render(panel, scrollContent) end)

    Config.EnsureSnapshot()
    local windows, values, order = windowOptions()
    local id = Config.SelectedWindow(windows)
    builder:AddSelector({
        label = "Window", centered = true, sizeScale = PICKER_SCALE, width = PICKER_WIDTH,
        values = values, order = order,
        get = function() return tostring(id) end,
        set = function(v)
            Config.SetSelectedWindow(tonumber(v))
            builder:DeferredRefreshAll()
        end,
    })

    local pending = Config.PendingCount()
    if pending > 0 then
        local text = pending == 1 and "%d change takes effect when the interface reloads."
            or "%d changes take effect when the interface reloads."
        builder:AddDescription(string.format(text, pending), { justify = "CENTER" })
        builder:AddButtonRow({ justify = "CENTER", buttons = { { text = "Reload", onClick = Config.Reload } } })
    end

    local tabs = {
        { key = "chat", label = label("CHAT", "Chat") },
        { key = "channels", label = "Channels" },
        { key = "other", label = label("OTHER", "Other") },
    }
    if Config.CombatLogAvailable(id) then
        tabs[#tabs + 1] = { key = "combatLog", label = "Combat Log" }
    end
    builder:AddTabbedSection({
        tabs = tabs,
        componentId = NAV_KEY,
        sectionKey = "config",
        buildContent = {
            chat = function(_, tab) sectionsTab(tab, builder, id, "chat") end,
            channels = function(_, tab) channelsTab(tab, builder, id) end,
            other = function(_, tab) sectionsTab(tab, builder, id, "other") end,
            combatLog = function(_, tab) combatLogTab(tab) end,
        },
    })

    builder:AddButtonRow({
        buttons = {
            { text = label("CHAT_DEFAULTS", "Chat Defaults"), onClick = Config.ResetChat },
            { text = label("RESET_CHAT_WINDOW_POSITIONS", "Reset Chat Positions"), onClick = Config.RedockWindows },
        },
    })

    builder:Finalize()
end

--- A change Blizzard announces while the page is shown re-draws it.
local function refresh()
    if not activeBuilder then return end
    local panel = addon.UI.SettingsPanel
    local shown = panel and panel.frame and panel.frame:IsShown()
    if shown and panel._currentBuilder == activeBuilder then activeBuilder:DeferredRefreshAll() end
end

for _, event in ipairs({ "CHANNEL_UI_UPDATE", "CHAT_REGIONAL_STATUS_CHANGED", "UPDATE_CHAT_WINDOWS" }) do
    addon.Events.On(CR.OWNER .. "ConfigPage", event, function()
        Config.Invalidate()
        refresh()
    end)
end

addon.UI.SettingsPanel:RegisterRenderer(NAV_KEY, Render)
