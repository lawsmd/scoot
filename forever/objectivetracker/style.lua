--------------------------------------------------------------------------------
-- forever/objectivetracker/style.lua
-- The objective tracker's settings, their defaults, and what applies them to
-- the Camelot containers: height, scale, the background's alpha, the text
-- size, the header backgrounds, the three text styles, and the fade in
-- instance combat.
--
-- Two panes, one code path. The main tracker (CamelotObjectiveTracker) and
-- the Current Objectives pane (CamelotCurrentObjectiveTracker, current.lua) are
-- each a pane descriptor in Style.PANES: a frame name and a key prefix. Every
-- apply loops the panes,
-- and a pane's settings sit under its prefix (objectiveTracker.current.*),
-- so the two share the page code too (page.lua, currentpage.lua).
--
-- First of the tracker files, and on both clients. Retail loads Camelot.toc
-- for the settings panel and excludes the HUD, and the pages have to draw
-- their controls there so a stored value can be checked across a reload
-- while the beta keeps none. So nothing here reads a tracker frame at file
-- scope; every apply runs against the pane's frame when it exists and
-- returns when it does not.
--
-- Blizzard's tracker keeps height, opacity and text size as Edit Mode
-- settings on its own frame. These containers are not Edit Mode systems, so
-- the three are Camelot's, stored with the rest and applied through the same
-- mechanisms Blizzard's Edit Mode uses: editModeHeight and UpdateHeight for
-- the height, the NineSlice alpha for the background, and the manager's
-- SetTextSize for the size, which swaps the two font objects every template
-- inherits so that layout measures the size it draws. The shared font
-- objects carry the main pane's size; the current pane's own size is set
-- string by string, the way a face is.
--
-- The text styles are applied after each layout, the way Scoot's component
-- applies them to Blizzard's frame. A string once given a face stays
-- detached from its font object, so from its second layout on the tracker
-- measures the face it draws; the first layout of a fresh frame is measured
-- in Blizzard's face and re-run once the face is on.
--------------------------------------------------------------------------------

local addonName, addon = ...

local DB = addon.DB

addon.ObjectiveTracker = addon.ObjectiveTracker or {}
local OT = addon.ObjectiveTracker

local Style = {}
OT.Style = Style

local OWNER = "camelotObjectiveTrackerStyle"

--------------------------------------------------------------------------------
-- Panes, paths and defaults
--------------------------------------------------------------------------------

-- Blizzard's Edit Mode ranges for the tracker system, and the Modern preset's
-- values: 800 high, a clear background, 12-point text. The header font is
-- two points above the line font (the manager's headerExtraSize). The
-- current pane holds a few quests at a time and takes a lower height range.
Style.HEIGHT = { min = 400, max = 1000, step = 10, default = 800 }
Style.PANE_HEIGHT = { min = 100, max = 600, step = 10, default = 300 }
Style.OPACITY = { min = 0, max = 100, step = 1, default = 0 }
Style.TEXT_SIZE = { min = 12, max = 20, step = 1, default = 12 }
Style.SCALE = { min = 0.5, max = 1.5, step = 0.05, default = 1 }
Style.HOLD = { min = 5, max = 300, step = 5, default = 90 }
-- The cross-fade of a quest moving between the panes (fade.lua). 0 is a cut.
Style.FADE = { min = 0, max = 2, step = 0.1, default = 0.5 }
Style.HEADER_EXTRA_SIZE = 2

-- The three styled texts and where each is read from: the container and
-- module headers, a block's header line, and a block's objective lines.
Style.TEXT_KEYS = { "textHeader", "textQuestName", "textQuestObjective" }

--- The panes. `prefix` is the segment a pane's settings sit under, nil for
--- the main tracker whose keys are the original ones; `frameName` the global
--- the pane's container is declared as in frames.xml.
Style.MAIN = { key = "main", prefix = nil, frameName = "CamelotObjectiveTracker",
               heightRange = Style.HEIGHT, label = "Objective Tracker" }
Style.CURRENT = { key = "current", prefix = "current", frameName = "CamelotCurrentObjectiveTracker",
                  heightRange = Style.PANE_HEIGHT, label = "Current Objectives" }
Style.PANES = { Style.MAIN, Style.CURRENT }

-- The Camelot style of the Current Objectives pane (cards.lua): a row or a
-- column of quest cards with its own look under
-- objectiveTracker.current.cards.*. Not a pane: every pane loop calls
-- container methods the cards' frame has none of. The
-- behaviour keys (enabled, the triggers, hold, fade, flash) are the pane's
-- and serve both styles.
Style.CARDS = { key = "cards", prefix = "current.cards", label = "Current Objective Cards" }
Style.STYLES = { classic = "Classic", camelot = "Camelot" }
Style.STYLE_ORDER = { "classic", "camelot" }
Style.CARD_WIDTH = { min = 120, max = 220, step = 5, default = 150 }
Style.CARD_SPACING = { min = 0, max = 40, step = 1, default = 8 }
Style.CARD_MAX = { min = 1, max = 8, step = 1, default = 5 }
Style.CARD_TITLE_SIZE = { min = 9, max = 18, step = 1, default = 12 }
Style.CARD_OBJECTIVE_SIZE = { min = 8, max = 16, step = 1, default = 10 }
Style.CARD_TEXT_KEYS = { "textTitle", "textObjective" }
Style.CARD_LAYOUTS = { row = "Row", column = "Column" }
Style.CARD_LAYOUT_ORDER = { "row", "column" }

--- The dotted path of a tracker setting: Style.Path("height"), or
--- Style.Path("textHeader", "fontFace"). A pane's keys are prefixed:
--- Style.Path("current", "height").
function Style.Path(...)
    return "objectiveTracker." .. table.concat({ ... }, ".")
end

function Style.Get(...)
    return DB.Get(Style.Path(...))
end

--- The same two for a pane: the main pane's path is the plain one.
function Style.PanePath(pane, ...)
    if pane and pane.prefix then return Style.Path(pane.prefix, ...) end
    return Style.Path(...)
end

function Style.PaneGet(pane, ...)
    return DB.Get(Style.PanePath(pane, ...))
end

do
    local map = {}
    for _, pane in ipairs(Style.PANES) do
        map[Style.PanePath(pane, "height")] = pane.heightRange.default
        map[Style.PanePath(pane, "opacity")] = Style.OPACITY.default
        map[Style.PanePath(pane, "textSize")] = Style.TEXT_SIZE.default
        map[Style.PanePath(pane, "scale")] = Style.SCALE.default
        map[Style.PanePath(pane, "hideHeaderBackgrounds")] = false
        map[Style.PanePath(pane, "tintHeaderBackgroundEnable")] = false
        map[Style.PanePath(pane, "tintHeaderBackgroundColor")] = { 1, 1, 1, 1 }
        for _, key in ipairs(Style.TEXT_KEYS) do
            -- No face and no style: the string stays on Blizzard's font
            -- object, whose face is the client's own for its locale and
            -- whose shadow is black at 1, -1. The page shows Friz Quadrata
            -- and Shadow for that state, which is what the roman font
            -- object draws.
            map[Style.PanePath(pane, key, "colorMode")] = "default"
            map[Style.PanePath(pane, key, "color")] = { 1, 1, 1, 1 }
        end
    end
    -- 100 is no fade. Scoot stores nil for the same state. One setting for
    -- both panes.
    map[Style.Path("opacityInInstanceCombat")] = 100
    -- The current pane's behaviour (current.lua). Camelot ships on.
    map[Style.Path("current", "enabled")] = true
    map[Style.Path("current", "onEnterArea")] = true
    map[Style.Path("current", "onProgress")] = true
    map[Style.Path("current", "holdSeconds")] = Style.HOLD.default
    map[Style.Path("current", "fadeSeconds")] = Style.FADE.default
    map[Style.Path("current", "flashProgress")] = true
    -- The pane's style, and the cards' look.
    map[Style.Path("current", "style")] = "classic"
    local cards = Style.CARDS
    map[Style.PanePath(cards, "layout")] = "row"
    map[Style.PanePath(cards, "width")] = Style.CARD_WIDTH.default
    map[Style.PanePath(cards, "spacing")] = Style.CARD_SPACING.default
    map[Style.PanePath(cards, "maxCards")] = Style.CARD_MAX.default
    map[Style.PanePath(cards, "scale")] = Style.SCALE.default
    map[Style.PanePath(cards, "opacity")] = 100
    map[Style.PanePath(cards, "titleSize")] = Style.CARD_TITLE_SIZE.default
    map[Style.PanePath(cards, "objectiveSize")] = Style.CARD_OBJECTIVE_SIZE.default
    for _, key in ipairs(Style.CARD_TEXT_KEYS) do
        -- No backdrop behind the cards: the outline carries the contrast.
        map[Style.PanePath(cards, key, "style")] = "THICKOUTLINESLUG"
        map[Style.PanePath(cards, key, "colorMode")] = "default"
        map[Style.PanePath(cards, key, "color")] = { 1, 1, 1, 1 }
    end
    DB.RegisterDefaults(map)
end

--------------------------------------------------------------------------------
-- Reads
--------------------------------------------------------------------------------

local function clamp(value, range)
    local v = tonumber(value) or range.default
    if v < range.min then v = range.min elseif v > range.max then v = range.max end
    return v
end
Style.Clamp = clamp

function Style.Height(pane)
    pane = pane or Style.MAIN
    return clamp(Style.PaneGet(pane, "height"), pane.heightRange)
end

function Style.Scale(pane)
    return clamp(Style.PaneGet(pane or Style.MAIN, "scale"), Style.SCALE)
end

function Style.TextSize(pane)
    return math.floor(clamp(Style.PaneGet(pane or Style.MAIN, "textSize"), Style.TEXT_SIZE) + 0.5)
end

--- The alpha a pane's background draws at.
function Style.BackgroundAlpha(pane)
    return clamp(Style.PaneGet(pane or Style.MAIN, "opacity"), Style.OPACITY) / 100
end

--- The seconds a quest stays in the current pane after progress on it.
function Style.HoldSeconds()
    return clamp(Style.Get("current", "holdSeconds"), Style.HOLD)
end

--- The seconds a quest takes to cross-fade between the panes; 0 is a cut.
function Style.FadeSeconds()
    return clamp(Style.Get("current", "fadeSeconds"), Style.FADE)
end

--- "classic" or "camelot": which style the Current Objectives pane draws in.
function Style.CurrentStyle()
    return Style.Get("current", "style") == "camelot" and "camelot" or "classic"
end

local function cardNumber(key, range)
    return clamp(Style.PaneGet(Style.CARDS, key), range)
end

function Style.CardWidth() return math.floor(cardNumber("width", Style.CARD_WIDTH) + 0.5) end
function Style.CardSpacing() return cardNumber("spacing", Style.CARD_SPACING) end
function Style.CardMax() return math.floor(cardNumber("maxCards", Style.CARD_MAX) + 0.5) end
function Style.CardScale() return cardNumber("scale", Style.SCALE) end
function Style.CardOpacity() return cardNumber("opacity", Style.OPACITY) / 100 end

--- "row" or "column": the cards side by side, or one under another.
function Style.CardLayout()
    return Style.PaneGet(Style.CARDS, "layout") == "column" and "column" or "row"
end

--- A card text's point size: "titleSize" or "objectiveSize".
function Style.CardTextSize(key)
    local range = key == "titleSize" and Style.CARD_TITLE_SIZE or Style.CARD_OBJECTIVE_SIZE
    return math.floor(cardNumber(key, range) + 0.5)
end

local function frameOf(pane)
    return _G[pane.frameName]
end

--- The pane a container belongs to, nil for a frame that is neither.
function Style.PaneOf(container)
    for _, pane in ipairs(Style.PANES) do
        if frameOf(pane) == container then return pane end
    end
    return nil
end

--- What CamelotObjectiveTrackerMixin:SetBackgroundAlpha answers in place of
--- the manager's value, for the container asking.
function Style.BackgroundAlphaFor(container)
    return Style.BackgroundAlpha(Style.PaneOf(container))
end

-- Every pane whose frame exists: on retail none does.
local function eachPane(fn)
    for _, pane in ipairs(Style.PANES) do
        local c = frameOf(pane)
        if c then fn(pane, c) end
    end
end

local function anyPane()
    return frameOf(Style.MAIN) ~= nil
end

--------------------------------------------------------------------------------
-- Height, scale, background, text size
--------------------------------------------------------------------------------

function Style.ApplyHeight()
    eachPane(function(pane, c)
        c.editModeHeight = Style.Height(pane)
        c:UpdateHeight()
    end)
end

function Style.ApplyScale()
    eachPane(function(pane, c)
        c:SetScale(Style.Scale(pane))
    end)
    -- The base scale is down; Dynamic Layouts puts a held dynamic scale and
    -- position back on top (dynamic.lua) before the buttons read the rects.
    if OT.Dynamic then OT.Dynamic.Reassert() end
    -- The quest item buttons stand on the blocks by screen coordinate.
    if OT.Items then OT.Items.Reposition() end
end

function Style.ApplyBackgroundAlpha()
    eachPane(function(pane, c)
        c:SetBackgroundAlpha(Style.BackgroundAlpha(pane))
    end)
end

-- The name of the font family the line font object stands on, which
-- SetTextSize sets to "ObjectiveTrackerFont<size>".
local function lineFontFamily()
    local fontObject = ObjectiveTrackerLineFont
    local parent = fontObject and fontObject.GetFontObject and fontObject:GetFontObject()
    return parent and parent.GetName and parent:GetName() or nil
end

--- Swaps the shared font objects to the main pane's size. The manager's
--- method ends with UpdateAll, so the call is skipped when the size is
--- already on. The current pane's size is applied string by string (ApplyText).
function Style.ApplyTextSize()
    if not (anyPane() and ObjectiveTrackerManager) then return end
    local size = Style.TextSize(Style.MAIN)
    if lineFontFamily() == "ObjectiveTrackerFont" .. size then return end
    ObjectiveTrackerManager:SetTextSize(size)
end

--------------------------------------------------------------------------------
-- Header backgrounds
--------------------------------------------------------------------------------

local function eachHeaderBackground(c, fn)
    if c.Header and c.Header.Background then fn(c.Header.Background) end
    c:ForEachModule(function(module)
        if module.Header and module.Header.Background then fn(module.Header.Background) end
    end)
end

--- Shown or hidden, and the tint. Off is Blizzard's own: shown, white.
function Style.ApplyHeaders()
    eachPane(function(pane, c)
        local shown = not Style.PaneGet(pane, "hideHeaderBackgrounds")
        local r, g, b, a = 1, 1, 1, 1
        if Style.PaneGet(pane, "tintHeaderBackgroundEnable") then
            local tint = Style.PaneGet(pane, "tintHeaderBackgroundColor")
            if type(tint) == "table" then
                r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
            end
        end
        eachHeaderBackground(c, function(bg)
            bg:SetShown(shown)
            bg:SetVertexColor(r, g, b, a)
        end)
    end)
end

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

local function textConfig(pane, key)
    return {
        fontFace = Style.PaneGet(pane, key, "fontFace"),
        style = Style.PaneGet(pane, key, "style"),
        colorMode = Style.PaneGet(pane, key, "colorMode"),
        color = Style.PaneGet(pane, key, "color"),
    }
end

-- Strings that have taken a face, a style or a size at least once. A first
-- application changes the string's metrics after the layout that placed it,
-- so that layout is run again. A string once detached from its font object
-- is re-applied on every pass, so a cleared face or a size put back to the
-- shared one still lands.
local styled = setmetatable({}, { __mode = "k" })
local relayoutPending = {}

local function requestRelayout(c)
    if relayoutPending[c] then return end
    relayoutPending[c] = true
    C_Timer.After(0, function()
        relayoutPending[c] = nil
        c:MarkDirty()
    end)
end

-- The face and the style, at the pane's size. Nothing stored and the size
-- the shared font objects carry: the string stays on its font object. Only a
-- face, or only a size: SetFont keeps the flags and the shadow the string
-- has. A style: ApplyFontStyle decodes it.
local function applyFont(fs, cfg, size, c, sizeDiffers)
    local face = cfg.fontFace and addon.ResolveFontFace(cfg.fontFace) or nil
    local style = cfg.style
    if not (face or style or sizeDiffers or styled[fs]) then return end
    local curFace, _, curFlags = fs:GetFont()
    face = face or curFace
    if not face then return end
    if style then
        addon.ApplyFontStyle(fs, face, size, style)
    else
        fs:SetFont(face, size, curFlags)
    end
    if not styled[fs] then
        styled[fs] = true
        requestRelayout(c)
    end
end

-- Toward white, the way Blizzard's HeaderHighlight sits above Header.
local function brighten(r, g, b, factor)
    return r + (1 - r) * factor, g + (1 - g) * factor, b + (1 - b) * factor
end

-- A custom color is written; any other mode leaves Blizzard's color, which
-- the block rewrites on every layout and every hover.
local function applyColor(fs, cfg, highlighted)
    local r, g, b, a, source = addon.ResolveColorRGBA(cfg.colorMode, cfg.color, {})
    if source ~= "custom" then return end
    if highlighted then r, g, b = brighten(r, g, b, 0.35) end
    fs:SetTextColor(r, g, b, a)
end

local function eachBlock(module, fn)
    local used = module.usedBlocks
    if type(used) ~= "table" then return end
    for _, blocks in pairs(used) do
        for _, block in pairs(blocks) do fn(block) end
    end
end

local function eachLine(block, fn)
    if type(block.ForEachUsedLine) ~= "function" then return end
    block:ForEachUsedLine(fn)
end

-- The block's colors after its own UpdateHighlight: Blizzard writes the
-- header's and every line's color there on enter and leave, with no layout.
-- A block belongs to one module, and a module to one pane, so the hook reads
-- the pane's config at call time.
local hookedBlocks = setmetatable({}, { __mode = "k" })

local function colorBlock(block, questName, objective)
    if block.HeaderText then
        applyColor(block.HeaderText, questName, block.isHighlighted)
    end
    eachLine(block, function(line)
        if line.Text then applyColor(line.Text, objective) end
    end)
end

local function hookBlock(block, pane)
    if hookedBlocks[block] or type(block.UpdateHighlight) ~= "function" then return end
    hookedBlocks[block] = true
    hooksecurefunc(block, "UpdateHighlight", function(b)
        colorBlock(b, textConfig(pane, "textQuestName"), textConfig(pane, "textQuestObjective"))
    end)
end

local function applyTextTo(pane, c)
    local header = textConfig(pane, "textHeader")
    local questName = textConfig(pane, "textQuestName")
    local objective = textConfig(pane, "textQuestObjective")
    local size = Style.TextSize(pane)
    local headerSize = size + Style.HEADER_EXTRA_SIZE
    -- The shared font objects carry the main pane's size; another size is
    -- set on each string.
    local sizeDiffers = size ~= Style.TextSize(Style.MAIN)

    if c.Header and c.Header.Text then
        applyFont(c.Header.Text, header, headerSize, c, sizeDiffers)
        applyColor(c.Header.Text, header)
    end

    c:ForEachModule(function(module)
        if module.Header and module.Header.Text then
            applyFont(module.Header.Text, header, headerSize, c, sizeDiffers)
            applyColor(module.Header.Text, header)
        end
        eachBlock(module, function(block)
            hookBlock(block, pane)
            if block.HeaderText then
                applyFont(block.HeaderText, questName, size, c, sizeDiffers)
            end
            eachLine(block, function(line)
                if line.Text then applyFont(line.Text, objective, size, c, sizeDiffers) end
                -- The dash shares the line's font; its color stays Blizzard's.
                if line.Dash then applyFont(line.Dash, objective, size, c, sizeDiffers) end
            end)
            colorBlock(block, questName, objective)
        end)
    end)
end

--- The three text styles over every string each pane shows now.
function Style.ApplyText()
    eachPane(applyTextTo)
end

--------------------------------------------------------------------------------
-- Instance combat
--------------------------------------------------------------------------------

local function inDungeonOrRaid()
    local inInstance, instanceType = IsInInstance()
    return inInstance == true and (instanceType == "party" or instanceType == "raid")
end

-- Kept off addon.Opacity.Resolve: one override with a compound gate (combat in a dungeon or raid), else 1, and core/opacity.lua is not on this TOC.
--- The alpha the instance-combat fade holds the headers and modules at now.
function Style.CombatAlpha()
    if UnitAffectingCombat("player") and inDungeonOrRaid() then
        return clamp(Style.Get("opacityInInstanceCombat"), Style.OPACITY) / 100
    end
    return 1
end

--- The fade in instance combat, on the header and on each module but the
--- Scenario module, so the dungeon's own progress stays readable. Never the
--- container itself: alpha multiplies down the tree. One setting, both panes.
function Style.ApplyCombatOpacity()
    local alpha = Style.CombatAlpha()
    eachPane(function(_, c)
        if c.Header then c.Header:SetAlpha(alpha) end
        c:ForEachModule(function(module)
            if module ~= ScenarioObjectiveTracker then
                if module.Header then module.Header:SetAlpha(alpha) end
                if module.ContentsFrame then module.ContentsFrame:SetAlpha(alpha) end
            end
        end)
    end)
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

--- Every setting, in the order the frames take them. The pages' apply and
--- the profile engine's. The pane state re-reads its settings last, since a
--- trigger switched off or on moves quests between the panes.
function Style.Apply()
    if not anyPane() then return end
    Style.ApplyHeight()
    Style.ApplyScale()
    Style.ApplyBackgroundAlpha()
    Style.ApplyTextSize()
    Style.ApplyHeaders()
    Style.ApplyText()
    Style.ApplyCombatOpacity()
    if OT.Cards then OT.Cards.Apply() end
    if OT.Current then OT.Current.Refresh() end
end

--- What each container layout re-runs: the parts the layout rewrites.
function Style.OnUpdate()
    if not anyPane() then return end
    Style.ApplyHeaders()
    Style.ApplyText()
end

local installed = false

--- Once, from the tracker's setup, after the containers have their modules.
function Style.Install()
    if installed or not anyPane() then return end
    installed = true

    -- Blizzard's Edit Mode applies its tracker's text size to the shared
    -- font objects on every layout activation; the stored size goes back on
    -- after it.
    if ObjectiveTrackerFrame then
        hooksecurefunc(ObjectiveTrackerFrame, "UpdateSystemSettingTextSize", Style.ApplyTextSize)
    end

    addon.Events.On(OWNER, "PLAYER_REGEN_DISABLED", Style.ApplyCombatOpacity)
    addon.Events.On(OWNER, "PLAYER_REGEN_ENABLED", Style.ApplyCombatOpacity)
    addon.Events.On(OWNER, "PLAYER_ENTERING_WORLD", Style.ApplyCombatOpacity)

    Style.Apply()
end

-- After a profile switch, the frames re-read the new profile. A resync pass
-- keeps the profile it had; re-landing the base scale there would cut short
-- the Dynamic Layouts tween that leaving Edit Mode starts.
addon.Profiles.RegisterApplyStep("camelotObjectiveTracker", function(_, ctx)
    if ctx.initial or ctx.resync then return end
    Style.Apply()
end, 20)

--------------------------------------------------------------------------------
-- Edit Mode dialog
--------------------------------------------------------------------------------

-- The sliders Blizzard's tracker shows in its Edit Mode dialog, plus scale.
-- Labels only: the dialog has no room for descriptions.
local function sliderSpec(pane, label, range, key, scaleBy)
    scaleBy = scaleBy or 1
    return {
        kind = "slider", label = label,
        min = range.min * scaleBy, max = range.max * scaleBy, step = range.step * scaleBy,
        precision = 0,
        get = function() return math.floor(clamp(Style.PaneGet(pane, key), range) * scaleBy + 0.5) end,
        set = function(v)
            DB.Set(Style.PanePath(pane, key), (tonumber(v) or range.default * scaleBy) / scaleBy)
            Style.Apply()
        end,
    }
end

--- The mirror for a pane's branded Edit Mode dialog. Returns a function, the
--- shape the positionable's brand.mirror takes.
function Style.EditModeMirror(pane)
    pane = pane or Style.MAIN
    return function()
        return {
            sliderSpec(pane, "Height", pane.heightRange, "height"),
            sliderSpec(pane, "Scale", Style.SCALE, "scale", 100),
            sliderSpec(pane, "Opacity", Style.OPACITY, "opacity"),
            sliderSpec(pane, "Text Size", Style.TEXT_SIZE, "textSize"),
        }
    end
end
