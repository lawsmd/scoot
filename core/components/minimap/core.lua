--------------------------------------------------------------------------------
-- core.lua - Minimap namespace, state, shape and mask, border overlay
--
-- Namespace, state, constants, helpers, shape/mask, border overlay,
-- dock visibility, zone event handler, ADDON_LOADED handler,
-- styling orchestrator, component registration, and exports.
--
-- All overlays are parented to UIParent and anchored to Minimap to avoid taint.
-- Zero-Touch: Does nothing until user explicitly configures settings.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Namespace setup
addon.Minimap = addon.Minimap or {}
local MM = addon.Minimap

-- Module-level state
local minimapOverlays = {}  -- Weak-keyed table for overlay frames
setmetatable(minimapOverlays, { __mode = "k" })

-- Blizzard element hiding state
local blizzardZoneTextHidden = false
local blizzardClockHidden = false
local blizzardDockHidden = false

-- Constants
local PVP_COLORS = {
    sanctuary = {0.41, 0.8, 0.94, 1},  -- Light blue
    friendly = {0.1, 1, 0.1, 1},       -- Green
    hostile = {1, 0.1, 0.1, 1},        -- Red
    arena = {1, 0.1, 0.1, 1},          -- Red
    contested = {1, 0.7, 0, 1},        -- Orange
    combat = {1, 0.1, 0.1, 1},         -- Red
    normal = {1, 0.82, 0, 1},          -- Gold (default)
}

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

local function getMinimapDB()
    local comp = addon.Components and addon.Components["minimapStyle"]
    if comp and comp.db then
        -- Check for proxy DB (Zero-Touch)
        if addon.IsComponentUnconfigured(comp) then
            return nil
        end
        return comp.db
    end
end

local function ensureOverlayTable()
    local minimap = _G.Minimap
    if not minimap then return nil end
    if not minimapOverlays[minimap] then
        minimapOverlays[minimap] = {}
    end
    return minimapOverlays[minimap]
end

-- Promote shared helpers to namespace for sub-files
MM._getMinimapDB = getMinimapDB
MM._ensureOverlayTable = ensureOverlayTable
MM._minimapOverlays = minimapOverlays
MM._PVP_COLORS = PVP_COLORS

--------------------------------------------------------------------------------
-- Shape Application
--------------------------------------------------------------------------------

-- Track if square mode has ever been applied (to know when to restore)
local hasAppliedSquare = false

-- Circular mask texture (same as what HybridMinimap uses)
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SQUARE_MASK = "Interface\\BUTTONS\\WHITE8X8"

-- Refresh all LibDBIcon minimap button positions
local function RefreshMinimapButtonPositions()
    local LibDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if LibDBIcon and LibDBIcon.objects then
        for name, button in pairs(LibDBIcon.objects) do
            local pos = button.db and button.db.minimapPos or button.minimapPos or 225
            LibDBIcon:Refresh(name)
        end
    end
end

local function ApplyMinimapShape(db)
    local minimap = _G.Minimap
    if not minimap then return end

    local shapeChanged = false
    local newShape = db and db.mapShape or "default"

    if newShape == "square" then
        -- Apply square mask
        minimap:SetMaskTexture(SQUARE_MASK)
        hasAppliedSquare = true
        shapeChanged = true

        -- Hide circular compass border art
        if MinimapCompassTexture then
            MinimapCompassTexture:SetAlpha(0)
        end

        -- Override GetMinimapShape for addon compatibility
        _G.GetMinimapShape = function() return "SQUARE" end

        -- HybridMinimap compatibility
        if HybridMinimap then
            pcall(function()
                HybridMinimap.MapCanvas:SetUseMaskTexture(false)
                if HybridMinimap.CircleMask then
                    HybridMinimap.CircleMask:SetTexture(SQUARE_MASK)
                end
                HybridMinimap.MapCanvas:SetUseMaskTexture(true)
            end)
        end
    elseif hasAppliedSquare then
        -- Only restore if square mode was previously applied
        -- This maintains Zero-Touch for users who never changed the shape
        minimap:SetMaskTexture(CIRCLE_MASK)
        shapeChanged = true

        -- Restore circular compass border art
        if MinimapCompassTexture then
            MinimapCompassTexture:SetAlpha(1)
        end

        -- Restore GetMinimapShape for addon compatibility
        _G.GetMinimapShape = function() return "ROUND" end

        -- HybridMinimap compatibility - restore circular mask
        if HybridMinimap then
            pcall(function()
                HybridMinimap.MapCanvas:SetUseMaskTexture(false)
                if HybridMinimap.CircleMask then
                    HybridMinimap.CircleMask:SetTexture(CIRCLE_MASK)
                end
                HybridMinimap.MapCanvas:SetUseMaskTexture(true)
            end)
        end
    end

    -- Refresh minimap button positions after shape change
    if shapeChanged then
        C_Timer.After(0.1, RefreshMinimapButtonPositions)
    end
    -- If db is nil or mapShape is "default" and square was never applied,
    -- leave the minimap completely untouched (Zero-Touch principle)
end

--------------------------------------------------------------------------------
-- Blizzard Element Hiding (Zone Text, Clock)
--------------------------------------------------------------------------------

-- Hide-enforcement (core/enforce.lua): each key reads the minimap settings
-- live and hides with Hide, as the buttons' Show hooks did before.
local Enforce = addon.Enforce
local function hideElement(frame)
    local hide = frame.HideBase or frame.Hide
    if hide then hide(frame) end
end
local ZONE_TEXT_HIDE_OPTS = {
    methods = { "Show" },
    apply = hideElement,
    when = function()
        local db = getMinimapDB()
        if not db then return false end
        return not not (db.zoneTextHide or (db.zoneTextPosition and db.zoneTextPosition ~= "dock"))
    end,
}
local CLOCK_HIDE_OPTS = {
    methods = { "Show" },
    apply = hideElement,
    when = function()
        local db = getMinimapDB()
        if not db then return false end
        return not not (db.clockHide or (db.clockPosition and db.clockPosition ~= "dock"))
    end,
}
local DOCK_HIDE_OPTS = {
    methods = { "Show" },
    apply = hideElement,
    when = function()
        local db = getMinimapDB()
        return db ~= nil and not not db.dockHide
    end,
}

local function HideBlizzardZoneText()
    -- Hide Blizzard's zone text button (the clickable text above minimap)
    if MinimapZoneTextButton then
        MinimapZoneTextButton:Hide()
        blizzardZoneTextHidden = true
        Enforce.Install(MinimapZoneTextButton, "minimapZoneText", ZONE_TEXT_HIDE_OPTS)
    end

    -- Also hide the zone text in the MinimapCluster if accessible
    if MinimapCluster and MinimapCluster.ZoneTextButton then
        MinimapCluster.ZoneTextButton:Hide()
        blizzardZoneTextHidden = true
    end
end

local function ShowBlizzardZoneText()
    if not blizzardZoneTextHidden then return end
    blizzardZoneTextHidden = false

    -- Show Blizzard's zone text button
    if MinimapZoneTextButton then
        MinimapZoneTextButton:Show()
    end

    -- Also show the zone text in the MinimapCluster if accessible
    if MinimapCluster and MinimapCluster.ZoneTextButton then
        MinimapCluster.ZoneTextButton:Show()
    end
end

local function HideBlizzardClock()
    -- Hide Blizzard's clock button (only if it exists)
    if TimeManagerClockButton then
        TimeManagerClockButton:Hide()
        blizzardClockHidden = true
        Enforce.Install(TimeManagerClockButton, "minimapClock", CLOCK_HIDE_OPTS)
    end
    -- Note: If TimeManagerClockButton doesn't exist yet, the TimeManager ADDON_LOADED
    -- handler will call this again when Blizzard_TimeManager loads
end

local function ShowBlizzardClock()
    if not blizzardClockHidden then return end
    blizzardClockHidden = false

    -- Show Blizzard's clock button
    if TimeManagerClockButton then
        TimeManagerClockButton:Show()
    end
end

-- Promote hiding functions to namespace for sub-files
MM._HideBlizzardZoneText = HideBlizzardZoneText
MM._ShowBlizzardZoneText = ShowBlizzardZoneText
MM._HideBlizzardClock = HideBlizzardClock
MM._ShowBlizzardClock = ShowBlizzardClock

--------------------------------------------------------------------------------
-- Dock Visibility (BorderTop, Calendar, Tracking, Addon Compartment)
--------------------------------------------------------------------------------

-- Helper to hide tracking elements and keep the background hidden
local function HideTrackingElements()
    if not MinimapCluster or not MinimapCluster.Tracking then return end

    if MinimapCluster.Tracking.Button then
        MinimapCluster.Tracking.Button:Hide()
    end
    if MinimapCluster.Tracking.Background then
        MinimapCluster.Tracking.Background:Hide()
        Enforce.Install(MinimapCluster.Tracking.Background, "minimapTrackingBackground", DOCK_HIDE_OPTS)
    end
end

local function ApplyDockVisibility(db)
    if not db then return end

    local hideDock = db.dockHide

    if hideDock then
        blizzardDockHidden = true
        -- Hide the dock bar (BorderTop contains zone text area)
        if MinimapCluster and MinimapCluster.BorderTop then
            MinimapCluster.BorderTop:Hide()
        end
        -- Hide calendar button
        if GameTimeFrame then
            GameTimeFrame:Hide()
        end
        -- Hide tracking button and background
        HideTrackingElements()
        -- Deferred check for tracking elements that may load late
        C_Timer.After(0.5, function()
            local currentDb = getMinimapDB()
            if currentDb and currentDb.dockHide then
                HideTrackingElements()
            end
        end)
        -- Hide addon compartment button
        if AddonCompartmentFrame then
            AddonCompartmentFrame:Hide()
        end
    elseif blizzardDockHidden then
        blizzardDockHidden = false
        -- Restore dock bar
        if MinimapCluster and MinimapCluster.BorderTop then
            MinimapCluster.BorderTop:Show()
        end
        -- Restore calendar button
        if GameTimeFrame then
            GameTimeFrame:Show()
        end
        -- Restore tracking button and background
        if MinimapCluster and MinimapCluster.Tracking then
            if MinimapCluster.Tracking.Button then
                MinimapCluster.Tracking.Button:Show()
            end
            if MinimapCluster.Tracking.Background then
                MinimapCluster.Tracking.Background:Show()
            end
        end
        -- Restore addon compartment button
        if AddonCompartmentFrame then
            AddonCompartmentFrame:Show()
        end
    end
end

--------------------------------------------------------------------------------
-- Border Overlay
--------------------------------------------------------------------------------

local function UpdateBorderOverlay(db, forceShow)
    local overlays = ensureOverlayTable()
    if not overlays then return end

    local minimap = _G.Minimap
    if not minimap then return end

    -- Only show border when square shape AND borderEnabled AND overlay not active
    -- forceShow bypasses overlayActive check (used when overlay is visually stashed but db.overlayActive still true)
    local overlayActive = not forceShow and db and db.overlayEnabled and db.overlayActive
    local showBorder = db and db.mapShape == "square" and db.borderEnabled and not overlayActive

    if not showBorder then
        if overlays.border then
            overlays.border:Hide()
        end
        return
    end

    local thickness = tonumber(db.borderThickness) or 2
    if thickness < 1 then thickness = 1 end
    if thickness > 8 then thickness = 8 end

    -- Get color
    local r, g, b, a = 0, 0, 0, 1
    if db.borderTintEnabled and db.borderColor then
        r = db.borderColor[1] or 0
        g = db.borderColor[2] or 0
        b = db.borderColor[3] or 0
        a = db.borderColor[4] or 1
    end

    -- Edges live on a UIParent-parented container (taint avoidance) pinned to
    -- the BACKGROUND strata at level 1, expanded outward by the thickness.
    local _, container = addon.Borders.ApplySquare(minimap, {
        size = thickness,
        color = { r, g, b, a },
        layer = "BACKGROUND",
        containerStrata = "BACKGROUND",
        containerLevel = 1,
        expand = thickness,
        skipDimensionCheck = true,
    })
    if container and not overlays.border then
        addon.RegisterPetBattleFrame(container)
    end
    overlays.border = container
end

--------------------------------------------------------------------------------
-- Event Handler for Zone Changes
--------------------------------------------------------------------------------

local zoneEventsArmed = nil

local function EnsureZoneEventHandler()
    if zoneEventsArmed then return end
    zoneEventsArmed = true

    local function onZoneEvent()
        MM._UpdateZoneText()
        MM._UpdateZoneCoordinates()
    end
    addon.Events.On("Minimap:Zone", "ZONE_CHANGED", onZoneEvent)
    addon.Events.On("Minimap:Zone", "ZONE_CHANGED_INDOORS", onZoneEvent)
    addon.Events.On("Minimap:Zone", "ZONE_CHANGED_NEW_AREA", onZoneEvent)
end

--------------------------------------------------------------------------------
-- HybridMinimap / TimeManager Handler
--------------------------------------------------------------------------------

local addonLoadedArmed = nil

local function EnsureAddonLoadedHandler()
    if addonLoadedArmed then return end
    addonLoadedArmed = true

    -- OnAddonLoaded runs the callback immediately when the addon is already
    -- loaded; both appliers are idempotent re-applies of the current db.
    addon.Events.OnAddonLoaded("Blizzard_HybridMinimap", function()
        local db = getMinimapDB()
        if db then
            ApplyMinimapShape(db)
        end
    end)
    addon.Events.OnAddonLoaded("Blizzard_TimeManager", function()
        -- Apply clock settings now that TimeManagerClockButton exists
        local db = getMinimapDB()
        if db then
            MM._ApplyClockStyle(db)
        end
    end)
end

--------------------------------------------------------------------------------
-- Main Apply Styling Function
--------------------------------------------------------------------------------

local function ApplyMinimapStyling(self)
    local db = self.db

    -- Zero-Touch: Check for proxy DB (means no config)
    if addon.IsComponentUnconfigured(self) then
        return
    end

    if not db then return end

    -- Ensure event handlers are set up
    EnsureZoneEventHandler()
    EnsureAddonLoadedHandler()

    -- Apply shape
    ApplyMinimapShape(db)

    -- Apply border
    UpdateBorderOverlay(db)

    -- Apply dock visibility (must be before zone/clock to control BorderTop)
    ApplyDockVisibility(db)

    -- Apply zone text
    MM._ApplyZoneTextStyle(db)

    -- Apply zone coordinates
    MM._ApplyZoneCoordinatesStyle(db)

    -- Apply clock
    MM._ApplyClockStyle(db)

    -- Apply system data
    MM._ApplySystemDataStyle(db)

    -- Apply addon button container
    MM._ApplyButtonContainerStyle(db)

    -- Apply addon button border styling
    MM._ApplyAddonButtonBorderStyle(db)

    -- Apply custom tracking button
    MM._ApplyTrackingButtonStyle(db)

    -- Apply custom mail button
    MM._EnsureMailEventHandler()
    MM._ApplyMailButtonStyle(db)

    -- Apply minimap overlay
    if addon.ApplyMinimapOverlay then
        addon.ApplyMinimapOverlay(db)
    end

    -- Apply off-screen dragging unlock
    if addon.ApplyMinimapOffscreenUnlock then
        addon.ApplyMinimapOffscreenUnlock()
    end
end

--------------------------------------------------------------------------------
-- Component Registration
--------------------------------------------------------------------------------

addon:RegisterComponentInitializer(function(self)
    local Component = addon.ComponentPrototype

    local minimapComponent = Component:New({
        id = "minimapStyle",
        name = "Minimap",
        frameName = "MinimapCluster",  -- Edit Mode-managed frame
        settings = {
            -- Map Style (Addon-only settings)
            -- Note: Map Size is read/written directly to Edit Mode, not stored in AceDB
            mapShape = { type = "addon", default = "default" },
            borderEnabled = { type = "addon", default = false },
            borderTintEnabled = { type = "addon", default = false },
            borderColor = { type = "addon", default = {0, 0, 0, 1} },
            borderThickness = { type = "addon", default = 2 },

            -- Dock
            dockHide = { type = "addon", default = false },

            -- Zone Text
            zoneTextHide = { type = "addon", default = false },
            zoneTextPosition = { type = "addon", default = "dock" },  -- "dock" shows Blizzard's, others show overlay
            zoneTextColorMode = { type = "addon", default = "pvp" },
            zoneTextCustomColor = { type = "addon", default = {1, 0.82, 0, 1} },
            zoneTextFont = { type = "addon", default = "FRIZQT__" },
            zoneTextFontSize = { type = "addon", default = 12 },
            zoneTextFontStyle = { type = "addon", default = "OUTLINE" },
            zoneCoordinatesEnabled = { type = "addon", default = false },
            zoneTextOffsetX = { type = "addon", default = 0 },
            zoneTextOffsetY = { type = "addon", default = 0 },

            -- Clock
            clockHide = { type = "addon", default = false },
            clockPosition = { type = "addon", default = "dock" },  -- "dock" shows Blizzard's, others show overlay
            clockTimeSource = { type = "addon", default = "local" },
            clockUse24Hour = { type = "addon", default = false },
            clockFont = { type = "addon", default = "FRIZQT__" },
            clockFontSize = { type = "addon", default = 12 },
            clockFontStyle = { type = "addon", default = "OUTLINE" },
            clockColorMode = { type = "addon", default = "default" },
            clockCustomColor = { type = "addon", default = {1, 1, 1, 1} },
            clockOffsetX = { type = "addon", default = 0 },
            clockOffsetY = { type = "addon", default = 0 },

            -- System Data (visibility determined by showFPS/showLatency)
            systemDataShowFPS = { type = "addon", default = false },
            systemDataShowLatency = { type = "addon", default = false },
            systemDataLatencySource = { type = "addon", default = "home" },
            systemDataFont = { type = "addon", default = "FRIZQT__" },
            systemDataFontSize = { type = "addon", default = 11 },
            systemDataFontStyle = { type = "addon", default = "OUTLINE" },
            systemDataColorMode = { type = "addon", default = "default" },
            systemDataCustomColor = { type = "addon", default = {1, 1, 1, 1} },
            systemDataAnchor = { type = "addon", default = "BOTTOM" },
            systemDataOffsetX = { type = "addon", default = 0 },
            systemDataOffsetY = { type = "addon", default = -18 },

            -- Addon Buttons
            addonButtonContainerEnabled = { type = "addon", default = false },
            addonButtonContainerAnchor = { type = "addon", default = "BOTTOMLEFT" },
            addonButtonContainerOffsetX = { type = "addon", default = 0 },
            addonButtonContainerOffsetY = { type = "addon", default = 0 },
            scootButtonSeparate = { type = "addon", default = false },
            hideAddonButtonBorders = { type = "addon", default = false },
            addonButtonBorderTintEnabled = { type = "addon", default = false },
            addonButtonBorderTintColor = { type = "addon", default = {1, 1, 1, 1} },

            -- Tracking Button
            trackingButtonEnabled = { type = "addon", default = false },
            trackingButtonAnchor = { type = "addon", default = "TOPLEFT" },
            trackingButtonOffsetX = { type = "addon", default = 0 },
            trackingButtonOffsetY = { type = "addon", default = 0 },

            -- Mail Button
            mailButtonEnabled = { type = "addon", default = false },
            mailButtonAnchor = { type = "addon", default = "TOPRIGHT" },
            mailButtonOffsetX = { type = "addon", default = 0 },
            mailButtonOffsetY = { type = "addon", default = 0 },

            -- Minimap Overlay
            overlayEnabled = { type = "addon", default = false },
            overlayActive = { type = "addon", default = false },
            overlayScale = { type = "addon", default = 1.0 },
            overlayMapOpacity = { type = "addon", default = 0.85 },
            overlayNodesOpacity = { type = "addon", default = 1.0 },
            overlayCombatHide = { type = "addon", default = true },
            overlayButtonPosition = { type = "addon", default = "TOPRIGHT" },

            -- Off-Screen Dragging
            allowOffScreenDragging = { type = "addon", default = false },
        },
        ApplyStyling = ApplyMinimapStyling,
    })

    self:RegisterComponent(minimapComponent)
end, "minimap")

-- Export border visibility control for overlay system
function addon.SetMinimapBorderHidden(hidden)
    local overlays = ensureOverlayTable()
    if not overlays then return end
    if hidden then
        if overlays.border then
            overlays.border:Hide()
        end
    else
        local db = getMinimapDB()
        if db then
            UpdateBorderOverlay(db, true)
        end
    end
end

-- Hide/show overlay children (clock, FPS, addon buttons) during overlay mode.
-- Zone text + coords remain visible.
function addon.SetMinimapOverlayChildrenHidden(hidden)
    local overlays = ensureOverlayTable()
    if hidden then
        if overlays and overlays.clock then overlays.clock:Hide() end
        if overlays and overlays.systemData then overlays.systemData:Hide() end
        if MM._buttonContainerFrame then MM._buttonContainerFrame:Hide() end
        if MM._trackingButtonFrame then MM._trackingButtonFrame:Hide() end
        if MM._mailButtonFrame then MM._mailButtonFrame:Hide() end
    else
        -- Restore by re-applying styles (respects user settings)
        local db = getMinimapDB()
        if db then
            MM._ApplyClockStyle(db)
            MM._ApplySystemDataStyle(db)
            MM._ApplyButtonContainerStyle(db)
            MM._ApplyTrackingButtonStyle(db)
            MM._ApplyMailButtonStyle(db)
        end
    end
end

--------------------------------------------------------------------------------
-- Edit Mode Size Helpers (for UI)
--------------------------------------------------------------------------------

-- Read Edit Mode Map Size setting
function addon.getEditModeMinimapSize()
    local frame = _G.MinimapCluster
    local settingId = _G.Enum and _G.Enum.EditModeMinimapSetting and _G.Enum.EditModeMinimapSetting.Size
    if frame and settingId and addon and addon.EditMode and addon.EditMode.GetSetting then
        local v = addon.EditMode.GetSetting(frame, settingId)
        -- Edit Mode stores as 0-15 (index), which maps to 50-200% (raw)
        -- LibEditModeOverride should convert this, but handle both cases
        if v ~= nil then
            if v <= 15 then
                -- Index-based: convert to raw percent
                return 50 + (v * 10)
            else
                -- Already raw percent
                return math.max(50, math.min(200, v))
            end
        end
    end
    return 100
end

-- Write Edit Mode Map Size setting
function addon.setEditModeMinimapSize(value)
    local frame = _G.MinimapCluster
    local settingId = _G.Enum and _G.Enum.EditModeMinimapSetting and _G.Enum.EditModeMinimapSetting.Size
    if frame and settingId and addon and addon.EditMode and addon.EditMode.WriteSetting then
        -- Pass raw percent (50-200) - LibEditModeOverride handles index conversion
        local v = math.max(50, math.min(200, value or 100))
        v = math.floor(v / 10 + 0.5) * 10
        addon.EditMode.WriteSetting(frame, settingId, v, {
            suspendDuration = 0.25,
        })
    end
end
