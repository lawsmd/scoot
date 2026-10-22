--------------------------------------------------------------------------------
-- forever/statusbars/display.lua
-- The status bars replica: two Camelot holders, each with a container from
-- Blizzard's template, filled by a Camelot manager on Blizzard's mixin;
-- StatusTrackingBarManager parked; the width, opacity and text applies; the
-- hover surface; and /camelot statusbars.
--
-- Blizzard's manager picks the bars by the client's priorities
-- (StatusTrackingBarInfo.BarPriorities): on Forever experience comes last, so
-- with a watched faction the reputation takes bar 1 and the experience bar 2.
-- The Camelot manager runs the same code over its own two containers, so the
-- replica shows what Blizzard's would.
--------------------------------------------------------------------------------

local addonName, addon = ...

local SB = addon.StatusBars
local Style = SB.Style

local Display = {}
SB.Display = Display

local OWNER = SB.OWNER

local built = false
local claimed = false
local blocked = {}
local MAX_BLOCKED = 6
-- The level PLAYER_LEVEL_UP carries, which UnitLevel can trail for a moment.
local levelUp

local function manager()
    return _G.CamelotStatusTrackingBarManager
end

local function container(index)
    local holder = Style.Holder(index)
    return holder and holder.Container
end

--------------------------------------------------------------------------------
-- Suppression
--------------------------------------------------------------------------------
-- StatusTrackingBarManager is a UIParent child and parks under the hidden
-- holder with both of Blizzard's containers in it. Its events stay
-- registered, which costs nothing. Never released: the Features switch lands
-- at reload.

function Display.Claim()
    if claimed or not SB.IsEnabled() then return end
    local target = _G.StatusTrackingBarManager
    if not (target and addon.NativeFrame) then return end
    if not addon.NativeFrame:IsSuppressed(target) then
        addon.NativeFrame:Suppress(target, OWNER, "park")
    end
    claimed = true
end

--------------------------------------------------------------------------------
-- Applies
--------------------------------------------------------------------------------

--- The container at the bar's Width, the holder at the container's rect, and
--- what Blizzard re-lays on a size change: the bars inside, the dividers
--- between the segments, the rested tick.
function Display.ApplyWidth(index)
    local holder, c = Style.Holder(index), container(index)
    if not (holder and c) then return end
    c.widthPercent = Style.Width(index)
    local width = c:GetExpectedWidth()
    local height = c:GetHeight()
    c:SetSize(width, height)
    holder:SetSize(width, height)
    c:ResizeContainerBars()
    c:UpdateDividers(c:GetExpectedSegments())
    c:UpdateBarTick()
end

--- The holder's alpha. The Dynamic Layouts engine replaces alpha, so while it
--- holds the channel (a dynamic opacity of the bar's own, or a fade in flight)
--- the adapter owns it; a dynamic state silent on opacity reads this setting
--- as its target, and the engine never writes it, so the apply lands it here.
function Display.ApplyOpacity(index)
    local holder = Style.Holder(index)
    if not holder then return end
    if SB.Dynamic and SB.Dynamic.HoldsOpacity(index) then return end
    holder:SetAlpha(Style.Opacity(index) / 100)
end

-- The experience text with the player's level in front when Show Level is
-- on. The client's own UpdateCurrentText writes the text first.
local function wireLevel(index, bar)
    local base = bar.UpdateCurrentText
    bar.UpdateCurrentText = function(self)
        base(self)
        if not Style.ShowLevel(index) then return end
        local level = math.max(UnitLevel("player") or 0, levelUp or 0)
        self:SetBarText(string.format("%s  %s", (_G.UNIT_LEVEL_TEMPLATE or "Level %d"):format(level),
            self.OverlayFrame.Text:GetText() or ""))
    end
end

-- Blizzard's rule (StatusTrackingBarMixin:ShouldBarTextBeDisplayed) with the
-- Camelot manager's lock in place of Blizzard's and Always Show Text added.
-- Set on each bar instance, a Camelot-created frame.
local function wireText(index, c)
    for _, bar in pairs(c.bars or {}) do
        if not bar._camelotTextWired then
            bar._camelotTextWired = true
            bar.ShouldBarTextBeDisplayed = function(self)
                local m = manager()
                return GetCVarBool("xpBarText") or self.textLocked
                    or (m and m:IsTextLocked()) or Style.AlwaysShowText(index)
            end
            if bar.isExpBar then wireLevel(index, bar) end
        end
    end
end

function Display.ApplyText(index)
    local c = container(index)
    if not c then return end
    wireText(index, c)
    for _, bar in pairs(c.bars or {}) do
        -- currXP is set by the bar's first Update; before it there is no text.
        if bar.isExpBar and bar.currXP then bar:UpdateCurrentText() end
    end
    c:UpdateBarTextVisibility()
end

--------------------------------------------------------------------------------
-- Hover
--------------------------------------------------------------------------------
-- Blizzard's bars take the mouse at LOW with a fixed strata, a level or two
-- above the floor, so any mouse-enabled frame over part of a bar takes the
-- hover there; the owner found the bar answering only toward its middle (20
-- October 2026). Each container carries a surface of its own at MEDIUM that
-- takes motion only and hands OnEnter and OnLeave to the bar it shows. Its
-- level sits under the action bar containers (60) and the micro and bag
-- holders (50), so a button over the bar keeps its own tooltip.

local HOVER_LEVEL = 30
local hovers = {}

local function wireHover(index)
    local c = container(index)
    if hovers[index] or not c then return end
    local hover = CreateFrame("Frame", nil, c)
    hover:SetAllPoints(c)
    addon.Strata.ApplyHUD(hover, HOVER_LEVEL)
    hover:SetScript("OnEnter", function(self)
        local bar = c:GetShownBar()
        local onEnter = bar and bar:GetScript("OnEnter")
        if not onEnter then return end
        self.bar = bar
        onEnter(bar)
    end)
    hover:SetScript("OnLeave", function(self)
        local bar = self.bar
        self.bar = nil
        local onLeave = bar and bar:GetScript("OnLeave")
        if onLeave then onLeave(bar) end
    end)
    -- After the scripts: SetScript on OnEnter turns clicks back on, and the
    -- bars take no clicks.
    hover:SetMouseMotionEnabled(true)
    hover:SetMouseClickEnabled(false)
    hovers[index] = hover
end

--------------------------------------------------------------------------------
-- Edit Mode label
--------------------------------------------------------------------------------

--- Blizzard's names for the two systems: bar 1 is the Experience Bar while it
--- holds the experience bar (EditModeStatusTrackingBar1SystemMixin:
--- GetSystemName).
function Display.Label(index)
    if index == 1 then
        local c = container(1)
        local shown = c and c:GetShownBar()
        if shown and shown.isExpBar then return "Experience Bar" end
    end
    return "Status Bar " .. index
end

--- Called by the container's UpdateShownState (mixins.lua) on every change of
--- the bar it shows.
function Display.OnShownBarChanged(index)
    local holder = index and Style.Holder(index)
    if holder then holder.editModeName = Display.Label(index) end
end

--- Edit Mode shows both containers, empty or not, as Blizzard's shows its
--- own: the art is what the player places.
function Display.SetEditing(editing)
    for index = 1, 2 do
        local c = container(index)
        if c then
            c.isInEditMode = editing or nil
            c:UpdateShownState()
            -- A fade in flight finishes on its own: stopping it would strand
            -- the manager's swap, which waits for the animation's end.
            if editing then
                if not c:IsAnimating() then c:SetAlpha(1) end
            elseif not c:IsAnimating() and c.shownBarIndex == StatusTrackingBarInfo.BarsEnum.None then
                c:SetAlpha(0)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

-- The bus hands a handler the event name first, then the payload.
local function onBlocked(event, addonNameBlocked, action)
    if type(action) ~= "string" then return end
    if not action:find("StatusTracking", 1, true) then return end
    table.insert(blocked, 1, string.format("%s %s %s at %.1f", event, tostring(addonNameBlocked), action, GetTime()))
    if #blocked > MAX_BLOCKED then table.remove(blocked) end
end

local function fading(c)
    return c.FadeInAnimation:IsPlaying() or c.FadeOutAnimation:IsPlaying()
        or c.MaxLevelFadeOutAnimation:IsPlaying()
end

-- A container that shows a bar at less than full alpha with no fade in
-- flight fades in now. The guard reads the fade groups, not IsAnimating,
-- which also counts the bar's own value animation and would leave the
-- container dark behind a fill that is still ticking.
local function settleFades()
    for index = 1, 2 do
        local c = container(index)
        if c and c.shownBarIndex ~= StatusTrackingBarInfo.BarsEnum.None
            and not fading(c) and c:GetAlpha() < 1 then
            c.FadeInAnimation:Restart()
        end
    end
end

function Display.Build()
    local m = manager()
    -- The frames exist on Forever whatever the switch says. A feature off
    -- never registers the manager's events (mixins.lua, RegisterEvents), so
    -- the holders stay hidden and the containers empty.
    if not SB.IsEnabled() then return end
    if built then return end
    if not (m and container(1) and container(2)) then return end

    addon.Events.On(OWNER, "ADDON_ACTION_BLOCKED", onBlocked)
    addon.Events.On(OWNER, "ADDON_ACTION_FORBIDDEN", onBlocked)
    addon.Events.On(OWNER, "PLAYER_LEVEL_UP", function(_, level)
        levelUp = tonumber(level)
        for index = 1, 2 do Display.ApplyText(index) end
    end)
    built = true

    Display.Claim()
    for index = 1, 2 do
        local holder = Style.Holder(index)
        addon.RegisterPetBattleFrame(holder)
        holder:Show()
        wireHover(index)
    end
    Style.Apply()
    -- The first fill, with the holders drawing: the fade lands on a visible
    -- container, as Blizzard's does under its always-visible manager.
    m:RegisterBlizzardEvents()
    if UnitExists("player") then m:UpdateBarsShown() end
    settleFades()
    for index = 1, 2 do
        Display.OnShownBarChanged(index)
        if SB.EditMode then SB.EditMode.Register(index, Style.Holder(index)) end
        if SB.Dynamic then SB.Dynamic.Register(index, Style.Holder(index)) end
    end
end

function Display.IsBuilt()
    return built
end

addon.Events.OnWorldEntered(function()
    Display.Build()
end)

--------------------------------------------------------------------------------
-- /camelot statusbars
--------------------------------------------------------------------------------

local function frameLine(push, label, frame)
    if not frame then
        push("  %s: absent", label)
        return
    end
    local ok, text = pcall(function()
        local parent = frame:GetParent()
        local point, rel, relPoint, x, y = frame:GetPoint(1)
        return string.format("parent %s, shown %s, visible %s, alpha %.2f, size %.0f x %.0f, strata %s, point %s to %s %s (%.1f, %.1f)",
            parent and parent:GetName() or tostring(parent), tostring(frame:IsShown()), tostring(frame:IsVisible()),
            frame:GetAlpha(), frame:GetWidth(), frame:GetHeight(), tostring(frame:GetFrameStrata()),
            tostring(point), rel and rel.GetName and rel:GetName() or tostring(rel), tostring(relPoint), x or 0, y or 0)
    end)
    push("  %s: %s", label, ok and text or ("unreadable: " .. tostring(text)))
end

local function barName(index)
    for name, value in pairs(StatusTrackingBarInfo.BarsEnum) do
        if value == index then return name end
    end
    return tostring(index)
end

function Display.Dump()
    local lines, push = addon.DebugLines()
    push("Camelot status bars: enabled %s, built %s, lockdown %s, editing %s",
        tostring(SB.IsEnabled()), tostring(built), tostring(InCombatLockdown()),
        tostring(addon.EditMode and addon.EditMode.IsEditing and addon.EditMode.IsEditing()))
    local blizzard = _G.StatusTrackingBarManager
    frameLine(push, "StatusTrackingBarManager", blizzard)
    push("  Blizzard's manager parked: %s", tostring(blizzard and addon.NativeFrame and addon.NativeFrame:IsSuppressed(blizzard)))
    local m = manager()
    push("  Camelot manager: %s, %d containers", m and "exists" or "absent", m and m.barContainers and #m.barContainers or 0)
    if StatusTrackingBarInfo and m then
        local order = {}
        for _, index in pairs(StatusTrackingBarInfo.BarsEnum) do
            if index ~= StatusTrackingBarInfo.BarsEnum.None then
                order[#order + 1] = string.format("%s %s (priority %d)", barName(index),
                    m:CanShowBar(index) and "can show" or "no", m:GetBarPriority(index))
            end
        end
        table.sort(order)
        push("  bars: %s", table.concat(order, "; "))
    end
    for index = 1, 2 do
        local c = container(index)
        push("  bar %d, %s: width %d%%, opacity %d%%, always show text %s, show level %s",
            index, Display.Label(index), Style.Width(index), Style.Opacity(index),
            tostring(Style.AlwaysShowText(index)), tostring(Style.ShowLevel(index)))
        frameLine(push, "holder", Style.Holder(index))
        frameLine(push, "container", c)
        frameLine(push, "hover", hovers[index])
        if c then
            push("    shows %s, pending %s, animating %s, fade in %s, fade out %s, in Edit Mode %s",
                barName(c.shownBarIndex), tostring(c.pendingBarToShowIndex and barName(c.pendingBarToShowIndex)),
                tostring(c:IsAnimating()), tostring(c.FadeInAnimation:IsPlaying()),
                tostring(c.FadeOutAnimation:IsPlaying()), tostring(c.isInEditMode))
        end
        if SB.Dynamic then push("    dynamic layouts: %s", SB.Dynamic.Describe(index)) end
    end
    push("  blocked actions naming a status bar (%d):", #blocked)
    for _, line in ipairs(blocked) do push("    %s", line) end
    addon.DebugShowWindow("Camelot status bars", lines)
end

addon:RegisterSlashCommand({
    name = "statusbars",
    help = "show the status bars replica: the two bars, what each shows, Blizzard's parked manager and the blocked actions",
    handler = function() Display.Dump() end,
})
