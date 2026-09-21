--------------------------------------------------------------------------------
-- forever/objectivetracker/tracker.lua
-- Camelot's objective tracker: the wiring that makes CamelotObjectiveTracker
-- (frames.xml) the tracker the player sees, CamelotCurrentObjectiveTracker the
-- Current Objectives pane beside it, and Blizzard's ObjectiveTrackerFrame an
-- empty, parked frame.
--
-- The tracker is Blizzard's code on Camelot-owned frames. ObjectiveTrackerManager
-- takes any number of containers and assigns modules to one with
-- SetModuleContainer; a module singleton that never receives a container never
-- registers its events and every MarkDirty on it is a no-op. So this file adds
-- the two Camelot containers, hands them Camelot's module frames in Blizzard's
-- order (the Current twin to the pane, the rest to the tracker), and keeps
-- Blizzard's frame from ever getting modules with SetCanAddModules, which is
-- what Blizzard_Kiosk/Housing/Game.lua does for the same reason.
--
-- Height, opacity, text size and the rest of the look are Camelot settings,
-- applied by style.lua, which loads before this file on both clients; its
-- Install runs at the end of Setup below, and current.lua's after it.
--------------------------------------------------------------------------------

local addonName, addon = ...

local DB = addon.DB

addon.ObjectiveTracker = addon.ObjectiveTracker or {}
local OT = addon.ObjectiveTracker

local OWNER = "camelotObjectiveTracker"
local NAV_KEY = "objectiveTracker"

DB.RegisterModule("objectiveTracker", true)
DB.RegisterDefaults({
    ["objectiveTracker.enabled"] = true,
})

addon.Features.Register({
    group = "interface", groupLabel = "Interface",
    id = "objectiveTracker", label = "Objective Tracker",
    path = "objectiveTracker.enabled",
})

-- Held for the session: the Features page changes it at the reload, and a
-- feature off at login never touches Blizzard's tracker.
function OT.IsEnabled()
    return DB.IsModuleEnabled("objectiveTracker")
        and DB.SessionGet("objectiveTracker.enabled") == true
end

--------------------------------------------------------------------------------
-- Panes
--------------------------------------------------------------------------------
-- The two containers, each free-positioned in Edit Mode under its own key,
-- with positions per layout in layout.<key>.positions, the unit frames'
-- shape. The tracker's default is the Modern preset's anchor for Blizzard's
-- ObjectiveTracker system (Blizzard_EditMode/Mainline/EditModePresetLayouts.lua);
-- the pane's is a draft above the character, clear of the minimap.

local PANES = {
    {
        frameName = "CamelotObjectiveTracker", key = NAV_KEY, name = "Objective Tracker",
        default = { point = "TOPRIGHT", x = -110, y = -275 }, styleKey = "MAIN",
    },
    {
        frameName = "CamelotCurrentObjectiveTracker", key = "currentObjectives", name = "Current Objectives",
        default = { point = "TOP", x = 0, y = -120 }, styleKey = "CURRENT",
    },
}

local function paneFrame(pane)
    return _G[pane.frameName]
end

local function paneOf(container)
    for _, pane in ipairs(PANES) do
        if paneFrame(pane) == container then return pane end
    end
    return PANES[1]
end

local function eachPane(fn)
    for _, pane in ipairs(PANES) do
        local frame = paneFrame(pane)
        if frame then fn(pane, frame) end
    end
end

--------------------------------------------------------------------------------
-- Modules
--------------------------------------------------------------------------------

-- Blizzard's order (Blizzard_ObjectiveTrackerManager.lua, Init), each name a
-- Camelot twin from frames.xml except the first: Blizzard's own Scenario module
-- is re-homed as it is, until its inline XML is transcribed. The Current twin
-- sits after the Quest twin it is a third instance of; it goes to the pane.
local CURRENT_MODULE = "CamelotCurrentQuestObjectiveTracker"

local ORDER = {
    "ScenarioObjectiveTracker",
    "CamelotUIWidgetObjectiveTracker",
    "CamelotCampaignQuestObjectiveTracker",
    "CamelotQuestObjectiveTracker",
    CURRENT_MODULE,
    "CamelotAdventureObjectiveTracker",
    "CamelotAchievementObjectiveTracker",
    "CamelotMonthlyActivitiesObjectiveTracker",
    "CamelotInitiativeTasksObjectiveTracker",
    "CamelotProfessionsRecipeTracker",
    "CamelotBonusObjectiveTracker",
    "CamelotWorldQuestObjectiveTracker",
}

-- Blizzard singleton -> Camelot twins. Blizzard code outside the tracker
-- dirties the singletons by name (ContentTrackingManager, the UI widget layout
-- callback); a parked singleton swallows that, so each one forwards. The
-- quest singleton has two twins.
local TWINS = {
    UIWidgetObjectiveTracker          = { "CamelotUIWidgetObjectiveTracker" },
    CampaignQuestObjectiveTracker     = { "CamelotCampaignQuestObjectiveTracker" },
    QuestObjectiveTracker             = { "CamelotQuestObjectiveTracker", CURRENT_MODULE },
    AdventureObjectiveTracker         = { "CamelotAdventureObjectiveTracker" },
    AchievementObjectiveTracker       = { "CamelotAchievementObjectiveTracker" },
    MonthlyActivitiesObjectiveTracker = { "CamelotMonthlyActivitiesObjectiveTracker" },
    InitiativeTasksObjectiveTracker   = { "CamelotInitiativeTasksObjectiveTracker" },
    ProfessionsRecipeTracker          = { "CamelotProfessionsRecipeTracker" },
    BonusObjectiveTracker             = { "CamelotBonusObjectiveTracker" },
    WorldQuestObjectiveTracker        = { "CamelotWorldQuestObjectiveTracker" },
}

-- The modules that lay out quest item buttons. Each gets its own settings
-- table naming the slot template: the mixin's table is shared by reference
-- across every instance and keyed by tostring() in the module, so it is
-- shadowed, never edited.
local ITEM_SLOT_MODULES = {
    "CamelotQuestObjectiveTracker",
    "CamelotCampaignQuestObjectiveTracker",
    CURRENT_MODULE,
    "CamelotBonusObjectiveTracker",
    "CamelotWorldQuestObjectiveTracker",
}

-- The quest modules an auto-quest popup expands.
local QUEST_TWINS = {
    "CamelotQuestObjectiveTracker",
    "CamelotCampaignQuestObjectiveTracker",
    CURRENT_MODULE,
}

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

local didSetup = false

local function Setup()
    if didSetup then return end
    didSetup = true

    local container = CamelotObjectiveTracker
    local pane = CamelotCurrentObjectiveTracker
    local manager = ObjectiveTrackerManager

    for _, name in ipairs(ITEM_SLOT_MODULES) do
        local module = _G[name]
        if module then
            module.questItemButtonSettings = {
                template = "CamelotQuestItemSlotTemplate", offsetX = 0, offsetY = 0,
            }
        end
    end

    manager:AddContainer(container)
    if pane then manager:AddContainer(pane) end

    local modules = {}
    for _, name in ipairs(ORDER) do
        local module = _G[name]
        if module then
            modules[#modules + 1] = module
        end
    end
    manager:AssignModulesOrder(modules)
    local current = _G[CURRENT_MODULE]
    for _, module in ipairs(modules) do
        local target = container
        if pane and module == current then target = pane end
        manager:SetModuleContainer(module, target)
    end

    for blizzardName, twinNames in pairs(TWINS) do
        local singleton = _G[blizzardName]
        if singleton then
            for _, twinName in ipairs(twinNames) do
                local twin = _G[twinName]
                if twin then
                    hooksecurefunc(singleton, "MarkDirty", function() twin:MarkDirty() end)
                end
            end
        end
    end

    -- QuestFrame and SplashFrame add and remove auto-quest popups on the
    -- singleton. The popup list is the client's and the item ids live in a
    -- table both instances share, so the twins draw them; what the singleton
    -- swallows is the expand. The sound has already played once.
    if QuestObjectiveTracker then
        hooksecurefunc(QuestObjectiveTracker, "AddAutoQuestPopUp", function()
            for _, name in ipairs(QUEST_TWINS) do
                local twin = _G[name]
                if twin then twin:ForceExpand() end
            end
        end)
    end

    -- SplashFrame gates auto-quest popups on its shown state and calls
    -- ObjectiveTrackerFrame:Update() as it opens and closes.
    if ObjectiveTrackerFrame then
        hooksecurefunc(ObjectiveTrackerFrame, "Update", function()
            container:MarkDirty()
            if pane then pane:MarkDirty() end
        end)
    end

    -- The look, once the modules are in: height, scale, background, text
    -- size, headers, text, and the combat fade with its events. Then the
    -- routing between the panes and its events.
    if OT.Style then OT.Style.Install() end
    if OT.Current then OT.Current.Install() end
end

--------------------------------------------------------------------------------
-- Suppression
--------------------------------------------------------------------------------
-- ObjectiveTrackerFrame is a top-level frame, so it is parked (a hidden
-- parent), the method the unit frames use. With no modules it never shows
-- itself; the park is for Edit Mode, which shows every system frame. Never
-- released: the feature lands at reload.

local suppressed = false

function OT.ApplySuppression()
    if suppressed or not OT.IsEnabled() then return end
    if not (ObjectiveTrackerFrame and addon.NativeFrame) then return end
    addon.NativeFrame:Suppress(ObjectiveTrackerFrame, OWNER, "park")
    suppressed = true
end

function OT.IsSuppressed()
    return suppressed
end

--------------------------------------------------------------------------------
-- Edit Mode
--------------------------------------------------------------------------------
-- The frames are unprotected, so a position applies in combat too.

local store = {
    get = function(key, layoutName)
        local entry = DB.GetLayout(key)
        local positions = entry and entry.positions
        return positions and positions[layoutName] or nil
    end,
    set = function(key, layoutName, point, x, y)
        local entry = DB.GetLayout(key) or {}
        entry.positions = entry.positions or {}
        entry.positions[layoutName] = { point = point, x = x, y = y }
        DB.SetLayout(key, entry)
    end,
}

local function ApplyPosition(frame, point, x, y)
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, point, x, y)
    if OT.Items then OT.Items.Reposition() end
    return false
end

local registered = false

local function RegisterEditMode()
    if registered then return end
    if not (addon.EditMode and addon.EditMode.RegisterPositionable) then return end
    registered = true

    eachPane(function(pane, frame)
        frame.editModeName = pane.name
        local Style = OT.Style
        local selection = addon.EditMode.RegisterPositionable(frame, {
            key = pane.key,
            default = pane.default,
            restoreDefault = true,
            store = store,
            apply = ApplyPosition,
            -- The dialog carries the sliders Blizzard's tracker dialog has,
            -- plus scale, from style.lua.
            brand = { navKey = pane.key, componentId = pane.key,
                      mirror = Style and Style.EditModeMirror(Style[pane.styleKey]) },
        })
        if selection then
            -- The library anchors the selection box to the frame's own edges.
            -- Blizzard's EditModeObjectiveTrackerSystemMixin:AnchorSelectionFrame
            -- starts it 30 to the left, where the POI buttons and the
            -- background's left margin sit; without that the box cuts the
            -- content's left edge.
            selection:ClearAllPoints()
            selection:SetPoint("TOPLEFT", frame, "TOPLEFT", -30, 0)
            selection:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
            OT.WatchDrags(selection, frame)
        end
    end)

    addon.EditMode.OnEditMode(OWNER, {
        enter = function()
            -- NativeFrame skips the re-parent while the manager is open, so
            -- entering defers the claim and leaving pays it.
            addon.NativeFrame:Reapply()
            eachPane(function(_, frame)
                OT.EnsurePlaced("editmode enter", false, frame)
                -- An empty container hides itself except while Edit Mode is
                -- active; this is the update that shows it for dragging.
                frame:Update()
            end)
        end,
        exit = function()
            addon.NativeFrame:Reapply()
            eachPane(function(_, frame)
                OT.EnsurePlaced("editmode exit", false, frame)
            end)
        end,
    })
end

--------------------------------------------------------------------------------
-- Placement
--------------------------------------------------------------------------------
-- A frame with no rect draws nothing and takes no click, and everything
-- inside it goes with it: the modules, and the Edit Mode selection box. On
-- the beta the first drag in Edit Mode left the tracker with GetLeft() nil,
-- which LibEditMode's normalizePosition reads unguarded (19 September 2026;
-- the shared module list was the cause found, the heal stays as a guard).
-- So each container heals itself: any pass that finds no rect re-applies
-- the stored position, or the default, and the selection box's drag is
-- watched so the moment the rect goes is on record.

local HEAL_LOG_MAX = 6
local DRAG_LOG_MAX = 3

local healLog = {}
local dragLog = {}

local function HasRect(frame)
    return frame:GetLeft() ~= nil
end

local function describePoint(frame)
    local n = frame:GetNumPoints()
    if n == 0 then return "no points" end
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    local rel = relativeTo and (relativeTo.GetName and relativeTo:GetName() or "?") or "screen"
    return string.format("%d point(s), %s to %s %s at %.1f, %.1f",
        n, tostring(point), rel, tostring(relativePoint), x or 0, y or 0)
end

local function snapshot(stage, c)
    local left, top = c:GetLeft(), c:GetTop()
    local parent = c:GetParent()
    return {
        stage = stage,
        frame = c:GetName() or "?",
        rect = left and string.format("%.0f, %.0f", left, top) or "none",
        anchor = describePoint(c),
        parent = parent and (parent.GetName and parent:GetName() or "?") or "nil",
        shown = c:IsShown(), visible = c:IsVisible(),
        movable = c:IsMovable(), userPlaced = c:IsUserPlaced(),
        w = c:GetWidth(), h = c:GetHeight(),
    }
end

local function pushLog(log, max, entry)
    log[#log + 1] = entry
    if #log > max then table.remove(log, 1) end
end

--- Re-applies a container's position when it has no rect. `force` re-applies
--- regardless (the reset command); `container` defaults to the tracker.
--- Returns true when something was applied.
function OT.EnsurePlaced(reason, force, container)
    container = container or CamelotObjectiveTracker
    if not container then return false end
    if not force and HasRect(container) then return false end

    local before = snapshot(reason, container)
    if addon.EditMode and addon.EditMode.RestorePositionable then
        addon.EditMode.RestorePositionable(container)
    end
    if not HasRect(container) then
        local d = paneOf(container).default
        ApplyPosition(container, d.point, d.x, d.y)
    end
    before.after = snapshot(reason, container).rect
    pushLog(healLog, HEAL_LOG_MAX, before)
    return true
end

--- Every container layout: heal, re-dress what the layout rewrote, then
--- re-place the item buttons.
function OT.OnContainerUpdated(container)
    OT.EnsurePlaced("update", false, container)
    if OT.Style then OT.Style.OnUpdate() end
    if OT.Items then OT.Items.Reposition() end
end

--- Hooks on a LibEditMode selection box. The library's own scripts run
--- first; these observe, and a ticker follows the drag frame by frame so a
--- rect lost mid-drag is caught there, with the frame stopped and re-placed
--- before the library reads it on the drop.
function OT.WatchDrags(selection, container)
    container = container or CamelotObjectiveTracker
    local current, ticker

    local function stopTicker()
        if ticker then ticker:Cancel() ticker = nil end
    end

    selection:HookScript("OnMouseDown", function()
        current = { snapshot("mousedown", container) }
        pushLog(dragLog, DRAG_LOG_MAX, current)
    end)

    selection:HookScript("OnDragStart", function()
        current = current or {}
        current[#current + 1] = snapshot("dragstart", container)
        if not HasRect(container) then
            container:StopMovingOrSizing()
            OT.EnsurePlaced("dragstart", false, container)
            return
        end
        stopTicker()
        ticker = C_Timer.NewTicker(0, function()
            if not HasRect(container) then
                current[#current + 1] = snapshot("rect lost mid-drag", container)
                container:StopMovingOrSizing()
                OT.EnsurePlaced("mid-drag", false, container)
                stopTicker()
            elseif not IsMouseButtonDown("LeftButton") then
                -- The drop has happened or is happening; one more tick and
                -- the library's drop handler has run.
                stopTicker()
                C_Timer.After(0, function()
                    current[#current + 1] = snapshot("after drop", container)
                    OT.EnsurePlaced("after drop", false, container)
                end)
            end
        end)
    end)

    selection:HookScript("OnDragStop", function()
        current = current or {}
        current[#current + 1] = snapshot("dragstop", container)
    end)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

addon.Events.OnAddonLoaded(addonName, function()
    if not OT.IsEnabled() then return end
    if not (ObjectiveTrackerManager and CamelotObjectiveTracker) then return end

    -- Before Blizzard's Init, which runs on the first PLAYER_ENTERING_WORLD
    -- after VARIABLES_LOADED: its container gets added and its module loop is
    -- skipped. The hook fires inside Init, after that add and before its
    -- closing UpdateAll, which then updates the Camelot containers too. Init
    -- itself cannot be hooked: EventUtil captured the function value at load.
    ObjectiveTrackerManager:SetCanAddModules(false)
    hooksecurefunc(ObjectiveTrackerManager, "AddContainer", function(_, container)
        if container == ObjectiveTrackerFrame then
            Setup()
        end
    end)
end)

addon.Events.OnWorldEntered(function()
    if not OT.IsEnabled() then return end
    if not (ObjectiveTrackerManager and CamelotObjectiveTracker) then return end

    OT.ApplySuppression()
    RegisterEditMode()

    -- Belt and braces: had Init already run, its AddContainer was missed.
    C_Timer.After(0, function()
        if not didSetup and ObjectiveTrackerManager.containers[ObjectiveTrackerFrame] then
            Setup()
        end
    end)
end)

addon.Events.On(OWNER, "PLAYER_ENTERING_WORLD", function()
    OT.ApplySuppression()
end)

--------------------------------------------------------------------------------
-- /camelot tracker
--------------------------------------------------------------------------------

local function pushContainer(push, label, container)
    push("[%s] %s", label, container and container:GetName() or "nil")
    if not container then
        push("")
        return
    end
    push("  shown %s, visible %s, collapsed %s, movable %s, user placed %s",
        tostring(container:IsShown()), tostring(container:IsVisible()),
        tostring(container:IsCollapsed()), tostring(container:IsMovable()),
        tostring(container:IsUserPlaced()))
    local parent = container:GetParent()
    push("  parent %s", parent and (parent.GetName and parent:GetName() or "?") or "nil")
    local w, h = container:GetSize()
    local left, top = container:GetLeft(), container:GetTop()
    push("  size %.0f x %.0f, editModeHeight %s, rect %s", w, h, tostring(container.editModeHeight),
        left and string.format("left %.0f top %.0f", left, top) or "NONE")
    push("  anchor: %s", describePoint(container))
    push("  modules:")
    container:ForEachModule(function(module)
        local state = module.state
        push("    %-44s order %-2s state %-2s height %-5s shown %s",
            module:GetName() or "?", tostring(module.uiOrder), tostring(state),
            tostring(module:GetContentsHeight()), tostring(module:IsShown()))
    end)
    push("")
end

local function pushSettings(push, Style, pane, label)
    push("settings (%s): height %s, scale %s, opacity %s, text size %s", label,
        tostring(Style.Height(pane)), tostring(Style.Scale(pane)),
        tostring(Style.BackgroundAlpha(pane)), tostring(Style.TextSize(pane)))
    for _, key in ipairs(Style.TEXT_KEYS) do
        push("  %-18s face %s, style %s, color %s", key,
            tostring(Style.PaneGet(pane, key, "fontFace")), tostring(Style.PaneGet(pane, key, "style")),
            tostring(Style.PaneGet(pane, key, "colorMode")))
    end
    push("  headers hidden %s, tinted %s",
        tostring(Style.PaneGet(pane, "hideHeaderBackgrounds")),
        tostring(Style.PaneGet(pane, "tintHeaderBackgroundEnable")))
end

local function dumpTracker()
    local lines, push = addon.DebugLines("=== Camelot objective tracker ===", "")
    push("enabled %s, setup %s, parked %s, edit mode registered %s",
        tostring(OT.IsEnabled()), tostring(didSetup), tostring(suppressed), tostring(registered))
    if ObjectiveTrackerManager then
        push("manager canAddModules %s, backgroundAlpha %s",
            tostring(ObjectiveTrackerManager.canAddModules),
            tostring(ObjectiveTrackerManager.backgroundAlpha))
    end
    -- One list for two containers is the mixin's shared table (mixins.lua,
    -- OnLoad); the dump shows both lists complete when it is.
    if ObjectiveTrackerFrame and CamelotObjectiveTracker then
        push("containers share one modules table: blizzard/tracker %s, blizzard/pane %s, tracker/pane %s",
            tostring(ObjectiveTrackerFrame.modules == CamelotObjectiveTracker.modules),
            tostring(CamelotCurrentObjectiveTracker ~= nil
                and ObjectiveTrackerFrame.modules == CamelotCurrentObjectiveTracker.modules),
            tostring(CamelotCurrentObjectiveTracker ~= nil
                and CamelotObjectiveTracker.modules == CamelotCurrentObjectiveTracker.modules))
    end
    if OT.Style then
        local Style = OT.Style
        local lineSize
        if ObjectiveTrackerLineFont then
            lineSize = select(2, ObjectiveTrackerLineFont:GetFont())
        end
        push("line font at %s; instance combat opacity %s", tostring(lineSize),
            tostring(Style.Get("opacityInInstanceCombat")))
        pushSettings(push, Style, Style.MAIN, "tracker")
        pushSettings(push, Style, Style.CURRENT, "pane")
    end
    push("")
    pushContainer(push, "camelot", CamelotObjectiveTracker)
    pushContainer(push, "current", CamelotCurrentObjectiveTracker)
    pushContainer(push, "blizzard", ObjectiveTrackerFrame)
    if OT.Current then
        OT.Current.Dump(push)
    end
    if OT.Items then
        OT.Items.Dump(push)
    end

    local function pushSnapshot(indent, snap)
        push("%s%-18s %-30s rect %-14s %s", indent, snap.stage, snap.frame, snap.rect, snap.anchor)
        push("%s  parent %s, shown %s, visible %s, movable %s, user placed %s, %.0f x %.0f%s",
            indent, snap.parent, tostring(snap.shown), tostring(snap.visible),
            tostring(snap.movable), tostring(snap.userPlaced), snap.w, snap.h,
            snap.after and (", healed to " .. snap.after) or "")
    end
    push("")
    push("heals (%d):", #healLog)
    for _, snap in ipairs(healLog) do pushSnapshot("  ", snap) end
    push("")
    push("drags (%d):", #dragLog)
    for i, drag in ipairs(dragLog) do
        push("  drag %d", i)
        for _, snap in ipairs(drag) do pushSnapshot("    ", snap) end
    end
    addon.DebugShowWindow("Camelot objective tracker", lines)
end

addon:RegisterSlashCommand({
    name = "tracker",
    help = "[reset | pin <questID> | pin clear] dump the objective tracker: containers, modules, park, "
        .. "the current set, item buttons, heals, drags; reset re-applies both positions; "
        .. "pin puts a watched quest into the Current Objectives pane or lets it go",
    handler = function(sub)
        local verb, rest = (sub or ""):match("^%s*(%S*)%s*(.*)$")
        if verb == "reset" then
            eachPane(function(_, frame)
                OT.EnsurePlaced("reset", true, frame)
                frame:Update()
            end)
            return
        elseif verb == "pin" and OT.Current then
            if rest == "clear" then
                OT.Current.Clear()
            else
                local questID = tonumber(rest)
                if questID then OT.Current.Pin(questID) end
            end
            return
        end
        dumpTracker()
    end,
})
