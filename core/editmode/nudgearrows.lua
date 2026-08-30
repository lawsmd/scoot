-- nudgearrows.lua - Clickable arrow buttons on selected Edit Mode frames
local addonName, addon = ...

addon.EditMode = addon.EditMode or {}

local LEO = LibStub("LibEditModeOverride-1.0")
local LEM -- LibEditMode, resolved lazily from addon namespace

local SMALL_STEP = 1
local BIG_STEP = 10

-- Arrow button size and offset from frame edge
local ARROW_SIZE = 20
local ARROW_INSET = 2

-- Atlas names for each direction
local ARROW_ATLAS = {
    UP    = "NPE_ArrowUp",
    DOWN  = "NPE_ArrowDown",
    LEFT  = "NPE_ArrowLeft",
    RIGHT = "NPE_ArrowRight",
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local overlay        -- The reusable overlay frame
local arrowButtons   -- { UP, DOWN, LEFT, RIGHT } button references
local currentFrame   -- The Blizzard/custom frame currently selected
local currentIsNative -- true = native Blizzard system frame, false = custom
local tryHookDialog  -- forward declaration; defined in Hook Installation section

--------------------------------------------------------------------------------
-- DB Helper
--------------------------------------------------------------------------------

local function isEnabled()
    local profile = addon and addon.db and addon.db.profile
    local qol = profile and profile.qol
    return qol and qol.editModeNudgeArrows
end

--------------------------------------------------------------------------------
-- Nudge Dispatch
--------------------------------------------------------------------------------

local function nudge(dx, dy)
    if not currentFrame then return end
    if InCombatLockdown() then return end

    if currentIsNative then
        -- Native Blizzard system frame: use LEO to read/write position
        if not LEO then return end
        local ok, canEdit = pcall(LEO.CanEditActiveLayout, LEO)
        if not ok or not canEdit then return end

        local anchorInfo = LEO:GetFrameAnchorInfo(currentFrame)
        if not anchorInfo then return end

        local newX = (anchorInfo.offsetX or 0) + dx
        local newY = (anchorInfo.offsetY or 0) + dy

        LEO:ReanchorFrame(
            currentFrame,
            anchorInfo.point,
            anchorInfo.relativeTo,
            anchorInfo.relativePoint,
            newX,
            newY
        )

        if addon.EditMode and addon.EditMode.SaveOnly then
            addon.EditMode.SaveOnly()
        end
    else
        -- Custom Scoot frame (ScootAuras, Custom Groups): use LibEditMode
        if not LEM then
            LEM = addon._LEM or (LibStub and LibStub("LibEditMode", true))
        end
        if LEM and LEM.NudgeFrame then
            LEM:NudgeFrame(currentFrame, dx, dy)
        end
    end
end

--------------------------------------------------------------------------------
-- Arrow Button Factory
--------------------------------------------------------------------------------

local function createArrowButton(parent, direction)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(ARROW_SIZE, ARROW_SIZE)

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetAtlas(ARROW_ATLAS[direction])
    tex:SetAlpha(0.7)
    btn._tex = tex

    -- Hover highlight
    btn:SetScript("OnEnter", function(self)
        self._tex:SetAlpha(1)
    end)
    btn:SetScript("OnLeave", function(self)
        self._tex:SetAlpha(0.7)
    end)

    -- Click handler with shift detection
    local dirMap = {
        UP    = { 0,  1 },
        DOWN  = { 0, -1 },
        LEFT  = { -1, 0 },
        RIGHT = {  1, 0 },
    }
    local dirVec = dirMap[direction]

    btn:SetScript("OnClick", function()
        if not isEnabled() then return end
        local step = IsShiftKeyDown() and BIG_STEP or SMALL_STEP
        nudge(dirVec[1] * step, dirVec[2] * step)
    end)

    return btn
end

--------------------------------------------------------------------------------
-- Overlay Creation (once, reused)
--------------------------------------------------------------------------------

local function ensureOverlay()
    if overlay then return end

    overlay = CreateFrame("Frame", "ScootNudgeArrowOverlay", UIParent)
    overlay:SetFrameStrata("DIALOG")
    overlay:SetFrameLevel(500)
    overlay:Hide()

    -- The overlay itself is click-transparent; only the buttons capture clicks
    overlay:EnableMouse(false)

    arrowButtons = {}

    -- UP arrow: centered on top edge
    arrowButtons.UP = createArrowButton(overlay, "UP")
    arrowButtons.UP:SetPoint("BOTTOM", overlay, "TOP", 0, ARROW_INSET)

    -- DOWN arrow: centered on bottom edge
    arrowButtons.DOWN = createArrowButton(overlay, "DOWN")
    arrowButtons.DOWN:SetPoint("TOP", overlay, "BOTTOM", 0, -ARROW_INSET)

    -- LEFT arrow: centered on left edge
    arrowButtons.LEFT = createArrowButton(overlay, "LEFT")
    arrowButtons.LEFT:SetPoint("RIGHT", overlay, "LEFT", -ARROW_INSET, 0)

    -- RIGHT arrow: centered on right edge
    arrowButtons.RIGHT = createArrowButton(overlay, "RIGHT")
    arrowButtons.RIGHT:SetPoint("LEFT", overlay, "RIGHT", ARROW_INSET, 0)
end

--------------------------------------------------------------------------------
-- Show / Hide overlay
--------------------------------------------------------------------------------

local function showOverlay(anchorFrame)
    if not isEnabled() then return end
    ensureOverlay()

    overlay:ClearAllPoints()
    overlay:SetAllPoints(anchorFrame)
    overlay:Show()
end

local function hideOverlay()
    if overlay then
        overlay:Hide()
    end
    currentFrame = nil
    currentIsNative = nil
end

--------------------------------------------------------------------------------
-- Selection Detection: Native Blizzard system frames
--------------------------------------------------------------------------------

local function onNativeSystemSelected(_, systemFrame)
    if not dialogHooked then tryHookDialog() end
    if not isEnabled() then return end
    if not systemFrame then
        hideOverlay()
        return
    end

    -- Find the Selection child (Blizzard's EditModeSystemSelectionTemplate)
    local selectionChild = systemFrame.Selection
    if not selectionChild then
        hideOverlay()
        return
    end

    currentFrame = systemFrame
    currentIsNative = true
    showOverlay(selectionChild)
end

--------------------------------------------------------------------------------
-- Selection Detection: Custom Scoot frames (LibEditMode)
--------------------------------------------------------------------------------

local function onCustomFrameSelected(selection)
    if not isEnabled() then return end
    if not selection or not selection.parent then
        hideOverlay()
        return
    end

    currentFrame = selection.parent
    currentIsNative = false
    showOverlay(selection)
end

--------------------------------------------------------------------------------
-- Deselection Detection
--------------------------------------------------------------------------------

local function onClearSelectedSystem()
    -- Only hide when tracking a native frame (custom frame deselection handled separately)
    if currentIsNative then
        hideOverlay()
    end
end

local function onEditModeExit()
    hideOverlay()
end

--------------------------------------------------------------------------------
-- Hook Installation
--------------------------------------------------------------------------------

local hooksInstalled = false
local dialogHooked = false

tryHookDialog = function()
    if dialogHooked then return end
    if not LEM then
        LEM = addon._LEM or (LibStub and LibStub("LibEditMode", true))
    end
    if LEM and LEM.internal and LEM.internal.dialog then
        dialogHooked = true
        hooksecurefunc(LEM.internal.dialog, "Update", function(dialog, selection)
            onCustomFrameSelected(selection)
        end)
        LEM.internal.dialog:HookScript("OnHide", function()
            if not currentIsNative then
                hideOverlay()
            end
        end)
    end
end

local function installHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    -- Native Blizzard frame selection
    hooksecurefunc(EditModeManagerFrame, "SelectSystem", onNativeSystemSelected)

    -- Native Blizzard frame deselection
    hooksecurefunc(EditModeManagerFrame, "ClearSelectedSystem", onClearSelectedSystem)

    -- Edit Mode exit (OnHide)
    EditModeManagerFrame:HookScript("OnHide", onEditModeExit)

    -- Edit Mode enter: retry dialog hook (dialog may not exist at load time)
    EditModeManagerFrame:HookScript("OnShow", function()
        tryHookDialog()
    end)

    -- Try hooking dialog now (may succeed if frames already registered)
    tryHookDialog()

    -- Also hook resetSelection path used by both systems
    EventRegistry:RegisterCallback("EditModeExternal.hideDialog", function()
        hideOverlay()
    end)

    -- Hook Blizzard's system settings dialog hide (native frame deselected via clicking elsewhere)
    if EditModeSystemSettingsDialog then
        EditModeSystemSettingsDialog:HookScript("OnHide", function()
            if currentIsNative then
                hideOverlay()
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function addon.EditMode.InitNudgeArrows()
    -- Defer hook installation until Edit Mode manager is available
    if EditModeManagerFrame then
        installHooks()
    else
        -- Fallback: wait for EDIT_MODE_LAYOUTS_UPDATED
        addon.Events.Once("EditMode:NudgeArrows", "EDIT_MODE_LAYOUTS_UPDATED", function()
            if EditModeManagerFrame then
                installHooks()
            end
        end)
    end
end

function addon.EditMode.SetNudgeArrowsEnabled(enabled)
    if not enabled then
        hideOverlay()
    end
end

-- Initialize when this file loads (safe: sets up deferred hooks)
addon.EditMode.InitNudgeArrows()
