--------------------------------------------------------------------------------
-- forever/actionbars/gamepad.lua
-- The gamepad bar replica: Forever's GamepadMainActionBarFrame as a Camelot
-- page unit of Camelot buttons at the same spot, under the gamepad UI.
-- A shadow, as the standard bars are
-- (bars.lua): the controller keeps pressing Blizzard's own buttons through
-- Blizzard's own bindings on Blizzard's frame, dimmed to alpha 0 with its
-- buttons mouse off, and a watcher mirrors that frame's state onto this
-- one: the page, the active bar (which expands as Blizzard's does), the
-- override bars, the page tracker, the modifier icons, the shoulder
-- targeting art, the fade a targeting bar puts on the other bars, the
-- flyout dim, the active icon set, and the keys themselves for the pushed
-- state and the pressed geometry. Nothing is hooked on the system frame or its children
-- and nothing is registered into Blizzard's registries; every read is a
-- plain field or a getter.
--
-- The holder anchors to Blizzard's frame, whose Edit Mode box stays the
-- handle: Edit Mode moves Blizzard's frame and this one follows, so the
-- cast bar the gamepad map anchors to it stays aligned. The holder's own
-- box is for the Dynamic Layouts view alone, at rest under Blizzard's
-- otherwise. The click targets are secure, so the holder is implicitly
-- protected: the layout and the compact fold wait for regen in a fight; the
-- mirrored state redraws at once on the plain visual buttons.
--------------------------------------------------------------------------------

local _, addon = ...

local ActionBars = addon.ActionBars
local DB = addon.DB

local GamepadBar = {}
ActionBars.GamepadBar = GamepadBar

local PATH = "actionBars.gamepad."
local OWNER = ActionBars.OWNER .. ".gamepad"
local LAYOUT_KEY = "camelotActionBars.gamepad.layout"

GamepadBar.PATH = PATH
-- The Visibility and Dynamic Layouts key.
GamepadBar.KEY = "gamepadBar"
GamepadBar.NAV_KEY = "actionBarGamepad"
GamepadBar.LABEL = "Gamepad Bars"
GamepadBar.RANGES = {
    scale = { min = 50, max = 200, step = 10 },
}

-- Blizzard's frame size (MainActionBarFrame.xml).
local WIDTH, HEIGHT = 656, 202
local NUM_KEYS = 8
-- The slow tick the mirrors copy on, between the events that copy at once.
local SYNC_INTERVAL = 0.25
-- The page tracker's slot placement (PageUnit.lua, SetupPageTracker).
local TRACKER_PADDING = 5
local NUM_STANDARD_PAGE_IMAGES = 3

DB.RegisterDefaults({
    [PATH .. "enabled"] = true,
    [PATH .. "scale"] = 100,
    [PATH .. "compact"] = false,
    [PATH .. "showEmptyBars"] = true,
    [PATH .. "highlight"] = true,
    [PATH .. "expand"] = true,
    [PATH .. "buttonPrompts"] = false,
})

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

function GamepadBar.Get(field)
    return DB.Get(PATH .. field)
end

--- Write a setting and lay the bar out again.
function GamepadBar.Set(field, value)
    DB.Set(PATH .. field, value)
    GamepadBar.Apply()
end

local function number(field, fallback)
    return tonumber(GamepadBar.Get(field)) or fallback
end

--- The switch, read once per session as the Features switches are: a change
--- lands at the reload.
function GamepadBar.IsEnabled()
    return ActionBars.IsEnabled() and DB.SessionGet(PATH .. "enabled") ~= false
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local holder, face, pageUnit
local box -- the holder's Edit Mode selection, for the dynamic view
local blizzard, unit -- GamepadMainActionBarFrame and its PageUnit
local built = false

local ANCHOR_KEYS = { "top", "left", "right", "bottom" }
-- Blizzard's standard bars by the actionBars key each anchor's bar takes.
local STANDARD_BARS = { topBar = "top", leftBar = "left", rightBar = "right", bottomBar = "bottom" }
-- The bars that stand in for a standard bar while shown (PageUnit.lua,
-- SetupActionBarReferences); the possess and stance bars move to the
-- anchor they override, the targeting bars stay on the top one.
local OVERRIDE_BARS = { "possessBar", "stanceBar", "friendlyTargetingBar", "hostileTargetingBar", "shortcutsBar" }
-- The modifier icon that belongs to each anchor's bar: Blizzard parents it
-- into the bar, so the bar's fade reaches it there.
local ICON_BY_KEY = { left = "LeftIcon", right = "RightIcon", bottom = "CenteredIcons" }
local SHOULDER_SIDES = { "Left", "Right" }

local anchorOf = {} -- Blizzard anchor frame -> key
local barKey = {} -- Blizzard standard bar -> key
local keys = {} -- action index -> the keys bound to it
local pushed = {} -- action index -> down
local trackerSlots = {} -- Camelot's page tracker slots
local state = { overrides = {}, slotStates = {}, icons = {}, shoulders = {}, barAlpha = {} }
local sinceSync = 0

local function plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

--- The frame the Visibility settings write for the token, or nil.
function GamepadBar.Face(token)
    if token ~= GamepadBar.KEY or not holder then return nil end
    return holder.Face
end

--- Whether the bar draws: built, and its holder shown.
function GamepadBar.IsActive(token)
    return token == GamepadBar.KEY and built and holder:IsShown()
end

function GamepadBar.IsBuilt()
    return built
end

--------------------------------------------------------------------------------
-- The dim
--------------------------------------------------------------------------------
-- Kept off addon.NativeFrame: the selection box is this replica's Edit Mode
-- handle, and the alpha method hides it. Blizzard's frame goes to alpha 0,
-- its box ignoring parent alpha by its own template, and its bars, buttons
-- and page buttons take no mouse (suppression.lua's rule for a dimmed bar;
-- Blizzard clicks the page buttons itself). The mouse writes are protected,
-- so they run out of combat, once.

local mouseOff = false

local function MouseOff()
    if mouseOff or not unit then return end
    for _, bar in pairs(unit.actionBars or {}) do
        bar:EnableMouse(false)
        for _, button in ipairs(bar.actionButtons or {}) do
            button:EnableMouse(false)
        end
    end
    local tracker = unit.PageTracker
    if tracker then
        tracker:EnableMouse(false)
        if tracker.ChangePageButton then tracker.ChangePageButton:EnableMouse(false) end
    end
    for _, key in ipairs({ "LeftClassAction", "RightClassAction" }) do
        if unit[key] then unit[key]:EnableMouse(false) end
    end
    local cycle = _G.CycleActionBarPageButton
    if cycle then cycle:EnableMouse(false) end
    mouseOff = true
end

local function Dim()
    if not blizzard then return end
    blizzard:SetAlpha(0)
    addon.Events.RunOutOfCombat(MouseOff, OWNER .. ".mouseOff")
end

--------------------------------------------------------------------------------
-- The watcher
--------------------------------------------------------------------------------

local function ReadKeys()
    for i = 1, NUM_KEYS do
        keys[i] = { GetBindingKey("GAMEPADACTIONBUTTON" .. i, 1) }
    end
end

local function SyncMirrors()
    if not pageUnit then return end
    for _, bar in pageUnit:EachBar() do
        bar:SyncMirrors()
    end
end

-- The icon set the slot art and the prompts draw from (Xbox letters,
-- PlayStation shapes), the read Blizzard's own art makes.
local function ActiveIconSet()
    local manager = InputDeviceIconSetManager
    if not (manager and manager.GetActiveInputDeviceIconSet) then return nil end
    return manager:GetActiveInputDeviceIconSet()
end

-- The Blizzard bar's anchor key, and whether it is an override bar.
local function anchorKeyOf(bar)
    local key = barKey[bar]
    if key then return key, false end
    local parent = bar:GetParent()
    return parent and anchorOf[parent] or nil, true
end

local function syncIcon(key)
    local source, mirror = unit[key], pageUnit[key]
    if not (source and mirror) then return end
    local shown = source:IsVisible() and true or false
    if state.icons[key] ~= shown then
        state.icons[key] = shown
        mirror:SetShown(shown)
    end
end

local function syncTracker()
    local tracker = unit.PageTracker
    if not tracker then return end
    local shown = tracker:IsShown() and true or false
    if shown ~= state.trackerShown then
        state.trackerShown = shown
        pageUnit.PageTracker:SetShown(shown)
    end
    if not shown then return end
    for i, slot in ipairs(trackerSlots) do
        local source = tracker.slots and tracker.slots[i]
        local slotState = source and source.currentState
        if slotState and slotState ~= state.slotStates[i] then
            state.slotStates[i] = slotState
            slot:SetPageSlotState(slotState)
        end
    end
    local special = tracker.specialSlot
    local specialShown = special and special:IsShown() and true or false
    if specialShown ~= state.specialShown then
        state.specialShown = specialShown
        local ours = trackerSlots[#trackerSlots]
        if ours then ours:SetShown(specialShown) end
    end
    local width = tracker:GetWidth()
    if width ~= state.trackerWidth then
        state.trackerWidth = width
        pageUnit.PageTracker:SetWidth(width)
    end
end

-- The shoulder targeting art: each box's icon is whatever atlas Blizzard's
-- carries (friendly or hostile at rest, shortcuts while a targeting bar
-- shows, the pair swapped under GamepadSwapTargetModifiers), and its
-- pressed art shows while Blizzard's does. A nil atlas, before Blizzard's
-- own setup has run, is left alone.
local function syncShoulders()
    for _, side in ipairs(SHOULDER_SIDES) do
        local icon, ours = unit[side .. "ShoulderIcon"], pageUnit[side .. "ShoulderIcon"]
        if icon and ours then
            local atlas = plain(icon:GetAtlas())
            if atlas ~= nil and atlas ~= state.shoulders[side] then
                state.shoulders[side] = atlas
                ours:SetAtlas(atlas, true)
            end
        end
        local highlight, oursPressed = unit[side .. "ShoulderHighlight"], pageUnit[side .. "ShoulderHighlight"]
        if highlight and oursPressed then
            local shown = highlight:IsShown() and true or false
            local key = side .. "Pressed"
            if shown ~= state.shoulders[key] then
                state.shoulders[key] = shown
                oursPressed:SetShown(shown)
            end
        end
    end
end

-- The fade a targeting bar puts on the other bars (TargetActionBars/Shared.lua,
-- FadeOutInactiveBars): every bar off the top anchor goes to 0.3 over two
-- seconds, the override bar and the hidden standard bar under it alike,
-- and all come back to 1. The standard bar's alpha is the anchor's, and
-- the anchor's bar, mirror and modifier icon take it. Per frame, since
-- UIFrameFade writes it per frame.
local function syncBarAlpha()
    for name, key in pairs(STANDARD_BARS) do
        local bar = unit.actionBars[name]
        local alpha = bar and plain(bar:GetAlpha())
        if alpha ~= nil and alpha ~= state.barAlpha[key] then
            state.barAlpha[key] = alpha
            pageUnit.bars[key]:SetAlpha(alpha)
            pageUnit.mirrors[key]:SetAlpha(alpha)
            local icon = ICON_BY_KEY[key] and pageUnit[ICON_BY_KEY[key]]
            if icon then icon:SetAlpha(alpha) end
        end
    end
end

local function Watch(_, elapsed)
    if not unit then return end

    local tracker = unit.PageTracker
    local page = tracker and tracker.currentPage or 1
    if page ~= state.page then
        state.page = page
        pageUnit:SetPage(page)
    end

    for _, key in ipairs(ANCHOR_KEYS) do
        local source, sourceName
        for _, name in ipairs(OVERRIDE_BARS) do
            local bar = unit.actionBars[name]
            if bar and bar:IsShown() then
                local parent = bar:GetParent()
                if parent and anchorOf[parent] == key then
                    source, sourceName = bar, name
                    break
                end
            end
        end
        if source ~= state.overrides[key] then
            state.overrides[key] = source
            pageUnit:SetMirrorSource(key, source, sourceName)
            if source then SyncMirrors() end
        end
    end

    local active = unit.activeBar
    local ours
    if active then
        local key, override = anchorKeyOf(active)
        if key then
            ours = override and pageUnit.mirrors[key] or pageUnit.bars[key]
        end
    end
    if ours ~= state.active then
        state.active = ours
        pageUnit:SetActiveBar(ours)
        for i = 1, NUM_KEYS do pushed[i] = false end
    end

    syncTracker()
    syncIcon("LeftIcon")
    syncIcon("RightIcon")
    syncIcon("CenteredIcons")
    syncShoulders()
    syncBarAlpha()

    -- The flyout dim, unless a flyout opened from a Camelot button holds
    -- the alpha itself.
    if not pageUnit.activeFlyoutButton then
        local alpha = unit:GetAlpha()
        if alpha ~= state.alpha then
            state.alpha = alpha
            pageUnit:SetAlpha(alpha)
        end
    end

    if ours then
        for i = 1, NUM_KEYS do
            local down = false
            for _, key in ipairs(keys[i] or {}) do
                if IsKeyDown(key) then
                    down = true
                    break
                end
            end
            if down ~= (pushed[i] or false) then
                pushed[i] = down
                ours:SetPushed(i, down)
            end
        end
    end

    sinceSync = sinceSync + (elapsed or 0)
    if sinceSync >= SYNC_INTERVAL then
        sinceSync = 0
        SyncMirrors()
        local iconSet = ActiveIconSet()
        if iconSet ~= state.iconSet then
            state.iconSet = iconSet
            pageUnit:RefreshInputIconSet()
        end
    end
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local function Layout()
    local scale = number("scale", 100) / 100
    holder:SetSize(WIDTH * scale, HEIGHT * scale)
    pageUnit:SetScale(scale)
    face.useCompactLayout = GamepadBar.Get("compact") == true
    face.showEmptyBars = GamepadBar.Get("showEmptyBars") ~= false
    face.showHighlight = GamepadBar.Get("highlight") ~= false
    face.shouldExpand = GamepadBar.Get("expand") ~= false
    face.showButtonIcons = GamepadBar.Get("buttonPrompts") == true
    pageUnit:SetCompact(face.useCompactLayout)
    pageUnit:RefreshActionBarVisibilities()
    pageUnit:RefreshHighlight()
    ActionBars.Visibility.Apply(GamepadBar.KEY)
end

--- Lay the bar out again, after a setting or a profile switch. Waits for
--- regen in a fight.
function GamepadBar.Apply()
    if not built then return end
    addon.Events.RunOutOfCombat(Layout, LAYOUT_KEY)
    if GamepadBar.Page and GamepadBar.Page.Refresh then GamepadBar.Page.Refresh() end
end

--- Edit Mode opening or closing: the dim re-asserted.
function GamepadBar.OnEditMode()
    if built then Dim() end
end

--------------------------------------------------------------------------------
-- Edit Mode and Dynamic Layouts
--------------------------------------------------------------------------------
-- The adapter is the protected tier, as the stance bar's: opacity and scale
-- on the holder; no position channel, since the holder follows Blizzard's
-- frame. The view sets a frame's record through its box's dialog, so the
-- holder carries a box of its own for the view alone: Blizzard's box under
-- it keeps the drag in the regular Edit Mode, and the view hides every
-- Blizzard box.

-- The holder's anchor, put back after anything the library writes (a nudge).
local function Anchor()
    holder:ClearAllPoints()
    holder:SetPoint("CENTER", blizzard, "CENTER")
end

-- Nothing is stored and nothing is restored: the key is nil (endcaps.lua's
-- pattern). A position the library writes reaches apply as a drop, which
-- puts the holder back on Blizzard's frame and reports the drop handled.
local NO_STORE = { get = function() return nil end, set = function() end }
local DEFAULT = { point = "CENTER", x = 0, y = 0 }

-- The box rests at alpha 0 with its mouse off outside the view
-- (positionables.lua, dynamicViewOnly) and never moves the holder: the drag
-- is unregistered and a nudge springs back. The view's dialog lists Opacity
-- and Scale from the adapter's channels, and no Position row.
local function RegisterBox()
    local EM = addon.EditMode
    if not (EM and EM.RegisterPositionable) then return end
    holder.editModeName = GamepadBar.LABEL
    box = EM.RegisterPositionable(holder, {
        key = nil,
        default = DEFAULT,
        store = NO_STORE,
        apply = function()
            -- The holder is implicitly protected; the view never opens in
            -- combat, so this is a safety net.
            if InCombatLockdown() then
                addon.Events.RunOutOfCombat(Anchor, OWNER .. ".anchor")
            else
                Anchor()
            end
            return true
        end,
        positionEditable = function() return false end,
        dynamicViewOnly = true,
        brand = { navKey = GamepadBar.NAV_KEY, componentId = GamepadBar.NAV_KEY },
    })
    if box then box:RegisterForDrag() end
end

local Dynamic = {}
GamepadBar.Dynamic = Dynamic

local dynamicRegistered = false

function Dynamic.Register()
    local DL = addon.DynamicLayouts
    if not (DL and DL.Register) then return end
    dynamicRegistered = true
    DL.Register({
        id = GamepadBar.KEY,
        label = GamepadBar.LABEL,
        group = "gamepadBar",
        frame = holder,
        tier = "protected",
        channels = { "opacity", "scale" },
        base = {
            opacity = function() return 1 end,
            scale = function() return 1 end,
        },
        -- The click targets take a drop, and under the gamepad UI this is
        -- the bar on screen: a held action brings the layout back.
        dropTarget = true,
    })
end

function Dynamic.IsRegistered()
    return dynamicRegistered
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

-- Blizzard's page tracker slots, on Blizzard's slot templates: images for
-- the standard pages, text for the special one (PageUnit.lua,
-- SetupPageTracker). The LEFT point goes first; the text slot's Initialize
-- adds a TOP point of its own.
local function BuildTracker()
    local constants = Constants.GamepadActionBarConstants
    local tracker = pageUnit.PageTracker
    for i = 1, constants.NUM_PAGES_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT do
        local standard = i <= constants.NUM_STANDARD_PAGES_PER_GAMEPAD_ACTION_BAR_PAGE_UNIT
        local image = standard and i <= NUM_STANDARD_PAGE_IMAGES
        local template = image and "GamepadActionBarPageTrackerSlotImageFrame"
            or "GamepadActionBarPageTrackerSlotTextFrame"
        local slot = CreateFrame("Frame", nil, tracker, template)
        slot:SetPoint("LEFT", tracker, "LEFT", (i - 1) * slot:GetWidth() + TRACKER_PADDING, 0)
        slot.num = i
        if standard then
            slot:Initialize(i)
        else
            slot:Initialize("S")
        end
        trackerSlots[i] = slot
    end
end

-- The map from Blizzard's frames to anchor keys, and the four reserved
-- slots of the top bar as mirrors of Blizzard's.
local function Install()
    anchorOf[unit.TopCenteredAnchor] = "top"
    anchorOf[unit.LeftCenteredAnchor] = "left"
    anchorOf[unit.RightCenteredAnchor] = "right"
    anchorOf[unit.BottomCenteredAnchor] = "bottom"
    for name, key in pairs(STANDARD_BARS) do
        local bar = unit.actionBars[name]
        if bar then barKey[bar] = key end
    end

    local top = pageUnit.bars.top
    local source = unit.actionBars.topBar
    for i = 5, 8 do
        local button = top.actionButtons[i]
        button:ArmMirror(true)
        button:SetMirror(source and source.actionButtons and source.actionButtons[i] or nil)
    end

    for _, bar in pageUnit:EachBar() do
        for _, button in ipairs(bar.actionButtons) do
            ActionBars.Buttons[#ActionBars.Buttons + 1] = button
        end
    end

    pageUnit:SetPage(1, true)
    state.page = 1
    state.iconSet = ActiveIconSet()
end

-- The events Blizzard redraws the reserved icons on, then the ones the
-- targeting bars redraw their portraits and assist slot on.
local SYNC_EVENTS = {
    "PLAYER_TARGET_CHANGED", "PLAYER_SOFT_INTERACT_CHANGED", "PLAYER_SOFT_ENEMY_CHANGED",
    "RAID_TARGET_UPDATE", "PLAYER_EQUIPMENT_CHANGED", "UPDATE_BONUS_ACTIONBAR", "PET_BAR_UPDATE",
    "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT", "PLAYER_ENTERING_WORLD",
    "UNIT_TARGET", "UNIT_PET", "GROUP_ROSTER_UPDATE", "UNIT_PORTRAIT_UPDATE",
}

-- One deferred copy per frame however many of those fire: UNIT_TARGET
-- fires for every unit in sight.
local syncQueued = false
local function QueueSync()
    if syncQueued then return end
    syncQueued = true
    C_Timer.After(0, function()
        syncQueued = false
        SyncMirrors()
    end)
end

-- The events Blizzard registers on a flyout button (ActionBarButton.lua,
-- UpdateFlyoutActionInfo), forwarded to every Camelot button instead.
local FLYOUT_EVENTS = { "UNIT_AURA", "UNIT_POWER_UPDATE", "SPELL_FLYOUT_UPDATE", "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE" }
local FLYOUT_UNIT_EVENTS = { UNIT_AURA = true, UNIT_POWER_UPDATE = true }

local function forwardFlyoutEvent(event, ...)
    if FLYOUT_UNIT_EVENTS[event] and (...) ~= "player" then return end
    for _, bar in pageUnit:EachBar() do
        for _, button in ipairs(bar.actionButtons) do
            button:OnFlyoutEvent(event, ...)
        end
    end
end

--- Build the holder, the page unit and the watcher, once, out of combat,
--- from ActionBars' own build, under the gamepad UI alone.
function GamepadBar.Build()
    if built or not GamepadBar.IsEnabled() then return end
    local Gamepad = addon.Gamepad
    if not (Gamepad and Gamepad.IsActive and Gamepad.IsActive()) then return end
    blizzard = GamepadMainActionBarFrame
    unit = blizzard and blizzard.PageUnit
    if not (unit and unit.actionBars and unit.actionBars.topBar and unit.TopCenteredAnchor) then
        unit = nil
        return
    end

    holder = CreateFrame("Frame", "CamelotGamepadBar", UIParent)
    addon.Strata.ApplyHUD(holder, 60)
    holder:SetSize(WIDTH, HEIGHT)
    holder:SetPoint("CENTER", blizzard, "CENTER")
    face = CreateFrame("Frame", nil, holder)
    face:SetAllPoints(holder)
    holder.Face = face
    -- The fields Blizzard's kept bar code reads on the page unit's parent.
    face.useCompactLayout = false
    face.showEmptyBars = true
    face.showButtonIcons = false
    face.showHighlight = true
    face.shouldExpand = false

    pageUnit = CreateFrame("Frame", "CamelotGamepadPageUnit", face, "CamelotGamepadPageUnitTemplate")
    pageUnit:SetPoint("CENTER")
    BuildTracker()
    Install()
    ReadKeys()
    built = true

    Layout()
    Dim()
    -- The positionable before the adapter, the house order.
    RegisterBox()
    Dynamic.Register()
    SyncMirrors()
    holder:SetScript("OnUpdate", Watch)

    for _, event in ipairs(SYNC_EVENTS) do
        addon.Events.On(OWNER, event, QueueSync)
    end
    for _, event in ipairs(FLYOUT_EVENTS) do
        addon.Events.On(OWNER, event, forwardFlyoutEvent)
    end
    addon.Events.On(OWNER, "UPDATE_BINDINGS", ReadKeys)
    addon.Events.On(OWNER, "PLAYER_ENTERING_WORLD", Dim)
end

-- After a profile switch the settings come from the new profile. Runs after
-- the stance bar's step at 32.
addon.Profiles.RegisterApplyStep("camelotGamepadBar", function(_, ctx)
    if ctx.initial or ctx.resync or not built then return end
    GamepadBar.Apply()
end, 33)

--------------------------------------------------------------------------------
-- Report
--------------------------------------------------------------------------------

local function keyList(i)
    local list = keys[i]
    if not list or #list == 0 then return "none" end
    return table.concat(list, ", ")
end

--- The rows /camelot actionbars prints.
function GamepadBar.Report(push)
    local Gamepad = addon.Gamepad
    push("gamepad bar: enabled %s, gamepad %s, built %s", tostring(GamepadBar.IsEnabled()),
        tostring(Gamepad and Gamepad.IsActive and Gamepad.IsActive()), tostring(built))
    if not built then return end
    push("  %-24s alpha %.2f, mouse off %s, shown %s", blizzard:GetName() or "?", blizzard:GetAlpha(),
        tostring(mouseOff), tostring(blizzard:IsShown()))
    push("  %-24s shown %-5s %.0fx%.0f scale %.2f protected %s, dynamic %s, box %s", holder:GetName(),
        tostring(holder:IsShown()), holder:GetWidth(), holder:GetHeight(), pageUnit:GetScale(),
        tostring((holder:IsProtected())), tostring(dynamicRegistered),
        box and ("alpha " .. box:GetAlpha() .. " mouse " .. tostring(box:IsMouseEnabled())) or "none")
    push("  %s", ActionBars.Visibility.Describe(GamepadBar.KEY))
    local active = state.active
    push("  page %s, active %s, compact %s, show empty %s, highlight %s, expand %s, prompts %s",
        tostring(state.page), active and (active.anchorKey .. (active.isMirror and " mirror" or "")) or "none",
        tostring(face.useCompactLayout), tostring(face.showEmptyBars), tostring(face.showHighlight),
        tostring(face.shouldExpand), tostring(face.showButtonIcons))
    push("  icon set %s", tostring(state.iconSet))
    for _, key in ipairs(ANCHOR_KEYS) do
        local bar, mirror = pageUnit.bars[key], pageUnit.mirrors[key]
        local source = state.overrides[key]
        local first = bar.actionButtons[1]
        push("  %-7s bar shown %-5s action %-5s empty %-5s | mirror shown %-5s source %s", key,
            tostring(bar:IsShown()), tostring(first and first.action), tostring(bar:IsBarEmpty()),
            tostring(mirror:IsShown()), source and (source:GetName() or source.DisplayName or "?") or "none")
    end
    local tracker = pageUnit.PageTracker
    push("  tracker shown %s, width %.0f; icons L %s R %s LR %s", tostring(tracker:IsShown()), tracker:GetWidth(),
        tostring(state.icons.LeftIcon), tostring(state.icons.RightIcon), tostring(state.icons.CenteredIcons))
    push("  shoulders L %s%s, R %s%s; bar alpha top %s left %s right %s bottom %s",
        tostring(state.shoulders.Left), state.shoulders.LeftPressed and " (pressed)" or "",
        tostring(state.shoulders.Right), state.shoulders.RightPressed and " (pressed)" or "",
        tostring(state.barAlpha.top), tostring(state.barAlpha.left), tostring(state.barAlpha.right),
        tostring(state.barAlpha.bottom))
    for i = 1, NUM_KEYS do
        push("  key %d: %s%s", i, keyList(i), pushed[i] and " (down)" or "")
    end
    -- The fields Forever's secure click path reads off a click target.
    local click = pageUnit.bars.top.actionButtons[1].click
    if click then
        for _, key in ipairs({ "popup", "popupDirection", "CalculateAction" }) do
            local secure, taintedBy = issecurevariable(click, key)
            push("  %s.%-16s %s%s", click:GetName(), key, secure and "secure" or "tainted",
                taintedBy and (" by " .. tostring(taintedBy)) or "")
        end
    end
end
