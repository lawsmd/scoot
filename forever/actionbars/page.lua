--------------------------------------------------------------------------------
-- forever/actionbars/page.lua
-- The Action Bars 1-8 page under the Action Bars group (nav key
-- actionBarClusters, labelled Clusters until 17 October 2026): the settings
-- for one of Blizzard's eight action bars at a time, past what the Edit Mode
-- dialog holds. One line points at Edit Mode for the clusters; a centered
-- Action Bar selector, with no label, picks the bar;
-- under it a tabbed
-- section holds Layout/Sizing, Cooldown Text, Keybind Text and Visibility
-- (visibility.lua). A cluster's
-- own rows (Axis, Spacing, End Caps) and every edit that makes, fills or
-- empties a cluster stay in Edit Mode. The Layout/Sizing rows write the
-- bar's member in whichever cluster holds it, through the edits in
-- clusters.lua; a bar no cluster holds still takes its text settings.
--
-- The selected bar follows the Edit Mode subject (editmode.lua calls
-- Page.Follow), so Configure on a cluster's box opens this page on the bar
-- the dialog was editing, and a pick here moves the subject the same way.
-- The micro menu and bag bar have their own page (microbagspage.lua).
--
-- The text styles are the unpaired list: Blizzard's code writes the keybind
-- string with SetText, Show and Hide, and the engine writes the countdown,
-- so a Deep Shadow copy would follow neither. While nothing is stored the
-- controls show the font object's or the countdown string's own values,
-- which are what the button draws (text.lua).
--------------------------------------------------------------------------------

local _, addon = ...

local ActionBars = addon.ActionBars
local Clusters = ActionBars.Clusters
local EditMode = ActionBars.EditMode
local Text = ActionBars.Text
local DB = addon.DB
local SettingsBuilder = addon.UI.SettingsBuilder
local Helpers = addon.UI.Settings.Helpers

local Page = {}
ActionBars.Page = Page

local NAV_KEY = EditMode.NAV_KEY
Page.NAV_KEY = NAV_KEY

-- The bar picker: a field a quarter larger than a row's, and wider.
local PICKER_SCALE = 1.25
local PICKER_WIDTH = 340

local BARS = { "bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8" }
local BAR_SET = {}
for _, token in ipairs(BARS) do BAR_SET[token] = true end

local TABS = {
    { key = "layout", label = "Layout/Sizing" },
    { key = "cooldown", label = "Cooldown Text" },
    { key = "keybind", label = "Keybind Text" },
    { key = "visibility", label = "Visibility" },
}

local selected = "bar1" -- the bar the page edits, for the session
local activeBuilder -- the page's builder while it is drawn
local quiet = false -- a page control is mid-edit

-- Run an edit from a page control. The rebuild inside it asks the page to
-- refresh, which is refused while the page itself is writing; a structural
-- edit, one that adds or removes rows, re-renders after, deferred a frame
-- so the control that fired it finishes its own handler first.
local function edit(builder, fn, structural)
    quiet = true
    local ok, err = pcall(fn)
    quiet = false
    if not ok then error(err, 0) end
    if structural then builder:DeferredRefreshAll() end
end

-- The cluster holding a bar and the bar's index in it, or nil.
local function placement(token)
    local id = Clusters.Owner(token)
    local cluster = id and Clusters.Find(id)
    for i, m in ipairs(cluster and cluster.members or {}) do
        if m.identity == token then return id, i, cluster end
    end
    return nil
end

--- Select the bar the page edits; editmode.lua calls this when the subject
--- changes. A token outside the eight action bars is ignored.
function Page.Follow(token)
    if BAR_SET[token] then selected = token end
end

--------------------------------------------------------------------------------
-- Layout/Sizing
--------------------------------------------------------------------------------

local function layoutTab(tab, builder, token)
    local id, index, cluster = placement(token)
    if not id then
        tab:AddDescription(Clusters.IdentityLabel(token) .. " is in no cluster. Edit Mode places it.")
        tab:Finalize()
        return
    end
    local m = cluster.members[index]
    local labels = EditMode.Labels(cluster.axis ~= "horizontal")
    local count = Clusters.ButtonCount(token)
    local function field(name, default)
        return function()
            local c = Clusters.Find(id)
            local mm = c and c.members and c.members[index]
            local v = mm and mm[name]
            if v == nil then return default end
            return v
        end
    end
    local function write(name, structural)
        return function(v)
            edit(builder, function() Clusters.SetMemberField(id, index, name, v) end, structural)
        end
    end

    -- The next row's maximum follows this one, so the write re-renders.
    tab:AddSlider({ label = "Buttons", min = 1, max = count, step = 1, precision = 0,
        get = field("buttons", count), set = write("buttons", true) })
    tab:AddSlider({ label = labels.lines, min = 1, max = m.buttons or count, step = 1, precision = 0,
        get = field("lines", 1), set = write("lines") })
    tab:AddSelector({ label = "Alignment", values = labels.align, order = EditMode.ALIGN_ORDER,
        get = field("align", "center"), set = write("align") })
    local size = EditMode.RANGES.iconSize
    tab:AddSlider({ label = "Icon Size", min = size.min, max = size.max, step = size.step, precision = 0,
        minLabel = size.min .. "%", maxLabel = size.max .. "%", displaySuffix = "%",
        get = field("iconSize", 100), set = write("iconSize") })
    local padding = EditMode.RANGES.iconPadding
    tab:AddSlider({ label = "Icon Padding", min = padding.min, max = padding.max, step = padding.step,
        precision = 0, get = field("iconPadding", 2), set = write("iconPadding") })
    -- With the empty buttons hidden, the filled ones can pack toward one
    -- end or the middle of the bar; the pair greys out while they show.
    tab:AddToggleGateRow({ label = "Show Empty Buttons",
        gate = {
            get = function() return field("alwaysShowButtons", true)() and true or false end,
            set = write("alwaysShowButtons"),
        },
        toggle = { label = "Compact Filled Buttons",
            get = function() return field("compact", false)() and true or false end,
            set = write("compact"),
        },
        selector = { values = labels.compact, order = EditMode.ALIGN_ORDER,
            get = field("compactAlign", "center"), set = write("compactAlign"),
        },
    })
    tab:Finalize()
end

--------------------------------------------------------------------------------
-- Cooldown Text and Keybind Text
--------------------------------------------------------------------------------

-- The composite's field names are the stored field names, one to one.
local IDENTITY_MAP = {}
for _, f in ipairs({ "hidden", "fontFace", "style", "size", "color", "offsetX", "offsetY" }) do
    IDENTITY_MAP[f] = f
end

-- What the keybind controls show while nothing is stored: the template's
-- font object, Arial Narrow on every client the font families list.
local function keybindDefaults()
    local _, size = Text.FontObjectFont()
    local color = { 1, 1, 1, 1 }
    local fontObject = _G[Text.FONT_OBJECT]
    if fontObject then
        local r, g, b = fontObject:GetTextColor()
        color = { r, g, b, 1 }
    end
    return {
        fontFace = "ARIALN",
        size = size and math.floor(size + 0.5) or 12,
        style = Text.FontObjectStyle(),
        color = color,
    }
end

-- What the cooldown controls show while nothing is stored: the countdown
-- string's own size and outline, in Friz Quadrata, the client's default.
local function cooldownDefaults()
    local _, size, flags = Text.CooldownFont()
    return {
        fontFace = "FRIZQT__",
        size = size and math.floor(size + 0.5) or 16,
        style = Text.StyleOf(flags),
        color = { 1, 1, 1, 1 },
    }
end

local function textTab(tab, token, part, hideLabel, defaults)
    local get, set = Helpers.CreateFlatAccessors(
        function(f) return DB.Get(Text.Path(token, part, f)) end,
        function(f, value) DB.Set(Text.Path(token, part, f), value) end,
        IDENTITY_MAP)
    tab:AddTextStyleBlock({
        get = get, set = set, apply = function() Text.Refresh(token) end,
        defaults = defaults,
        hideToggle = { label = hideLabel },
        style = { order = Helpers.fontStyleOrder },
        size = { min = 6, max = 32, minLabel = "6", maxLabel = "32" },
        color = { kind = "plain" },
        offset = { range = 50, minLabel = "-50", maxLabel = "+50" },
    })
    tab:Finalize()
end

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------

-- Out of combat with no target the bar is at full opacity and the dynamic
-- layout decides, so the block has no Out of Combat slider.
local OPACITY_TOOLTIP = {
    tooltipTitle = "Opacity Priority",
    tooltipText = "In Combat takes precedence over With Target. With neither, the bar is at "
        .. "full opacity and the Dynamic Layout decides.",
}

--- The Visibility rows for one token, an action bar or a micro and bag
--- holder; the Micro & Bag page draws them too (microbagspage.lua).
function Page.VisibilityRows(tab, token)
    local Visibility = ActionBars.Visibility
    local function apply() Visibility.Apply(token) end

    tab:AddSelector({ label = "Bar Visible", values = Visibility.MODE_LABELS, order = Visibility.MODE_ORDER,
        get = function() return Visibility.Mode(token) end,
        set = function(v)
            DB.Set(Visibility.Path(token, "visible"), v ~= "always" and v or nil)
            apply()
        end })

    local get, set = Helpers.CreateFlatAccessors(
        function(key) return DB.Get(Visibility.Path(token, key)) end,
        function(key, value)
            if tonumber(value) == 100 then value = nil end
            DB.Set(Visibility.Path(token, key), value)
        end,
        Visibility.OPACITY_KEYS)
    tab:AddStateOpacityBlock({ get = get, set = set, apply = apply, min = 0, ooc = false,
        infoIcon = OPACITY_TOOLTIP })

    tab:AddToggle({ label = "Mouseover Mode",
        get = function() return DB.Get(Visibility.Path(token, "mouseoverMode")) == true end,
        set = function(v)
            DB.Set(Visibility.Path(token, "mouseoverMode"), v and true or nil)
            apply()
        end })
    tab:Finalize()
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

local function Render(panel, scrollContent)
    panel:ClearContent()
    local builder = SettingsBuilder:CreateFor(scrollContent)
    panel._currentBuilder = builder
    activeBuilder = builder
    builder:SetOnRefresh(function() Render(panel, scrollContent) end)

    if not ActionBars.IsEnabled() then
        builder:AddDescription("Action Bars is off on the Features page.")
        builder:Finalize()
        return
    end

    builder:AddDescription("To control your Camelot Action Bar Clusters, select them in Edit Mode.",
        { justify = "CENTER" })

    local values = {}
    for _, token in ipairs(BARS) do values[token] = Clusters.IdentityLabel(token) end
    builder:AddSelector({ label = "Action Bar", centered = true, sizeScale = PICKER_SCALE,
        width = PICKER_WIDTH, values = values, order = BARS,
        get = function() return selected end,
        set = function(v)
            Page.Follow(v)
            local id, index = placement(v)
            if id then EditMode.SetSubject(id, index) end
            builder:DeferredRefreshAll()
        end })

    local token = selected
    builder:AddTabbedSection({
        tabs = TABS,
        componentId = NAV_KEY,
        sectionKey = "barTabs",
        buildContent = {
            layout = function(_, tab) layoutTab(tab, builder, token) end,
            cooldown = function(_, tab)
                textTab(tab, token, "cooldown", "Hide Cooldown Text", cooldownDefaults())
            end,
            keybind = function(_, tab)
                textTab(tab, token, "hotkey", "Hide Keybind Text", keybindDefaults())
            end,
            visibility = function(_, tab) Page.VisibilityRows(tab, token) end,
        },
    })

    builder:Finalize()
end

--- After a rebuild the page did not ask for (a profile switch while it is
--- open): re-render when the panel shows this page.
function Page.Refresh()
    if quiet or not activeBuilder then return end
    local panel = addon.UI.SettingsPanel
    local shown = panel and panel.frame and panel.frame:IsShown()
    if shown and panel._currentBuilder == activeBuilder then
        activeBuilder:DeferredRefreshAll()
    end
end

addon.UI.SettingsPanel:RegisterRenderer(NAV_KEY, function(panel, scrollContent)
    Render(panel, scrollContent)
end)
