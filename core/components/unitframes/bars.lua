-- bars.lua: Unit Frame bar styling orchestrator. Delegates to bars/ submodules.

local addonName, addon = ...
local Util = addon.ComponentsUtil
local CleanupIconBorderAttachments = Util.CleanupIconBorderAttachments
local ClampOpacity = Util.ClampOpacity
local PlayerInCombat = Util.PlayerInCombat
local HideDefaultBarTextures = Util.HideDefaultBarTextures
local ToggleDefaultIconOverlay = Util.ToggleDefaultIconOverlay

-- Secret-value safe helpers (shared module)
local safeOffset = addon.SecretSafe.safeOffset

-- Reference extracted modules (loaded via TOC before this file)
local Utils = addon.BarsUtils
local Combat = addon.BarsCombat
local Resolvers = addon.BarsResolvers
local Textures = addon.BarsTextures
local Alpha = addon.BarsAlpha
local Preemptive = addon.BarsPreemptive
local RaidFrames = addon.BarsRaidFrames
local PartyFrames = addon.BarsPartyFrames

local function isEditModeActive()
    if addon and addon.EditMode and addon.EditMode.IsEditModeActiveOrOpening then
        return addon.EditMode.IsEditModeActiveOrOpening()
    end
    local mgr = _G.EditModeManagerFrame
    return mgr and (mgr.editModeActive or (mgr.IsShown and mgr:IsShown()))
end

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = nil
local function ensureFS()
    if not FS then FS = addon.FrameState end
    return FS
end

local function getState(frame)
    local fs = ensureFS()
    return fs and fs.Get(frame) or nil
end

local function getProp(frame, key)
    local st = getState(frame)
    return st and st[key] or nil
end

local function setProp(frame, key, value)
    local st = getState(frame)
    if st then
        st[key] = value
    end
end

--------------------------------------------------------------------------------
-- Local aliases to extracted module functions
-- These provide backward compatibility with code in this file
--------------------------------------------------------------------------------

local getUiScale = Utils.getUiScale
local pixelsToUiUnits = Utils.pixelsToUiUnits
local uiUnitsToPixels = Utils.uiUnitsToPixels
local clampScreenCoordinate = Utils.clampScreenCoordinate
local getFrameScreenOffsets = Utils.getFrameScreenOffsets

-- Round a UI-unit value DOWN to the nearest physical screen pixel.
-- At non-1.0 UI scales, integer UI units don't land on pixel boundaries.
-- This ensures clip container edges snap to exact pixels so clipping
-- and border rendering agree on the same boundary (fixes sub-pixel gaps).
local function pixelFloor(uiValue, frame)
    local scale = 1
    if frame and frame.GetEffectiveScale then
        local ok, es = pcall(frame.GetEffectiveScale, frame)
        if ok and type(es) == "number" and es > 0 then
            scale = es
        end
    else
        scale = getUiScale()
    end
    return math.floor(uiValue * scale) / scale
end

local queuePowerBarReapply = Combat.queuePowerBarReapply
local queueUnitFrameTextureReapply = Combat.queueUnitFrameTextureReapply
local queueRaidFrameReapply = Combat.queueRaidFrameReapply
local queuePartyFrameReapply = Combat.queuePartyFrameReapply

-- Power Bar position trace: /scoot debug powerbar trace on|off|log|clear

local powerBarDebugTraceEnabled = false
local powerBarTraceBuffer = {}
local POWERBAR_TRACE_MAX_LINES = 500 -- Max lines to keep in buffer

addon.SetPowerBarDebugTrace = function(enabled)
    powerBarDebugTraceEnabled = enabled
    if enabled then
        print("|cff00ff00[ScooterMod]|r Power bar trace ENABLED (buffering to log)")
        print("|cff00ff00[ScooterMod]|r Use '/scoot debug powerbar log' to view, '/scoot debug powerbar clear' to clear")
        table.insert(powerBarTraceBuffer, "=== Trace started at " .. date("%Y-%m-%d %H:%M:%S") .. " ===")
    else
        print("|cff00ff00[ScooterMod]|r Power bar trace DISABLED")
        table.insert(powerBarTraceBuffer, "=== Trace stopped at " .. date("%Y-%m-%d %H:%M:%S") .. " ===")
    end
end

addon.ShowPowerBarTraceLog = function()
    if #powerBarTraceBuffer == 0 then
        print("|cff00ff00[ScooterMod]|r Power bar trace buffer is empty")
        return
    end
    
    local text = table.concat(powerBarTraceBuffer, "\n")
    if addon.DebugShowWindow then
        addon.DebugShowWindow("Power Bar Trace Log (" .. #powerBarTraceBuffer .. " lines)", text)
    else
        print("|cff00ff00[ScooterMod]|r Debug window not available. Buffer has " .. #powerBarTraceBuffer .. " lines.")
    end
end

addon.ClearPowerBarTraceLog = function()
    local count = #powerBarTraceBuffer
    powerBarTraceBuffer = {}
    print("|cff00ff00[ScooterMod]|r Cleared " .. count .. " lines from power bar trace buffer")
end

local function debugTracePowerBar(message, ...)
    if not powerBarDebugTraceEnabled then return end
    local timestamp = GetTime and string.format("%.3f", GetTime()) or "?"
    local combat = (InCombatLockdown and InCombatLockdown()) and "COMBAT" or "safe"
    local formatted = string.format("[%s][%s] %s", timestamp, combat, message)
    if select("#", ...) > 0 then
        formatted = string.format(formatted, ...)
    end

    table.insert(powerBarTraceBuffer, formatted)

    while #powerBarTraceBuffer > POWERBAR_TRACE_MAX_LINES do
        table.remove(powerBarTraceBuffer, 1)
    end
end

-- Power Bar Custom Position (DEPRECATED): replaced by PRD with Edit Mode positioning.
-- Retained for backward compatibility; always returns false.

local function applyCustomPowerBarPosition(unit, pb, cfg)
    -- Feature deprecated - always return false
    -- Clear any legacy flags that may exist on the frame
    if pb then
        setProp(pb, "powerBarCustomActive", nil)
        setProp(pb, "powerBarCustomPosEnabled", nil)
    end
    return false
end

-- Debug helper:
-- /scoot debug powerbarpos [simulate]
-- Shows current Player ManaBar points + ScooterMod custom-position state.
function addon.DebugPowerBarPosition(simulateReset)
    if not (addon and addon.DebugShowWindow) then
        return
    end

    local pb =
        _G.PlayerFrame
        and _G.PlayerFrame.PlayerFrameContent
        and _G.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
        and _G.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea
        and _G.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar

    local lines = {}
    local function push(s) table.insert(lines, tostring(s)) end

    push("InCombatLockdown=" .. tostring((InCombatLockdown and InCombatLockdown()) and true or false))
    push("PlayerInCombat=" .. tostring((PlayerInCombat and PlayerInCombat()) and true or false))
    push("PowerBarFound=" .. tostring(pb ~= nil))

    if not pb then
        addon.DebugShowWindow("Player Power Bar Position", table.concat(lines, "\n"))
        return
    end

    local okIgnore, ignoring = false, nil
    if pb.IsIgnoringFramePositionManager then
        okIgnore, ignoring = pcall(pb.IsIgnoringFramePositionManager, pb)
    end
    push("IsIgnoringFramePositionManager=" .. tostring(okIgnore and ignoring or "<n/a>"))

    push("_ScootPowerBarCustomActive=" .. tostring(getProp(pb, "powerBarCustomActive") and true or false))
    push("_ScootPowerBarCustomPosEnabled=" .. tostring(getProp(pb, "powerBarCustomPosEnabled") and true or false))
    push("_ScootPowerBarCustomPosX=" .. tostring(getProp(pb, "powerBarCustomPosX")))
    push("_ScootPowerBarCustomPosY=" .. tostring(getProp(pb, "powerBarCustomPosY")))
    push("_ScootPowerBarCustomPosUnit=" .. tostring(getProp(pb, "powerBarCustomPosUnit")))

    local sx, sy = getFrameScreenOffsets(pb)
    push(string.format("ScreenOffsetFromCenter(px)=%s,%s", tostring(sx), tostring(sy)))

    local function dumpPoints(header)
        push("")
        push(header)
        if not (pb.GetNumPoints and pb.GetPoint) then
            push("<no GetPoint API>")
            return
        end
        local okN, n = pcall(pb.GetNumPoints, pb)
        n = (okN and n) or 0
        push("NumPoints=" .. tostring(n))
        for i = 1, n do
            local ok, point, relTo, relPoint, xOfs, yOfs = pcall(pb.GetPoint, pb, i)
            if ok and point then
                local relName = "<nil>"
                if relTo and relTo.GetName then
                    local okName, nm = pcall(relTo.GetName, relTo)
                    if okName and nm and nm ~= "" then
                        relName = nm
                    else
                        relName = tostring(relTo)
                    end
                else
                    relName = tostring(relTo)
                end
                push(string.format("[%d] %s -> %s (%s) x=%s y=%s", i, tostring(point), tostring(relName), tostring(relPoint), tostring(xOfs), tostring(yOfs)))
            else
                push(string.format("[%d] <error>", i))
            end
        end
    end

    dumpPoints("Points (before)")

    if simulateReset then
        push("")
        push("SimulateReset=true")
        if InCombatLockdown and InCombatLockdown() then
            push("SimulateResetSkipped=InCombatLockdown")
        else
            -- Simulate Blizzard's default reset from PlayerFrame_ToPlayerArt / ToVehicleArt.
            if pb.ClearAllPoints and pb.SetPoint then
                pcall(pb.ClearAllPoints, pb)
                pcall(pb.SetPoint, pb, "TOPLEFT", 85, -61)
            else
                push("SimulateResetSkipped=<no ClearAllPoints/SetPoint>")
            end
        end

        dumpPoints("Points (after simulate)")
    end

    addon.DebugShowWindow("Player Power Bar Position", table.concat(lines, "\n"))
end

-- Unit Frames: Copy Health/Power Bar Style settings (texture, color mode, tint)
do
    function addon.CopyUnitFrameBarStyleSettings(sourceUnit, destUnit)
        local db = addon and addon.db and addon.db.profile
        if not db then return false end
        db.unitFrames = db.unitFrames or {}
        local src = db.unitFrames[sourceUnit]
        if not src then return false end
        db.unitFrames[destUnit] = db.unitFrames[destUnit] or {}
        local dst = db.unitFrames[destUnit]

        local function deepcopy(v)
            if type(v) ~= "table" then return v end
            local out = {}
            for k, vv in pairs(v) do out[k] = deepcopy(vv) end
            return out
        end

        local keys = {
            "healthBarTexture",
            "healthBarColorMode",
            "healthBarTint",
            "healthBarBackgroundTexture",
            "healthBarBackgroundColorMode",
            "healthBarBackgroundTint",
            "healthBarBackgroundOpacity",
            "powerBarTexture",
            "powerBarColorMode",
            "powerBarTint",
            "powerBarBackgroundTexture",
            "powerBarBackgroundColorMode",
            "powerBarBackgroundTint",
            "powerBarBackgroundOpacity",
            "powerBarHideFullSpikes",
            "powerBarHideFeedback",
            "powerBarHideSpark",
            "powerBarHideManaCostPrediction",
            "powerBarHidden",
        }
        for _, k in ipairs(keys) do
            if src[k] ~= nil then dst[k] = deepcopy(src[k]) else dst[k] = nil end
        end

        if addon.ApplyUnitFrameBarTexturesFor then addon.ApplyUnitFrameBarTexturesFor(destUnit) end
        return true
    end
end

-- Unit Frames: Apply custom bar textures (Health/Power) with optional tint per unit
do
    -- Use resolver functions from extracted module
    local getUnitFrameFor = Resolvers.getUnitFrameFor
    local resolveHealthBar = Resolvers.resolveHealthBar
    local resolveHealthContainer = Resolvers.resolveHealthContainer
    local resolvePowerBar = Resolvers.resolvePowerBar
    local resolveAlternatePowerBar = Resolvers.resolveAlternatePowerBar
    local resolveHealthMask = Resolvers.resolveHealthMask
    local resolvePowerMask = Resolvers.resolvePowerMask
    local resolveUFContentMain = Resolvers.resolveUFContentMain
    local resolveUnitFrameFrameTexture = Resolvers.resolveUnitFrameFrameTexture
    local resolveBossHealthMask = Resolvers.resolveBossHealthMask
    local resolveBossPowerMask = Resolvers.resolveBossPowerMask
    local resolveBossHealthBarsContainer = Resolvers.resolveBossHealthBarsContainer
    local resolveBossManaBar = Resolvers.resolveBossManaBar
    
    -- Use texture functions from extracted module
    local applyToBar = Textures.applyToBar
    local applyBackgroundToBar = Textures.applyBackgroundToBar
    local ensureMaskOnBarTexture = Textures.ensureMaskOnBarTexture
    
    -- Use alpha functions from extracted module
    local applyAlpha = Alpha.applyAlpha
    local hookAlphaEnforcer = Alpha.hookAlphaEnforcer

    -- Raise unit frame text layers so they always appear above any custom borders
    local function raiseUnitTextLayers(unit, targetLevel)
        -- Never touch protected unit frame hierarchy during combat; doing so taints
        -- later secure operations such as TargetFrameToT:Show().
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        local function safeSetDrawLayer(fs, layer, sub)
            if fs and fs.SetDrawLayer then pcall(fs.SetDrawLayer, fs, layer, sub) end
        end
        local function safeRaiseFrameLevel(frame, baseLevel, bump)
            if not frame then return end
            local cur = (frame.GetFrameLevel and frame:GetFrameLevel()) or 0
            local target = math.max(cur, (tonumber(baseLevel) or 0) + (tonumber(bump) or 0))
            if targetLevel and type(targetLevel) == "number" then
                if target < targetLevel then target = targetLevel end
            end
            if frame.SetFrameLevel then pcall(frame.SetFrameLevel, frame, target) end
        end
        if unit == "Pet" then
            safeSetDrawLayer(_G.PetFrameHealthBarText, "OVERLAY", 6)
            safeSetDrawLayer(_G.PetFrameHealthBarTextLeft, "OVERLAY", 6)
            safeSetDrawLayer(_G.PetFrameHealthBarTextRight, "OVERLAY", 6)
            safeSetDrawLayer(_G.PetFrameManaBarText, "OVERLAY", 6)
            safeSetDrawLayer(_G.PetFrameManaBarTextLeft, "OVERLAY", 6)
            safeSetDrawLayer(_G.PetFrameManaBarTextRight, "OVERLAY", 6)
            -- Bump parent levels above any border holder
            local hb = _G.PetFrameHealthBar
            local mb = _G.PetFrameManaBar
            local base = (hb and hb.GetFrameLevel and hb:GetFrameLevel()) or 0
            safeRaiseFrameLevel(hb, base, 12)
            safeRaiseFrameLevel(mb, base, 12)
            return
        end
        if unit == "Boss" then
            for i = 1, 5 do
                local bossFrame = _G["Boss" .. i .. "TargetFrame"]
                if bossFrame then
                    local hbContainer = bossFrame.TargetFrameContent
                        and bossFrame.TargetFrameContent.TargetFrameContentMain
                        and bossFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                    if hbContainer then
                        safeSetDrawLayer(hbContainer.HealthBarText, "OVERLAY", 6)
                        safeSetDrawLayer(hbContainer.LeftText, "OVERLAY", 6)
                        safeSetDrawLayer(hbContainer.RightText, "OVERLAY", 6)
                        local base = (hbContainer.GetFrameLevel and hbContainer:GetFrameLevel())
                            or (bossFrame.GetFrameLevel and bossFrame:GetFrameLevel()) or 0
                        safeRaiseFrameLevel(hbContainer, base, 12)
                    end

                    local mana = bossFrame.TargetFrameContent
                        and bossFrame.TargetFrameContent.TargetFrameContentMain
                        and bossFrame.TargetFrameContent.TargetFrameContentMain.ManaBar
                    if mana then
                        safeSetDrawLayer(mana.ManaBarText, "OVERLAY", 6)
                        safeSetDrawLayer(mana.LeftText, "OVERLAY", 6)
                        safeSetDrawLayer(mana.RightText, "OVERLAY", 6)
                        local base = (mana.GetFrameLevel and mana:GetFrameLevel())
                            or (bossFrame.GetFrameLevel and bossFrame:GetFrameLevel()) or 0
                        safeRaiseFrameLevel(mana, base, 12)
                    end
                end
            end
            return
        end
        local root = (unit == "Player" and _G.PlayerFrame)
            or (unit == "Target" and _G.TargetFrame)
            or (unit == "Focus" and _G.FocusFrame) or nil
        if not root then return end
        -- Health texts
        local hbContainer = (unit == "Player" and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer)
            or (root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer)
        if hbContainer then
            safeSetDrawLayer(hbContainer.HealthBarText, "OVERLAY", 6)
            safeSetDrawLayer(hbContainer.LeftText, "OVERLAY", 6)
            safeSetDrawLayer(hbContainer.RightText, "OVERLAY", 6)
            local base = (hbContainer.GetFrameLevel and hbContainer:GetFrameLevel()) or ((root.GetFrameLevel and root:GetFrameLevel()) or 0)
            safeRaiseFrameLevel(hbContainer, base, 12)
        end
        -- Mana texts
        local mana
        if unit == "Player" then
            mana = root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar
        else
            mana = root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain and root.TargetFrameContent.TargetFrameContentMain.ManaBar
        end
        if mana then
            safeSetDrawLayer(mana.ManaBarText, "OVERLAY", 6)
            safeSetDrawLayer(mana.LeftText, "OVERLAY", 6)
            safeSetDrawLayer(mana.RightText, "OVERLAY", 6)
            local base = (mana.GetFrameLevel and mana:GetFrameLevel()) or ((root.GetFrameLevel and root:GetFrameLevel()) or 0)
            safeRaiseFrameLevel(mana, base, 12)
        end
    end

    -- Compute border holder level below current text and enforce ordering deterministically
    local function ensureTextAndBorderOrdering(unit)
        -- PetFrame is an Edit Mode managed/protected unit frame.
        -- Even out-of-combat frame-level/strata adjustments on PetFrame children can taint the frame
        -- and later cause protected Edit Mode methods (e.g., PetFrame:HideBase(), PetFrame:SetPointBase())
        -- to be blocked. Do not perform any ordering work for Pet.
        if unit == "Pet" then
            return
        end
        -- Guard against combat lockdown: raising frame levels on protected unit frames
        -- during combat will taint subsequent secure operations (see taint.log).
        if InCombatLockdown and InCombatLockdown() then
            return
        end

        -- Boss frames: ensure text containers are above border anchor frames for all Boss1-Boss5
        if unit == "Boss" then
            for i = 1, 5 do
                local bossFrame = _G["Boss" .. i .. "TargetFrame"]
                if bossFrame then
                    -- Health bar text ordering
                    local hbContainer = bossFrame.TargetFrameContent
                        and bossFrame.TargetFrameContent.TargetFrameContentMain
                        and bossFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                    local hb = hbContainer and hbContainer.HealthBar

                    if hb and hbContainer then
                        -- Get border anchor frame level (if it exists)
                        local borderAnchor = getProp(hb, "bossHealthBorderAnchor")
                        local borderLevel = borderAnchor and borderAnchor.GetFrameLevel and borderAnchor:GetFrameLevel() or 0
                        local barLevel = hb.GetFrameLevel and hb:GetFrameLevel() or 0

                        -- Text container must be above border anchor
                        local desiredTextLevel = math.max(
                            (hbContainer.GetFrameLevel and hbContainer:GetFrameLevel() or 0),
                            borderLevel + 1,
                            barLevel + 2
                        )
                        if hbContainer.SetFrameLevel then
                            pcall(hbContainer.SetFrameLevel, hbContainer, desiredTextLevel)
                        end

                        -- Keep border anchor between bar and text
                        if borderAnchor and borderAnchor.SetFrameLevel then
                            local holderLevel = math.max(1, desiredTextLevel - 1, barLevel + 1)
                            pcall(borderAnchor.SetFrameLevel, borderAnchor, holderLevel)
                        end
                    end

                    -- Power bar text ordering
                    local pb = bossFrame.TargetFrameContent
                        and bossFrame.TargetFrameContent.TargetFrameContentMain
                        and bossFrame.TargetFrameContent.TargetFrameContentMain.ManaBar

                    if pb then
                        -- Get border anchor frame level (if it exists)
                        local borderAnchor = getProp(pb, "bossPowerBorderAnchor")
                        local borderLevel = borderAnchor and borderAnchor.GetFrameLevel and borderAnchor:GetFrameLevel() or 0
                        local barLevel = pb.GetFrameLevel and pb:GetFrameLevel() or 0

                        -- ManaBar is both the StatusBar and the text container for Boss frames
                        local desiredTextLevel = math.max(
                            (pb.GetFrameLevel and pb:GetFrameLevel() or 0),
                            borderLevel + 1,
                            barLevel + 2
                        )
                        if pb.SetFrameLevel then
                            pcall(pb.SetFrameLevel, pb, desiredTextLevel)
                        end

                        -- Keep border anchor between bar and text
                        if borderAnchor and borderAnchor.SetFrameLevel then
                            local holderLevel = math.max(1, desiredTextLevel - 1, barLevel + 1)
                            pcall(borderAnchor.SetFrameLevel, borderAnchor, holderLevel)
                        end
                    end
                end
            end
            -- Raise text draw layers to high OVERLAY sublevel
            raiseUnitTextLayers("Boss")
            return
        end

        local root = (unit == "Player" and _G.PlayerFrame)
            or (unit == "Target" and _G.TargetFrame)
            or (unit == "Focus" and _G.FocusFrame)
            or (unit == "Pet" and _G.PetFrame) or nil
        if not root then return end
        local hb = resolveHealthBar(root, unit) or nil
        local hbContainer = resolveHealthContainer(root, unit) or nil
        local pb = resolvePowerBar(root, unit) or nil
        local manaContainer
        if unit == "Player" then
            manaContainer = root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar or nil
        else
            manaContainer = root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain and root.TargetFrameContent.TargetFrameContentMain.ManaBar or nil
        end
        -- Determine bar level and desired ordering: bar < clipContainer < holder < text
        local barLevel = (hb and hb.GetFrameLevel and hb:GetFrameLevel()) or 0
        if pb and pb.GetFrameLevel then
            local pbl = pb:GetFrameLevel() or 0
            if pbl > barLevel then barLevel = pbl end
        end
        -- Account for height clip container if active (text must be above it)
        local clipContainerLevel = 0
        local st = hb and getState(hb)
        if st and st.heightClipContainer and st.heightClipActive then
            local ccLevel = st.heightClipContainer.GetFrameLevel and st.heightClipContainer:GetFrameLevel()
            if ccLevel then clipContainerLevel = ccLevel end
        end
        local curTextLevel = 0
        if hbContainer and hbContainer.GetFrameLevel then curTextLevel = math.max(curTextLevel, hbContainer:GetFrameLevel() or 0) end
        if manaContainer and manaContainer.GetFrameLevel then curTextLevel = math.max(curTextLevel, manaContainer:GetFrameLevel() or 0) end
        local desiredTextLevel = math.max(curTextLevel, barLevel + 2, clipContainerLevel + 1)
        -- Raise text containers above holder
        if hbContainer and hbContainer.SetFrameLevel then pcall(hbContainer.SetFrameLevel, hbContainer, desiredTextLevel) end
        if manaContainer and manaContainer.SetFrameLevel then pcall(manaContainer.SetFrameLevel, manaContainer, desiredTextLevel) end
        -- Keep text FontStrings at high overlay sublevel
        raiseUnitTextLayers(unit, desiredTextLevel)
        -- Place the textured border holder between bar and text
        do
            local holderLevel = math.max(1, desiredTextLevel - 1, barLevel + 1)
            local hHolder = hb and hb.ScooterStyledBorder or nil
            if hHolder and hHolder.SetFrameLevel then
                -- Lock desired level so internal size hooks won't raise it above text later
                setProp(hb, "borderFixedLevel", holderLevel)
                pcall(hHolder.SetFrameLevel, hHolder, holderLevel)
            end
            -- Match holder strata to the text container's strata so frame level ordering decides (bar < holder < text)
            if hHolder and hHolder.SetFrameStrata then
                local s = (hbContainer and hbContainer.GetFrameStrata and hbContainer:GetFrameStrata())
                    or (hb and hb.GetFrameStrata and hb:GetFrameStrata())
                    or (root and root.GetFrameStrata and root:GetFrameStrata())
                    or "MEDIUM"
                pcall(hHolder.SetFrameStrata, hHolder, s)
            end
            local pHolder = pb and pb.ScooterStyledBorder or nil
            if pHolder and pHolder.SetFrameLevel then
                setProp(pb, "borderFixedLevel", holderLevel)
                pcall(pHolder.SetFrameLevel, pHolder, holderLevel)
            end
            if pHolder and pHolder.SetFrameStrata then
                local s2 = (manaContainer and manaContainer.GetFrameStrata and manaContainer:GetFrameStrata())
                    or (pb and pb.GetFrameStrata and pb:GetFrameStrata())
                    or (root and root.GetFrameStrata and root:GetFrameStrata())
                    or "MEDIUM"
                pcall(pHolder.SetFrameStrata, pHolder, s2)
            end
            -- No overlay frame creation: respect stock-frame reuse policy
        end
    end

    -- Boss rectangular overlays: fill mask chips in health bar (top-left) and power bar (bottom-right)
    -- when useCustomBorders is enabled.
    local function updateBossRectOverlay(bar, overlayKey)
        local st = getState(bar)
        local overlay = st and st[overlayKey] or nil
        if not bar or not overlay then return end
        if not (st and st.rectActive) then
            overlay:Hide()
            return
        end

        -- Anchor to StatusBarTexture for horizontal fill tracking (no secret value reads).
        local statusBarTex = bar:GetStatusBarTexture()
        if not statusBarTex then
            overlay:Hide()
            return
        end

        -- BOSS FIX: Use stored bounds frame for vertical constraints.
        -- Boss HealthBar StatusBar is oversized (spans both health + power areas).
        -- We anchor LEFT/RIGHT to StatusBarTexture (tracks fill width automatically),
        -- and TOP/BOTTOM to the correct bounds frame (HealthBarsContainer for health,
        -- ManaBar for power).
        local boundsFrame = st.bossRectBoundsFrame

        overlay:ClearAllPoints()
        if boundsFrame and boundsFrame ~= bar then
            -- Hybrid anchoring: 4 edges anchored separately
            -- Horizontal: track StatusBarTexture fill
            overlay:SetPoint("LEFT", statusBarTex, "LEFT", 0, 0)
            overlay:SetPoint("RIGHT", statusBarTex, "RIGHT", 0, 0)
            -- Vertical: constrain to correct bounds frame
            overlay:SetPoint("TOP", boundsFrame, "TOP", 0, 0)
            overlay:SetPoint("BOTTOM", boundsFrame, "BOTTOM", 0, 0)
        else
            -- Fallback for non-Boss bars or if bounds resolution failed
            overlay:SetAllPoints(statusBarTex)
        end
        overlay:Show()
    end

    local function ensureBossRectOverlay(bossFrame, bar, cfg, barType)
        if not bar or not bossFrame then return end

        local db = addon and addon.db and addon.db.profile
        if not db then return end
        
        -- Zero-Touch: do not create config tables
        local unitFrames = rawget(db, "unitFrames")
        local ufCfg = unitFrames and rawget(unitFrames, "Boss") or nil
        if not ufCfg then
            return
        end

        -- Boss overlays activate when useCustomBorders is enabled (fills chips created by frame art masks)
        local shouldActivate = (ufCfg.useCustomBorders == true)
        
        local overlayKey = (barType == "health") and "ScooterRectFillHealth" or "ScooterRectFillPower"
        local st = getState(bar)
        if not st then return end
        st.rectActive = shouldActivate

        -- CRITICAL: Resolve the correct bounds frame for Boss bars.
        -- For health: HealthBarsContainer (correct bounds - health bar only)
        -- For power: ManaBar directly (correct bounds - it's a sibling of HealthBarsContainer)
        -- The HealthBar StatusBar has oversized bounds spanning both bars!
        local boundsFrame
        if barType == "health" then
            -- Use the same resolver as the border code
            if Resolvers and Resolvers.resolveBossHealthBarsContainer then
                boundsFrame = Resolvers.resolveBossHealthBarsContainer(bossFrame)
            end
            if not boundsFrame then
                -- Fallback: try to get parent (HealthBarsContainer)
                boundsFrame = bar:GetParent()
            end
        else
            -- For power bar, use the ManaBar resolver
            if Resolvers and Resolvers.resolveBossManaBar then
                boundsFrame = Resolvers.resolveBossManaBar(bossFrame)
            end
            if not boundsFrame then
                -- Fallback: ManaBar should have correct bounds itself
                boundsFrame = bar
            end
        end
        
        -- Store the correct bounds frame for use in updateBossRectOverlay
        st.bossRectBoundsFrame = boundsFrame or bar

        if not shouldActivate then
            if st[overlayKey] then
                st[overlayKey]:Hide()
            end
            return
        end

        if not st[overlayKey] then
            local overlay = bar:CreateTexture(nil, "OVERLAY", nil, 2)
            overlay:SetVertTile(false)
            overlay:SetHorizTile(false)
            overlay:SetTexCoord(0, 1, 0, 1)
            st[overlayKey] = overlay

            -- Drive overlay width from the bar's value/size changes
            local hookKey = (barType == "health") and "bossHealthRectHooksInstalled" or "bossPowerRectHooksInstalled"
            if _G.hooksecurefunc and not st[hookKey] then
                st[hookKey] = true
                _G.hooksecurefunc(bar, "SetValue", function(self)
                    if isEditModeActive() then return end
                    updateBossRectOverlay(self, overlayKey)
                end)
                _G.hooksecurefunc(bar, "SetMinMaxValues", function(self)
                    if isEditModeActive() then return end
                    updateBossRectOverlay(self, overlayKey)
                end)
                if bar.HookScript then
                    bar:HookScript("OnSizeChanged", function(self)
                        if isEditModeActive() then return end
                        updateBossRectOverlay(self, overlayKey)
                    end)
                end
            end
        end

        -- Copy the configured bar texture/tint so the overlay visually matches
        local texKey, texPath, stockAtlas
        if barType == "health" then
            texKey = cfg.healthBarTexture or "default"
            texPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)
            stockAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health" -- Boss uses Target-style atlas
        else -- power
            texKey = cfg.powerBarTexture or "default"
            texPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)
            stockAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Mana" -- Boss uses Target-style atlas
        end

        local overlay = st[overlayKey]
        if texPath then
            -- Custom texture configured
            overlay:SetTexture(texPath)
        else
            -- Default texture - try to copy from bar
            local tex = bar:GetStatusBarTexture()
            local applied = false
            if tex then
                -- Try GetAtlas first
                local okAtlas, atlasName = pcall(tex.GetAtlas, tex)
                if okAtlas and atlasName and atlasName ~= "" then
                    if overlay.SetAtlas then
                        pcall(overlay.SetAtlas, overlay, atlasName, true)
                        applied = true
                    end
                end
                
                if not applied then
                    local okTex, pathOrTex = pcall(tex.GetTexture, tex)
                    if okTex then
                        if type(pathOrTex) == "string" and pathOrTex ~= "" then
                            local isAtlas = _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(pathOrTex) ~= nil
                            if isAtlas and overlay.SetAtlas then
                                pcall(overlay.SetAtlas, overlay, pathOrTex, true)
                                applied = true
                            else
                                overlay:SetTexture(pathOrTex)
                                applied = true
                            end
                        elseif type(pathOrTex) == "number" and pathOrTex > 0 then
                            overlay:SetTexture(pathOrTex)
                            applied = true
                        end
                    end
                end
            end
            
            -- Fallback to stock atlas
            if not applied and stockAtlas and overlay.SetAtlas then
                pcall(overlay.SetAtlas, overlay, stockAtlas, true)
            end
        end

        -- Copy vertex color from configured settings
        local colorMode, tint
        if barType == "health" then
            colorMode = cfg.healthBarColorMode or "default"
            tint = cfg.healthBarTint
        else
            colorMode = cfg.powerBarColorMode or "default"
            tint = cfg.powerBarTint
        end

        local r, g, b, a = 1, 1, 1, 1
        if colorMode == "custom" and type(tint) == "table" then
            r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
        elseif colorMode == "class" and addon.GetClassColorRGB then
            local cr, cg, cb = addon.GetClassColorRGB("player")
            r, g, b = cr or 1, cg or 1, cb or 1
        elseif colorMode == "texture" then
            r, g, b, a = 1, 1, 1, 1
        elseif barType == "health" and colorMode == "default" and addon.GetDefaultHealthColorRGB then
            local hr, hg, hb = addon.GetDefaultHealthColorRGB()
            r, g, b = hr or 0, hg or 1, hb or 0
        end
        overlay:SetVertexColor(r, g, b, a)

        updateBossRectOverlay(bar, overlayKey)
    end

    -- The overlay remains at full height to occlude Blizzard's bar.
    -- A clipping container with SetClipsChildren(true) crops the visible portion.
    -- All reduced-height elements (background, rectFill) parent to the clip container.
    local function ensureHeightClipContainer(bar, unit, cfg)
        local st = getState(bar)
        if not st then return nil end

        local heightPct = cfg and cfg.healthBarOverlayHeightPct
        if not heightPct or heightPct >= 100 then
            -- No height reduction - hide container and restore original elements
            if st.heightClipContainer then
                st.heightClipContainer:Hide()
            end
            -- Restore original background (ScooterModBG via FrameState, not st.backgroundTex)
            local scooterBG_r = getProp(bar, "ScooterModBG")
            if st.heightClipBackgroundHidden and scooterBG_r then
                scooterBG_r:Show()
                st.heightClipBackgroundHidden = false
            end
            st.heightClipActive = false
            return nil
        end

        -- Create clipping container (once per bar)
        if not st.heightClipContainer then
            local container = CreateFrame("Frame", nil, bar:GetParent() or bar)
            container:SetClipsChildren(true)
            -- Frame level BELOW bar so text (which is on the bar) renders above the custom overlay.
            -- Blizzard's fill texture is hidden (alpha 0), so even though it's "above" the custom
            -- overlay in frame level terms, the custom overlay still shows through.
            -- This ensures: background < the custom overlay < Blizzard's hidden fill < text
            container:SetFrameLevel(math.max(1, (bar:GetFrameLevel() or 1) - 1))
            st.heightClipContainer = container
        end

        -- Position container at reduced height (centered vertically)
        local container = st.heightClipContainer
        local barHeight = bar:GetHeight()
        local targetHeight = barHeight * (heightPct / 100)
        local inset = pixelFloor((barHeight - targetHeight) / 2, bar)

        container:ClearAllPoints()
        container:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -inset)
        container:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, inset)
        container:Show()

        -- Create/update background that matches CONTAINER size (not full bar)
        if not st.heightClipBackground then
            local bg = container:CreateTexture(nil, "BACKGROUND", nil, -1)
            st.heightClipBackground = bg
        end

        local bg = st.heightClipBackground
        bg:ClearAllPoints()
        bg:SetAllPoints(container)  -- Match container, NOT full bar

        -- Copy from original background (ScooterModBG via FrameState) OR use sensible default
        local origBg = getProp(bar, "ScooterModBG")
        if origBg then
            local tex = origBg:GetTexture()
            if tex then
                bg:SetTexture(tex)
            else
                -- Copy color texture - use typical background opacity, not dark overlay
                bg:SetColorTexture(0, 0, 0, 0.5)
            end
            local r, g, b, a = origBg:GetVertexColor()
            if r then bg:SetVertexColor(r, g, b, a) end
            -- Hide original to prevent showing at full size
            origBg:Hide()
            st.heightClipBackgroundHidden = true
        else
            -- No custom background - use transparent (let parent show through)
            bg:SetColorTexture(0, 0, 0, 0)
        end
        bg:Show()

        st.heightClipActive = true
        return container
    end

    -- Reparent AnimatedLossBar into clipping container for proper height clipping (Player only).
    -- The AnimatedLossBar shows health lost as a dark red bar that fades out. Without reparenting,
    -- it appears at full height even when height reduction is active, and renders in the wrong z-order.
    local function reparentAnimatedLossBar(bar, clipContainer, heightPct)
        -- Get the animated loss bar (sibling of HealthBar in HealthBarsContainer)
        local parent = bar and bar:GetParent()
        local animatedLossBar = parent and parent.PlayerFrameHealthBarAnimatedLoss

        if not animatedLossBar then return end

        local st = getState(bar)
        if not st then return end

        if clipContainer and heightPct and heightPct < 100 then
            -- Height reduction active: reparent into clipping container
            if animatedLossBar:GetParent() ~= clipContainer then
                st.animLossOrigParent = animatedLossBar:GetParent()
                st.animLossOrigPoints = {}
                -- Save original anchor points
                for i = 1, animatedLossBar:GetNumPoints() do
                    local point, relativeTo, relativePoint, xOfs, yOfs = animatedLossBar:GetPoint(i)
                    st.animLossOrigPoints[i] = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, xOfs = xOfs, yOfs = yOfs }
                end
                animatedLossBar:SetParent(clipContainer)
                -- Re-anchor to match the bar position within the clip container
                animatedLossBar:ClearAllPoints()
                animatedLossBar:SetAllPoints(bar)
                -- Ensure it renders behind our overlay (lower sublevel in OVERLAY layer)
                if animatedLossBar.SetDrawLayer then
                    pcall(animatedLossBar.SetDrawLayer, animatedLossBar, "OVERLAY", 1)
                end
            end
        else
            -- Height reduction disabled: restore original parent
            if st.animLossOrigParent and animatedLossBar:GetParent() ~= st.animLossOrigParent then
                animatedLossBar:SetParent(st.animLossOrigParent)
                -- Restore original anchor points
                animatedLossBar:ClearAllPoints()
                if st.animLossOrigPoints and #st.animLossOrigPoints > 0 then
                    for _, pt in ipairs(st.animLossOrigPoints) do
                        animatedLossBar:SetPoint(pt.point, pt.relativeTo, pt.relativePoint, pt.xOfs, pt.yOfs)
                    end
                else
                    -- Fallback: re-anchor to sibling HealthBar
                    animatedLossBar:SetAllPoints(bar)
                end
                -- Let Blizzard manage draw layer naturally
            end
        end
    end

    -- Heal prediction bar keys (children of HealthBar StatusBar)
    local healPredBarKeys = {
        "MyHealPredictionBar",
        "OtherHealPredictionBar",
        "TotalAbsorbBar",
        "HealAbsorbBar",
    }

    -- Reparent heal prediction bars into clipping container for proper height clipping.
    -- Without reparenting, these bars appear at full height even when height reduction is active.
    -- Pattern mirrors reparentAnimatedLossBar() above.
    local function reparentHealPredictionBars(bar, clipContainer, heightPct)
        if not bar then return end

        local st = getState(bar)
        if not st then return end

        if clipContainer and heightPct and heightPct < 100 then
            -- Height reduction active: reparent into clipping container
            if st.healPredReparented then return end

            st.healPredOrigParents = st.healPredOrigParents or {}
            st.healPredOrigPoints = st.healPredOrigPoints or {}

            for _, key in ipairs(healPredBarKeys) do
                local child = bar[key]
                if child and not (child.IsForbidden and child:IsForbidden()) then
                    st.healPredOrigParents[key] = child:GetParent()
                    local points = {}
                    for i = 1, child:GetNumPoints() do
                        local point, relativeTo, relativePoint, xOfs, yOfs = child:GetPoint(i)
                        points[i] = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, xOfs = xOfs, yOfs = yOfs }
                    end
                    st.healPredOrigPoints[key] = points
                    pcall(child.SetParent, child, clipContainer)
                    -- Don't change anchors — Blizzard's UnitFrameHealPredictionBars_Update
                    -- uses explicit relativeTo references that remain valid across parents.
                end
            end
            st.healPredReparented = true
        else
            -- Height reduction disabled: restore original parents
            if not st.healPredReparented then return end

            for _, key in ipairs(healPredBarKeys) do
                local child = bar[key]
                if child and not (child.IsForbidden and child:IsForbidden()) then
                    local origParent = st.healPredOrigParents and st.healPredOrigParents[key]
                    if origParent then
                        pcall(child.SetParent, child, origParent)
                        local points = st.healPredOrigPoints and st.healPredOrigPoints[key]
                        if points and #points > 0 then
                            child:ClearAllPoints()
                            for _, pt in ipairs(points) do
                                child:SetPoint(pt.point, pt.relativeTo, pt.relativePoint, pt.xOfs, pt.yOfs)
                            end
                        end
                    end
                end
            end
            st.healPredReparented = false
            st.healPredOrigParents = nil
            st.healPredOrigPoints = nil
        end
    end

    -- Optional rectangular overlay for unit frame health bars when the portrait is hidden.
    -- This is used to visually "fill in" the right-side chip on Target/Focus when the
    -- circular portrait is hidden, without replacing the stock StatusBar frame.
    -- Also used for "Color by Value" mode to avoid modifying Blizzard's protected textures.
    local function updateRectHealthOverlay(unit, bar)
        local st = getState(bar)
        local overlay = st and st.rectFill or nil
        if not bar or not overlay then return end

        local statusBarTex = bar:GetStatusBarTexture()

        if not (st and st.rectActive) then
            overlay:Hide()
            -- Restore Blizzard's native texture visibility when overlay is inactive
            if statusBarTex and statusBarTex.SetAlpha then
                pcall(statusBarTex.SetAlpha, statusBarTex, 1)
            end
            if bar.HealthBarTexture and bar.HealthBarTexture.SetAlpha then
                pcall(bar.HealthBarTexture.SetAlpha, bar.HealthBarTexture, 1)
            end
            return
        end
        -- PetFrame's managed UnitFrame updates (heal prediction sizing) can be triggered by
        -- innocuous StatusBar reads from addon code, and may hard-error due to "secret values" inside
        -- Blizzard_UnitFrame (e.g., myCurrentHealAbsorb comparisons). This overlay is purely cosmetic,
        -- so we disable it for Pet to guarantee preset/profile application can't provoke that path.
        if st and st.rectDisabledForSecretValues then
            -- Important: do not call methods (Hide/Show/SetWidth/etc.) from inside the
            -- bar:SetValue / bar:SetMinMaxValues hook path when we're in a "secret value"
            -- environment. This overlay is cosmetic; we prefer a complete no-op.
            return
        end
        -- Instead of reading values (GetMinMaxValues, GetValue, GetWidth) which return
        -- "secret values", the overlay anchors directly to the StatusBarTexture. The StatusBarTexture
        -- is the actual "fill" portion of the StatusBar and automatically scales with health value.
        if not statusBarTex then
            overlay:Hide()
            return
        end

        overlay:ClearAllPoints()
        overlay:SetAllPoints(statusBarTex)
        overlay:Show()

        -- CRITICAL: Hide Blizzard's native texture(s) so they don't show through as white.
        -- The overlay is our controlled texture that receives the value-based color.
        -- Without hiding the native texture, you see "white mixed with color" at low alpha
        -- and "pure white" at full alpha.
        if statusBarTex and statusBarTex.SetAlpha then
            pcall(statusBarTex.SetAlpha, statusBarTex, 0)
        end
        -- Also hide the named HealthBarTexture if it's a different object
        if bar.HealthBarTexture and bar.HealthBarTexture ~= statusBarTex and bar.HealthBarTexture.SetAlpha then
            pcall(bar.HealthBarTexture.SetAlpha, bar.HealthBarTexture, 0)
        end
    end

    -- Power bar foreground overlay: addon-owned texture that sits above the StatusBar fill.
    -- Unlike the health overlay (which fills portrait gaps), this overlay exists to persist
    -- custom textures/colors through combat. Because it's our own texture (not a protected
    -- StatusBar region), no combat guard is needed.
    local function updateRectPowerOverlay(unit, bar)
        local st = getState(bar)
        local overlay = st and st.powerFill or nil
        if not bar or not overlay then return end
        if not (st and st.powerOverlayActive) then
            overlay:Hide()
            return
        end

        local okTex, statusBarTex = pcall(bar.GetStatusBarTexture, bar)
        if not okTex then statusBarTex = nil end

        overlay:ClearAllPoints()
        if statusBarTex then
            overlay:SetAllPoints(statusBarTex)
        else
            overlay:SetAllPoints(bar)
        end
        overlay:Show()
    end

    local function ensureRectHealthOverlay(unit, bar, cfg)
        if not bar then return end

        local db = addon and addon.db and addon.db.profile
        if not db then return end
        -- Zero‑Touch: do not create config tables. If this unit has no config, do nothing.
        local unitFrames = rawget(db, "unitFrames")
        local ufCfg = unitFrames and rawget(unitFrames, unit) or nil
        if not ufCfg then
            return
        end

        -- Determine whether overlay should be active based on unit type and settings:
        -- - Target/Focus: activate when portrait is hidden (fills portrait cut-out on right side)
        -- - Player/TargetOfTarget/Pet: activate when using custom borders (fills top-right corner chip in mask)
        -- - ANY unit: activate when using non-default color mode (custom, class, value, texture)
        --   This ensures the overlay system handles "Color by Value" instead of trying to modify
        --   Blizzard's protected textures directly.
        local shouldActivate = false
        local st = getState(bar)
        if not st then return end

        -- Reset per-call disable flag unless explicitly re-set below.
        st.rectDisabledForSecretValues = nil

        -- Check if non-default color or texture settings require overlay
        local colorMode = cfg and cfg.healthBarColorMode or "default"
        local texKey = cfg and cfg.healthBarTexture or "default"
        local hasNonDefaultColor = (colorMode ~= "default" and colorMode ~= "" and colorMode ~= nil)
        local hasNonDefaultTexture = (texKey ~= "default" and texKey ~= "" and texKey ~= nil)
        local needsOverlayForStyling = hasNonDefaultColor or hasNonDefaultTexture

        if unit == "Target" or unit == "Focus" then
            local portraitCfg = rawget(ufCfg, "portrait")
            local portraitHidden = (portraitCfg and portraitCfg.hidePortrait == true) or false
            shouldActivate = portraitHidden or needsOverlayForStyling
            if cfg and cfg.healthBarReverseFill ~= nil then
                st.rectReverseFill = not not cfg.healthBarReverseFill
            end
        elseif unit == "Player" then
            shouldActivate = (ufCfg.useCustomBorders == true) or needsOverlayForStyling
            st.rectReverseFill = false -- Player health bar always fills left-to-right
        elseif unit == "TargetOfTarget" then
            shouldActivate = (ufCfg.useCustomBorders == true) or needsOverlayForStyling
            st.rectReverseFill = false -- ToT health bar always fills left-to-right
        elseif unit == "FocusTarget" then
            shouldActivate = (ufCfg.useCustomBorders == true) or needsOverlayForStyling
            st.rectReverseFill = false -- FoT health bar always fills left-to-right
        elseif type(unit) == "string" and string.lower(unit) == "pet" then
            -- PetFrame has a small top-right "chip" when we hide Blizzard's border textures
            -- and replace them with a custom border. Use the same overlay approach as Player/ToT.
            shouldActivate = (ufCfg.useCustomBorders == true) or needsOverlayForStyling
            st.rectReverseFill = false -- Pet health bar always fills left-to-right
        else
            -- Others: skip
            if st.rectFill then
                st.rectActive = false
                st.rectFill:Hide()
            end
            return
        end

        -- Deactivate overlay if texture-only hiding is active
        if cfg and cfg.healthBarHideTextureOnly == true then
            shouldActivate = false
        end

        st.rectActive = shouldActivate

        if not shouldActivate then
            if st.rectFill then
                st.rectFill:Hide()
            end
            if st.heightClipContainer then
                st.heightClipContainer:Hide()
            end
            -- Restore original background if it was hidden (ScooterModBG via FrameState, not st.backgroundTex)
            local scooterBG_rst = getProp(bar, "ScooterModBG")
            if st.heightClipBackgroundHidden and scooterBG_rst then
                scooterBG_rst:Show()
                st.heightClipBackgroundHidden = false
            end
            st.heightClipActive = false
            -- Restore AnimatedLossBar to original parent for Player unit
            if unit == "Player" then
                reparentAnimatedLossBar(bar, nil, 100)
            end
            reparentHealPredictionBars(bar, nil, 100)
            return
        end

        -- Get or create clipping container for height reduction
        local clipContainer = ensureHeightClipContainer(bar, unit, cfg)

        -- Reparent AnimatedLossBar into clipping container for Player unit
        if unit == "Player" then
            local heightPct = cfg and cfg.healthBarOverlayHeightPct or 100
            reparentAnimatedLossBar(bar, clipContainer, heightPct)
        end

        -- Reparent heal prediction bars into clipping container for all units
        do
            local heightPct = cfg and cfg.healthBarOverlayHeightPct or 100
            reparentHealPredictionBars(bar, clipContainer, heightPct)
        end

        if not st.rectFill then
            -- Create overlay as child of clipping container (or bar if no height reduction)
            local overlayParent = clipContainer or bar
            local overlay = overlayParent:CreateTexture(nil, "OVERLAY", nil, 2)
            overlay:SetVertTile(false)
            overlay:SetHorizTile(false)
            overlay:SetTexCoord(0, 1, 0, 1)
            st.rectFill = overlay

            -- Drive overlay width from the health bar's own value/size changes.
            -- NOTE: No combat guard needed here because updateRectHealthOverlay() only
            -- operates on ScooterRectFill (our own child texture), not Blizzard's
            -- protected StatusBar. Cosmetic operations on our own textures are safe.
            if _G.hooksecurefunc and not st.rectHooksInstalled then
                st.rectHooksInstalled = true
                _G.hooksecurefunc(bar, "SetValue", function(self)
                    if isEditModeActive() then return end
                    updateRectHealthOverlay(unit, self)
                end)
                _G.hooksecurefunc(bar, "SetMinMaxValues", function(self)
                    if isEditModeActive() then return end
                    updateRectHealthOverlay(unit, self)
                end)
                if bar.HookScript then
                    bar:HookScript("OnSizeChanged", function(self)
                        if isEditModeActive() then return end
                        updateRectHealthOverlay(unit, self)
                    end)
                end
            end

            -- Hook bar size changes to update clipping container dimensions
            if clipContainer and bar.HookScript and not st.heightClipSizeHooked then
                st.heightClipSizeHooked = true
                bar:HookScript("OnSizeChanged", function(self)
                    if isEditModeActive() then return end
                    local s = getState(self)
                    if s and s.heightClipContainer and s.heightClipContainer:IsShown() then
                        local db = addon and addon.db and addon.db.profile
                        local unitFrames = db and rawget(db, "unitFrames")
                        local ufCfg = unitFrames and rawget(unitFrames, unit)
                        local heightPct = ufCfg and ufCfg.healthBarOverlayHeightPct or 100
                        local barHeight = self:GetHeight()
                        local targetHeight = barHeight * (heightPct / 100)
                        local inset = pixelFloor((barHeight - targetHeight) / 2, self)
                        s.heightClipContainer:ClearAllPoints()
                        s.heightClipContainer:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -inset)
                        s.heightClipContainer:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, inset)
                    end
                end)
            end
        elseif st.rectFill then
            -- Overlay already exists - ensure it's parented correctly
            local currentParent = st.rectFill:GetParent()
            if clipContainer then
                -- Height reduction enabled: reparent to clipping container if needed
                if currentParent ~= clipContainer then
                    st.rectFill:SetParent(clipContainer)
                end
            else
                -- Height reduction disabled: reparent back to bar if needed
                if currentParent ~= bar and st.heightClipContainer then
                    st.rectFill:SetParent(bar)
                end
            end
        end

        -- Copy the configured health bar texture/tint so the overlay visually matches.
        -- The CONFIGURED texture from the DB is used rather than reading from the bar,
        -- because GetTexture() can return a number (texture ID) instead of a string path
        -- after SetStatusBarTexture(), which caused the overlay to fall back to WHITE.
        local texKey = cfg.healthBarTexture or "default"
        local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)
        local overlay = st.rectFill
        
        if resolvedPath then
            -- Custom texture configured - use the resolved path
            if overlay and overlay.SetTexture then
                overlay:SetTexture(resolvedPath)
            end
        else
            -- Default texture - try to copy from bar, with fallback chain
            -- CRITICAL: GetTexture() can return an atlas token STRING. Passing an atlas token
            -- to SetTexture() causes the entire spritesheet to render (see UNITFRAMES.md).
            -- We must check if the string is an atlas and use SetAtlas() instead.
            local tex = bar:GetStatusBarTexture()
            local applied = false
            if tex then
                -- First, try GetAtlas() which is the most reliable for atlas-backed textures
                local okAtlas, atlasName = pcall(tex.GetAtlas, tex)
                if okAtlas and atlasName and atlasName ~= "" then
                    if overlay and overlay.SetAtlas then
                        pcall(overlay.SetAtlas, overlay, atlasName, true)
                        applied = true
                    end
                end
                
                if not applied then
                    local okTex, pathOrTex = pcall(tex.GetTexture, tex)
                    if okTex then
                        if type(pathOrTex) == "string" and pathOrTex ~= "" then
                            -- Check if this string is actually an atlas token
                            local isAtlas = _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(pathOrTex) ~= nil
                            if isAtlas and overlay and overlay.SetAtlas then
                                -- Use SetAtlas to avoid spritesheet rendering
                                pcall(overlay.SetAtlas, overlay, pathOrTex, true)
                                applied = true
                            else
                                -- It's a file path, safe to use SetTexture
                                if overlay then overlay:SetTexture(pathOrTex) end
                                applied = true
                            end
                        elseif type(pathOrTex) == "number" and pathOrTex > 0 then
                            -- Texture ID - use it directly
                            if overlay then overlay:SetTexture(pathOrTex) end
                            applied = true
                        end
                    end
                end
            end
            
            -- Fallback to stock health bar atlas for this unit
            if not applied then
                local stockAtlas
                if unit == "Player" then
                    stockAtlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health"
                elseif unit == "Target" then
                    stockAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health"
                elseif unit == "Focus" then
                    stockAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health"
                elseif unit == "TargetOfTarget" then
                    stockAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health" -- ToT shares party atlas
                elseif unit == "FocusTarget" then
                    stockAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health" -- FoT shares party atlas
                elseif unit == "Pet" then
                    -- Best-effort fallback; if this atlas changes, the earlier "copy from bar" path should
                    -- still handle the real default correctly.
                    stockAtlas = "UI-HUD-UnitFrame-Pet-PortraitOn-Bar-Health"
                end
                if stockAtlas and overlay and overlay.SetAtlas then
                    pcall(overlay.SetAtlas, overlay, stockAtlas, true)
                elseif overlay and overlay.SetColorTexture then
                    -- Last resort: use green health color instead of white
                    overlay:SetColorTexture(0, 0.8, 0, 1)
                end
            end
        end

        -- Apply vertex color to match configured color mode
        local colorMode = cfg.healthBarColorMode or "default"
        local tint = cfg.healthBarTint
        local r, g, b, a = 1, 1, 1, 1

        -- Map unit config key to unit token for API calls
        local unitToken = unit
        if unit == "Player" then unitToken = "player"
        elseif unit == "Target" then unitToken = "target"
        elseif unit == "Focus" then unitToken = "focus"
        elseif unit == "Pet" then unitToken = "pet"
        elseif unit == "TargetOfTarget" then unitToken = "targettarget"
        elseif unit == "FocusTarget" then unitToken = "focustarget"
        end

        if colorMode == "value" or colorMode == "valueDark" then
            -- "Color by Value" mode: use UnitHealthPercent with color curve
            -- Apply initial color now; dynamic updates handled by hooks below
            local useDark = (colorMode == "valueDark")
            if addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                -- Pass the overlay as the texture to color
                addon.BarsTextures.applyValueBasedColor(bar, unitToken, overlay, useDark)
            end
            -- Store reference so dynamic updates can find the overlay
            st.valueColorOverlay = overlay
            st.valueColorUseDark = useDark  -- Store for dynamic updates
        elseif colorMode == "custom" and type(tint) == "table" then
            r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
            if overlay and overlay.SetVertexColor then
                overlay:SetVertexColor(r, g, b, a)
            end
        elseif colorMode == "class" and addon.GetClassColorRGB then
            local cr, cg, cb = addon.GetClassColorRGB("player")
            r, g, b, a = cr or 1, cg or 1, cb or 1, 1
            if overlay and overlay.SetVertexColor then
                overlay:SetVertexColor(r, g, b, a)
            end
        elseif colorMode == "texture" then
            -- Preserve texture's original colors
            r, g, b, a = 1, 1, 1, 1
            if overlay and overlay.SetVertexColor then
                overlay:SetVertexColor(r, g, b, a)
            end
        elseif colorMode == "default" then
            -- Use the addon's static health color API as the authoritative source.
            -- GetVertexColor on atlas-backed StatusBarTextures (e.g., Pet) returns white
            -- because the color is baked into the atlas, not applied via vertex color.
            if addon.GetDefaultHealthColorRGB then
                local hr, hg, hb = addon.GetDefaultHealthColorRGB()
                r, g, b = hr or 0, hg or 1, hb or 0
            else
                -- Fallback: try to get the bar's current vertex color
                local tex = bar:GetStatusBarTexture()
                if tex and tex.GetVertexColor then
                    local ok, vr, vg, vb, va = pcall(tex.GetVertexColor, tex)
                    if ok then
                        r, g, b, a = vr or 1, vg or 1, vb or 1, va or 1
                    end
                end
            end
            if overlay and overlay.SetVertexColor then
                overlay:SetVertexColor(r, g, b, a)
            end
        end

        -- Ensure text containers are raised above the clipping container when height reduction is active
        if st.heightClipActive then
            ensureTextAndBorderOrdering(unit)
        end

        updateRectHealthOverlay(unit, bar)
    end

    -- Power bar foreground overlay: ensures a combat-safe addon-owned texture sits above
    -- the StatusBar fill so custom texture/color persists through combat resets.
    local function ensureRectPowerOverlay(unit, bar, cfg)
        if not bar then return end
        if not cfg then return end

        local texKey = cfg.powerBarTexture or "default"
        local colorMode = cfg.powerBarColorMode or "default"

        -- Determine whether overlay should be active: only for non-default settings
        local isDefaultTexture = (texKey == "default" or texKey == "" or texKey == nil)
        local isDefaultColor = (colorMode == "default" or colorMode == "" or colorMode == nil)
        local shouldActivate = not (isDefaultTexture and isDefaultColor)

        -- Deactivate overlay if bar is hidden or texture-only-hidden
        if cfg.powerBarHidden == true or cfg.powerBarHideTextureOnly == true then
            shouldActivate = false
        end

        local st = getState(bar)
        if not st then return end

        st.powerOverlayActive = shouldActivate

        if not shouldActivate then
            if st.powerFill then
                st.powerFill:Hide()
                -- Restore original fill visibility
                local okTex, statusBarTex = pcall(bar.GetStatusBarTexture, bar)
                if okTex and statusBarTex then
                    pcall(statusBarTex.SetAlpha, statusBarTex, 1)
                end
            end
            return
        end

        -- Create overlay texture once per bar
        if not st.powerFill then
            local createOk, overlay = pcall(bar.CreateTexture, bar, nil, "OVERLAY", nil, 2)
            if not createOk or not overlay then return end
            pcall(overlay.SetVertTile, overlay, false)
            pcall(overlay.SetHorizTile, overlay, false)
            pcall(overlay.SetTexCoord, overlay, 0, 1, 0, 1)
            st.powerFill = overlay

            -- Drive overlay position from bar value/size changes.
            -- No combat guard needed: only touches addon-owned texture.
            if _G.hooksecurefunc and not st.powerOverlayHooksInstalled then
                local hookOk = pcall(function()
                    _G.hooksecurefunc(bar, "SetValue", function(self)
                        if isEditModeActive() then return end
                        updateRectPowerOverlay(unit, self)
                    end)
                    _G.hooksecurefunc(bar, "SetMinMaxValues", function(self)
                        if isEditModeActive() then return end
                        updateRectPowerOverlay(unit, self)
                    end)
                    if bar.HookScript then
                        bar:HookScript("OnSizeChanged", function(self)
                            if isEditModeActive() then return end
                            updateRectPowerOverlay(unit, self)
                        end)
                    end
                end)
                if hookOk then st.powerOverlayHooksInstalled = true end
            end

            -- Sync hook: SetStatusBarTexture
            -- When Blizzard swaps the fill texture (e.g., Druid form change), re-anchor overlay,
            -- re-hide the new fill, and install alpha enforcement on it.
            if _G.hooksecurefunc and not st.powerOverlayTexSyncHooked then
                local hookOk = pcall(function()
                    _G.hooksecurefunc(bar, "SetStatusBarTexture", function(self, ...)
                        if isEditModeActive() then return end
                        local s = getState(self)
                        if not (s and s.powerOverlayActive) then return end
                        if getProp(self, "ufInternalTextureWrite") then return end
                        local newTex = self:GetStatusBarTexture()
                        if newTex then
                            pcall(newTex.SetAlpha, newTex, 0)
                            -- Install enforcement on new texture if not already hooked
                            if not getProp(newTex, "powerOverlayAlphaHooked") then
                                setProp(newTex, "powerOverlayAlphaHooked", true)
                                pcall(function()
                                    _G.hooksecurefunc(newTex, "SetAlpha", function(tex, alpha)
                                        local barState = getState(self)
                                        if barState and barState.powerOverlayActive and alpha > 0 then
                                            if not getProp(tex, "powerOverlaySettingAlpha") then
                                                setProp(tex, "powerOverlaySettingAlpha", true)
                                                tex:SetAlpha(0)
                                                setProp(tex, "powerOverlaySettingAlpha", nil)
                                            end
                                        end
                                    end)
                                end)
                            end
                        end
                        updateRectPowerOverlay(unit, self)
                    end)
                end)
                if hookOk then st.powerOverlayTexSyncHooked = true end
            end

            -- Sync hook: SetStatusBarColor
            -- When Blizzard changes the power color (power type change), update overlay
            -- vertex color if using "default" color mode.
            if _G.hooksecurefunc and not st.powerOverlayColorSyncHooked then
                local hookOk = pcall(function()
                    _G.hooksecurefunc(bar, "SetStatusBarColor", function(self)
                        if isEditModeActive() then return end
                        local s = getState(self)
                        if not (s and s.powerOverlayActive and s.powerFill) then return end
                        local db = addon and addon.db and addon.db.profile
                        if not db then return end
                        local unitFrames = rawget(db, "unitFrames")
                        local cfgNow = unitFrames and rawget(unitFrames, unit) or nil
                        if not cfgNow then return end
                        local cm = cfgNow.powerBarColorMode or "default"
                        if cm == "default" or cm == "power" then
                            local uid = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or (unit == "Pet" and "pet") or (unit == "TargetOfTarget" and "targettarget") or (unit == "FocusTarget" and "focustarget") or "player"
                            if addon.GetPowerColorRGB then
                                local pr, pg, pb = addon.GetPowerColorRGB(uid)
                                if pr and s.powerFill and s.powerFill.SetVertexColor then
                                    s.powerFill:SetVertexColor(pr, pg, pb, 1)
                                end
                            end
                        end
                    end)
                end)
                if hookOk then st.powerOverlayColorSyncHooked = true end
            end
        end

        local overlay = st.powerFill

        -- Apply texture to overlay
        local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)

        if resolvedPath then
            -- Custom texture configured
            if overlay and overlay.SetTexture then
                overlay:SetTexture(resolvedPath)
            end
        else
            -- Default texture: copy from bar's StatusBarTexture with atlas detection
            local okSBT, tex = pcall(bar.GetStatusBarTexture, bar)
            if not okSBT then tex = nil end
            local applied = false
            if tex then
                local okAtlas, atlasName = pcall(tex.GetAtlas, tex)
                if okAtlas and atlasName and atlasName ~= "" then
                    if overlay and overlay.SetAtlas then
                        pcall(overlay.SetAtlas, overlay, atlasName, true)
                        applied = true
                    end
                end

                if not applied then
                    local okTex, pathOrTex = pcall(tex.GetTexture, tex)
                    if okTex then
                        if type(pathOrTex) == "string" and pathOrTex ~= "" then
                            local isAtlas = _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(pathOrTex) ~= nil
                            if isAtlas and overlay and overlay.SetAtlas then
                                pcall(overlay.SetAtlas, overlay, pathOrTex, true)
                                applied = true
                            else
                                if overlay then overlay:SetTexture(pathOrTex) end
                                applied = true
                            end
                        elseif type(pathOrTex) == "number" and pathOrTex > 0 then
                            if overlay then overlay:SetTexture(pathOrTex) end
                            applied = true
                        end
                    end
                end
            end

            if not applied then
                -- Fallback: use a solid color texture matching power color
                local unitId = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or (unit == "Pet" and "pet") or (unit == "TargetOfTarget" and "targettarget") or (unit == "FocusTarget" and "focustarget") or "player"
                if overlay and overlay.SetColorTexture then
                    local pr, pg, pb = 0, 0, 1
                    if addon.GetPowerColorRGB then
                        pr, pg, pb = addon.GetPowerColorRGB(unitId)
                    end
                    overlay:SetColorTexture(pr or 0, pg or 0, pb or 1, 1)
                end
            end
        end

        -- Apply vertex color to overlay based on color mode
        local unitId = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or (unit == "Pet" and "pet") or (unit == "TargetOfTarget" and "targettarget") or (unit == "FocusTarget" and "focustarget") or "player"
        local tint = cfg.powerBarTint
        local r, g, b, a = 1, 1, 1, 1
        if colorMode == "custom" and type(tint) == "table" then
            r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
        elseif colorMode == "class" and addon.GetClassColorRGB then
            local cr, cg, cb = addon.GetClassColorRGB("player")
            r, g, b, a = cr or 1, cg or 1, cb or 1, 1
        elseif colorMode == "texture" then
            r, g, b, a = 1, 1, 1, 1
        elseif colorMode == "default" or colorMode == "power" then
            -- Use the addon's power color API as the authoritative source.
            -- This avoids issues where the fill texture's vertex color may be stale/white
            -- after Blizzard resets the StatusBarTexture on combat entry.
            if addon.GetPowerColorRGB then
                local pr, pg, pb = addon.GetPowerColorRGB(unitId)
                if pr then r, g, b = pr, pg, pb end
            end
        end
        if overlay and overlay.SetVertexColor then
            overlay:SetVertexColor(r, g, b, a)
        end

        -- Hide the original fill texture via alpha with persistent enforcement.
        -- Blizzard resets the fill's alpha during power value updates; without enforcement,
        -- the fill becomes visible through the semi-transparent overlay at low frame opacity.
        local okTex, statusBarTex = pcall(bar.GetStatusBarTexture, bar)
        if okTex and statusBarTex then
            pcall(statusBarTex.SetAlpha, statusBarTex, 0)
            -- Install enforcement hook (once per texture) using recursion guard pattern
            if not getProp(statusBarTex, "powerOverlayAlphaHooked") then
                setProp(statusBarTex, "powerOverlayAlphaHooked", true)
                pcall(function()
                    _G.hooksecurefunc(statusBarTex, "SetAlpha", function(self, alpha)
                        local barState = getState(bar)
                        if barState and barState.powerOverlayActive and alpha > 0 then
                            if not getProp(self, "powerOverlaySettingAlpha") then
                                setProp(self, "powerOverlaySettingAlpha", true)
                                self:SetAlpha(0)
                                setProp(self, "powerOverlaySettingAlpha", nil)
                            end
                        end
                    end)
                end)
            end
        end

        updateRectPowerOverlay(unit, bar)
    end

    -- Expose helpers for other modules (Cast Bar styling, etc.)
    addon._ApplyToStatusBar = applyToBar
    addon._ApplyBackgroundToStatusBar = applyBackgroundToBar

    local function applyForUnit(unit)
        local db = addon and addon.db and addon.db.profile
        if not db then return end
        -- Zero‑Touch: do not create config tables. If this unit has no config, do nothing.
        local unitFrames = rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, unit) or nil
        if not cfg then
            return
        end

        -- Zero‑Touch: only apply when at least one bar-related setting is explicitly configured.
        local function hasAnyKey(tbl, keys)
            if not tbl then return false end
            for i = 1, #keys do
                if tbl[keys[i]] ~= nil then return true end
            end
            return false
        end
        local hasAnyBarSetting =
            hasAnyKey(cfg, {
                "useCustomBorders",
                "healthBarTexture", "healthBarColorMode", "healthBarTint",
                "healthBarBackgroundTexture", "healthBarBackgroundColorMode", "healthBarBackgroundTint", "healthBarBackgroundOpacity",
                "powerBarTexture", "powerBarColorMode", "powerBarTint",
                "powerBarBackgroundTexture", "powerBarBackgroundColorMode", "powerBarBackgroundTint", "powerBarBackgroundOpacity",
                "powerBarHidden",
                "borderStyle", "borderThickness", "borderInset", "borderInsetH", "borderInsetV", "borderTintEnable", "borderTintColor",
                "healthBarReverseFill",
            })
        local altCfg = rawget(cfg, "altPowerBar")
        if not hasAnyBarSetting and not hasAnyKey(altCfg, { "enabled", "width", "height", "x", "y", "fontFace", "size", "style", "color", "alignment" }) then
            return
        end
        local frame = getUnitFrameFor(unit)
        if not frame then return end

        -- PetFrame is a managed/protected unit frame. Direct bar writes (SetStatusBarTexture)
        -- can trigger Blizzard's internal heal prediction update callbacks that error on "secret values".
        -- For Pet we use the overlay-only approach: ensureRectHealthOverlay() creates an addon-owned
        -- texture that uses SetAllPoints(statusBarTex) anchoring instead of value reads.
        -- We skip applyToBar() to avoid touching Blizzard's StatusBar directly.
        if unit == "Pet" then
            -- Hide PetFrameTexture (art hiding) - same pattern as line 3658+
            local ft = resolveUnitFrameFrameTexture(unit)
            if ft then
                local function compute()
                    local db2 = addon and addon.db and addon.db.profile
                    local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                    local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
                    local hide = cfg2 and (cfg2.useCustomBorders or cfg2.healthBarHideBorder)
                    return hide and 0 or 1
                end
                applyAlpha(ft, compute())
                hookAlphaEnforcer(ft, compute)
            end

            -- OVERLAY APPROACH: Instead of calling applyToBar() (which writes SetStatusBarTexture
            -- to Blizzard's bar and can trigger heal prediction updates), use ensureRectHealthOverlay()
            -- which creates an addon-owned overlay texture. The overlay uses SetAllPoints(statusBarTex)
            -- anchoring instead of reading values.
            local hb = resolveHealthBar(frame, unit)
            if hb then
                ensureRectHealthOverlay(unit, hb, cfg)
            end

            -- Apply background texture (overlay approach only handles foreground)
            if hb then
                local bgTexKeyHB = cfg.healthBarBackgroundTexture
                local bgColorModeHB = cfg.healthBarBackgroundColorMode
                local bgOpacityHB = tonumber(cfg.healthBarBackgroundOpacity)
                local hasBackgroundCustomization = bgTexKeyHB or bgColorModeHB or (bgOpacityHB and bgOpacityHB ~= 1)
                if hasBackgroundCustomization then
                    applyBackgroundToBar(hb, bgTexKeyHB, bgColorModeHB, cfg.healthBarBackgroundTint, bgOpacityHB, unit, "health")
                end
            end

            -- BORDER APPROACH: BarBorders.ApplyToBarFrame uses GetFrameLevel/GetHeight
            -- without pcall wrappers (barborders.lua lines 79, 84, 92), which can trigger
            -- secret value errors on Pet. Use an addon-owned anchor frame like Boss frames do.
            if hb and cfg.useCustomBorders then
                local styleKey = cfg.healthBarBorderStyle
                if styleKey == "none" or styleKey == nil then
                    -- Clear any existing border
                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                        local anchor = getProp(hb, "petHealthBorderAnchor")
                        if anchor then addon.BarBorders.ClearBarFrame(anchor) end
                    end
                    if addon.Borders and addon.Borders.HideAll then
                        local anchor = getProp(hb, "petHealthBorderAnchor")
                        if anchor then addon.Borders.HideAll(anchor) end
                    end
                else
                    -- Create or retrieve Pet border anchor frame
                    local anchorFrame = getProp(hb, "petHealthBorderAnchor")
                    if not anchorFrame then
                        anchorFrame = CreateFrame("Frame", nil, hb)
                        setProp(hb, "petHealthBorderAnchor", anchorFrame)
                    end
                    -- Anchor to clipping container if height reduction active, else health bar
                    anchorFrame:ClearAllPoints()
                    local st = getState(hb)
                    local borderTarget = (st and st.heightClipContainer and st.heightClipActive) and st.heightClipContainer or hb
                    anchorFrame:SetAllPoints(borderTarget)
                    -- Set frame level above the health bar so borders draw on top
                    local parentLevel = 10 -- fallback if GetFrameLevel returns secret
                    local ok, level = pcall(function() return hb:GetFrameLevel() end)
                    if ok and type(level) == "number" then
                        parentLevel = level
                    end
                    anchorFrame:SetFrameLevel(parentLevel + 5)
                    anchorFrame:Show()

                    -- Apply border settings
                    local tintEnabled = not not cfg.healthBarBorderTintEnable
                    local tintColor = type(cfg.healthBarBorderTintColor) == "table" and {
                        cfg.healthBarBorderTintColor[1] or 1,
                        cfg.healthBarBorderTintColor[2] or 1,
                        cfg.healthBarBorderTintColor[3] or 1,
                        cfg.healthBarBorderTintColor[4] or 1,
                    } or {1, 1, 1, 1}
                    local thickness = tonumber(cfg.healthBarBorderThickness) or 1
                    if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
                    local insetH = tonumber(cfg.healthBarBorderInsetH) or tonumber(cfg.healthBarBorderInset) or 0
                    local insetV = tonumber(cfg.healthBarBorderInsetV) or tonumber(cfg.healthBarBorderInset) or 0

                    -- Clear old borders first
                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                        addon.BarBorders.ClearBarFrame(anchorFrame)
                    end
                    if addon.Borders and addon.Borders.HideAll then
                        addon.Borders.HideAll(anchorFrame)
                    end

                    -- Use Borders.ApplySquare with skipDimensionCheck (anchor dimensions are inherited via SetAllPoints)
                    if addon.Borders and addon.Borders.ApplySquare then
                        local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
                        local baseOffset = 1
                        local expandX = baseOffset - insetH
                        local expandY = baseOffset - insetV
                        if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                        if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                        addon.Borders.ApplySquare(anchorFrame, {
                            size = thickness,
                            color = sqColor,
                            layer = "OVERLAY",
                            layerSublevel = 3,
                            expandX = expandX,
                            expandY = expandY,
                            skipDimensionCheck = true, -- Bypass GetWidth/GetHeight check
                        })
                    end
                end
            end

            -- Power bar visibility (hide/show via alpha enforcer only)
            local pb = resolvePowerBar(frame, unit)
            if not pb then
                pb = frame and frame.PetFrameManaBar
            end
            if pb then
                local function computePBAlpha()
                    local db2 = addon and addon.db and addon.db.profile
                    local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                    local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
                    local hidden = cfg2 and cfg2.powerBarHidden
                    return hidden and 0 or 1
                end
                applyAlpha(pb, computePBAlpha())
                hookAlphaEnforcer(pb, computePBAlpha)
            end

            return
        end

        -- TargetOfTarget uses the party frame template (like Pet) and is a protected frame.
        -- Direct bar writes and getters can trigger secret value errors. Use the same overlay+anchor
        -- pattern as Pet for safe border handling.
        if unit == "TargetOfTarget" then
            -- Hide FrameTexture (art hiding) - same pattern as Pet
            local ft = resolveUnitFrameFrameTexture(unit)
            if ft then
                local function compute()
                    local db2 = addon and addon.db and addon.db.profile
                    local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                    local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
                    local hide = cfg2 and (cfg2.useCustomBorders or cfg2.healthBarHideBorder)
                    return hide and 0 or 1
                end
                applyAlpha(ft, compute())
                hookAlphaEnforcer(ft, compute)
            end

            -- OVERLAY APPROACH: Use ensureRectHealthOverlay() which creates an addon-owned
            -- overlay texture using SetAllPoints anchoring.
            local hb = resolveHealthBar(frame, unit)
            if hb then
                ensureRectHealthOverlay(unit, hb, cfg)
            end

            -- Apply foreground color mode (same logic as shared path)
            -- ToT returns early, so we must apply color here instead of in the shared path
            local st = getState(hb)
            if st and st.rectActive and st.rectFill then
                local colorMode = cfg.healthBarColorMode or "default"
                local tint = cfg.healthBarTint
                local overlay = st.rectFill

                if colorMode == "value" or colorMode == "valueDark" then
                    local useDark = (colorMode == "valueDark")
                    if addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                        addon.BarsTextures.applyValueBasedColor(hb, "targettarget", overlay, useDark)
                    end
                    st.valueColorOverlay = overlay
                    st.valueColorUseDark = useDark
                elseif colorMode == "custom" and type(tint) == "table" then
                    overlay:SetVertexColor(tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1)
                elseif colorMode == "class" and addon.GetClassColorRGB then
                    local cr, cg, cb = addon.GetClassColorRGB("player")
                    overlay:SetVertexColor(cr or 1, cg or 1, cb or 1, 1)
                elseif colorMode == "texture" then
                    overlay:SetVertexColor(1, 1, 1, 1)
                elseif colorMode == "default" then
                    if addon.GetDefaultHealthColorRGB then
                        local hr, hg, hb_color = addon.GetDefaultHealthColorRGB()
                        overlay:SetVertexColor(hr or 0, hg or 1, hb_color or 0, 1)
                    else
                        overlay:SetVertexColor(0, 1, 0, 1)
                    end
                end
            end

            -- Apply background texture (overlay approach only handles foreground)
            if hb then
                local bgTexKeyHB = cfg.healthBarBackgroundTexture
                local bgColorModeHB = cfg.healthBarBackgroundColorMode
                local bgOpacityHB = tonumber(cfg.healthBarBackgroundOpacity)
                local hasBackgroundCustomization = bgTexKeyHB or bgColorModeHB or (bgOpacityHB and bgOpacityHB ~= 1)
                if hasBackgroundCustomization then
                    applyBackgroundToBar(hb, bgTexKeyHB, bgColorModeHB, cfg.healthBarBackgroundTint, bgOpacityHB, unit, "health")
                end
            end

            -- BORDER APPROACH: Use an addon-owned anchor frame like Pet does.
            if hb and cfg.useCustomBorders then
                local styleKey = cfg.healthBarBorderStyle
                if styleKey == "none" or styleKey == nil then
                    -- Clear any existing border
                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                        local anchor = getProp(hb, "totHealthBorderAnchor")
                        if anchor then addon.BarBorders.ClearBarFrame(anchor) end
                    end
                    if addon.Borders and addon.Borders.HideAll then
                        local anchor = getProp(hb, "totHealthBorderAnchor")
                        if anchor then addon.Borders.HideAll(anchor) end
                    end
                else
                    -- Create or retrieve ToT border anchor frame
                    local anchorFrame = getProp(hb, "totHealthBorderAnchor")
                    if not anchorFrame then
                        anchorFrame = CreateFrame("Frame", nil, hb)
                        setProp(hb, "totHealthBorderAnchor", anchorFrame)
                    end
                    -- Anchor to clipping container if height reduction active, else health bar
                    anchorFrame:ClearAllPoints()
                    local st = getState(hb)
                    local borderTarget = (st and st.heightClipContainer and st.heightClipActive) and st.heightClipContainer or hb
                    anchorFrame:SetAllPoints(borderTarget)
                    -- Set frame level above the health bar so borders draw on top
                    local parentLevel = 10 -- fallback if GetFrameLevel returns secret
                    local ok, level = pcall(function() return hb:GetFrameLevel() end)
                    if ok and type(level) == "number" then
                        parentLevel = level
                    end
                    anchorFrame:SetFrameLevel(parentLevel + 5)
                    anchorFrame:Show()

                    -- Apply border settings
                    local tintEnabled = not not cfg.healthBarBorderTintEnable
                    local tintColor = type(cfg.healthBarBorderTintColor) == "table" and {
                        cfg.healthBarBorderTintColor[1] or 1,
                        cfg.healthBarBorderTintColor[2] or 1,
                        cfg.healthBarBorderTintColor[3] or 1,
                        cfg.healthBarBorderTintColor[4] or 1,
                    } or {1, 1, 1, 1}
                    local thickness = tonumber(cfg.healthBarBorderThickness) or 1
                    if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
                    local insetH = tonumber(cfg.healthBarBorderInsetH) or tonumber(cfg.healthBarBorderInset) or 0
                    local insetV = tonumber(cfg.healthBarBorderInsetV) or tonumber(cfg.healthBarBorderInset) or 0

                    -- Clear old borders first
                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                        addon.BarBorders.ClearBarFrame(anchorFrame)
                    end
                    if addon.Borders and addon.Borders.HideAll then
                        addon.Borders.HideAll(anchorFrame)
                    end

                    -- Use Borders.ApplySquare with skipDimensionCheck (anchor dimensions are inherited via SetAllPoints)
                    if addon.Borders and addon.Borders.ApplySquare then
                        local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
                        local baseOffset = 1
                        local expandX = baseOffset - insetH
                        local expandY = baseOffset - insetV
                        if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                        if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                        addon.Borders.ApplySquare(anchorFrame, {
                            size = thickness,
                            color = sqColor,
                            layer = "OVERLAY",
                            layerSublevel = 3,
                            expandX = expandX,
                            expandY = expandY,
                            skipDimensionCheck = true, -- Bypass GetWidth/GetHeight check
                        })
                    end
                end
            end

            -- Power bar visibility (hide/show via alpha enforcer only)
            local pb = resolvePowerBar(frame, unit)
            if pb then
                local function computePBAlpha()
                    local db2 = addon and addon.db and addon.db.profile
                    local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                    local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
                    local hidden = cfg2 and cfg2.powerBarHidden
                    return hidden and 0 or 1
                end
                applyAlpha(pb, computePBAlpha())
                hookAlphaEnforcer(pb, computePBAlpha)
            end

            return
        end

        -- FocusTarget uses the party frame template (like Pet) and is a protected frame.
        -- Direct bar writes and getters can trigger secret value errors. Use the same overlay+anchor
        -- pattern as Pet for safe border handling.
        if unit == "FocusTarget" then
            -- Hide FrameTexture (art hiding) - same pattern as Pet
            local ft = resolveUnitFrameFrameTexture(unit)
            if ft then
                local function compute()
                    local db2 = addon and addon.db and addon.db.profile
                    local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                    local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
                    local hide = cfg2 and (cfg2.useCustomBorders or cfg2.healthBarHideBorder)
                    return hide and 0 or 1
                end
                applyAlpha(ft, compute())
                hookAlphaEnforcer(ft, compute)
            end

            -- OVERLAY APPROACH: Use ensureRectHealthOverlay() which creates an addon-owned
            -- overlay texture using SetAllPoints anchoring.
            local hb = resolveHealthBar(frame, unit)
            if hb then
                ensureRectHealthOverlay(unit, hb, cfg)
            end

            -- Apply foreground color mode (same logic as shared path)
            -- FoT returns early, so we must apply color here instead of in the shared path
            local st = getState(hb)
            if st and st.rectActive and st.rectFill then
                local colorMode = cfg.healthBarColorMode or "default"
                local tint = cfg.healthBarTint
                local overlay = st.rectFill

                if colorMode == "value" or colorMode == "valueDark" then
                    local useDark = (colorMode == "valueDark")
                    if addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                        addon.BarsTextures.applyValueBasedColor(hb, "focustarget", overlay, useDark)
                    end
                    st.valueColorOverlay = overlay
                    st.valueColorUseDark = useDark
                elseif colorMode == "custom" and type(tint) == "table" then
                    overlay:SetVertexColor(tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1)
                elseif colorMode == "class" and addon.GetClassColorRGB then
                    local cr, cg, cb = addon.GetClassColorRGB("player")
                    overlay:SetVertexColor(cr or 1, cg or 1, cb or 1, 1)
                elseif colorMode == "texture" then
                    overlay:SetVertexColor(1, 1, 1, 1)
                elseif colorMode == "default" then
                    if addon.GetDefaultHealthColorRGB then
                        local hr, hg, hb_color = addon.GetDefaultHealthColorRGB()
                        overlay:SetVertexColor(hr or 0, hg or 1, hb_color or 0, 1)
                    else
                        overlay:SetVertexColor(0, 1, 0, 1)
                    end
                end
            end

            -- Apply background texture (overlay approach only handles foreground)
            if hb then
                local bgTexKeyHB = cfg.healthBarBackgroundTexture
                local bgColorModeHB = cfg.healthBarBackgroundColorMode
                local bgOpacityHB = tonumber(cfg.healthBarBackgroundOpacity)
                local hasBackgroundCustomization = bgTexKeyHB or bgColorModeHB or (bgOpacityHB and bgOpacityHB ~= 1)
                if hasBackgroundCustomization then
                    applyBackgroundToBar(hb, bgTexKeyHB, bgColorModeHB, cfg.healthBarBackgroundTint, bgOpacityHB, unit, "health")
                end
            end

            -- BORDER APPROACH: Use an addon-owned anchor frame like Pet does.
            if hb and cfg.useCustomBorders then
                local styleKey = cfg.healthBarBorderStyle
                if styleKey == "none" or styleKey == nil then
                    -- Clear any existing border
                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                        local anchor = getProp(hb, "fotHealthBorderAnchor")
                        if anchor then addon.BarBorders.ClearBarFrame(anchor) end
                    end
                    if addon.Borders and addon.Borders.HideAll then
                        local anchor = getProp(hb, "fotHealthBorderAnchor")
                        if anchor then addon.Borders.HideAll(anchor) end
                    end
                else
                    -- Create or retrieve FoT border anchor frame
                    local anchorFrame = getProp(hb, "fotHealthBorderAnchor")
                    if not anchorFrame then
                        anchorFrame = CreateFrame("Frame", nil, hb)
                        setProp(hb, "fotHealthBorderAnchor", anchorFrame)
                    end
                    -- Anchor to clipping container if height reduction active, else health bar
                    anchorFrame:ClearAllPoints()
                    local st = getState(hb)
                    local borderTarget = (st and st.heightClipContainer and st.heightClipActive) and st.heightClipContainer or hb
                    anchorFrame:SetAllPoints(borderTarget)
                    -- Set frame level above the health bar so borders draw on top
                    local parentLevel = 10 -- fallback if GetFrameLevel returns secret
                    local ok, level = pcall(function() return hb:GetFrameLevel() end)
                    if ok and type(level) == "number" then
                        parentLevel = level
                    end
                    anchorFrame:SetFrameLevel(parentLevel + 5)
                    anchorFrame:Show()

                    -- Apply border settings
                    local tintEnabled = not not cfg.healthBarBorderTintEnable
                    local tintColor = type(cfg.healthBarBorderTintColor) == "table" and {
                        cfg.healthBarBorderTintColor[1] or 1,
                        cfg.healthBarBorderTintColor[2] or 1,
                        cfg.healthBarBorderTintColor[3] or 1,
                        cfg.healthBarBorderTintColor[4] or 1,
                    } or {1, 1, 1, 1}
                    local thickness = tonumber(cfg.healthBarBorderThickness) or 1
                    if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
                    local insetH = tonumber(cfg.healthBarBorderInsetH) or tonumber(cfg.healthBarBorderInset) or 0
                    local insetV = tonumber(cfg.healthBarBorderInsetV) or tonumber(cfg.healthBarBorderInset) or 0

                    -- Clear old borders first
                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                        addon.BarBorders.ClearBarFrame(anchorFrame)
                    end
                    if addon.Borders and addon.Borders.HideAll then
                        addon.Borders.HideAll(anchorFrame)
                    end

                    -- Use Borders.ApplySquare with skipDimensionCheck (anchor dimensions are inherited via SetAllPoints)
                    if addon.Borders and addon.Borders.ApplySquare then
                        local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
                        local baseOffset = 1
                        local expandX = baseOffset - insetH
                        local expandY = baseOffset - insetV
                        if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                        if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                        addon.Borders.ApplySquare(anchorFrame, {
                            size = thickness,
                            color = sqColor,
                            layer = "OVERLAY",
                            layerSublevel = 3,
                            expandX = expandX,
                            expandY = expandY,
                            skipDimensionCheck = true, -- Bypass GetWidth/GetHeight check
                        })
                    end
                end
            end

            -- Power bar visibility (hide/show via alpha enforcer only)
            local pb = resolvePowerBar(frame, unit)
            if pb then
                local function computePBAlpha()
                    local db2 = addon and addon.db and addon.db.profile
                    local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                    local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
                    local hidden = cfg2 and cfg2.powerBarHidden
                    return hidden and 0 or 1
                end
                applyAlpha(pb, computePBAlpha())
                hookAlphaEnforcer(pb, computePBAlpha)
            end

            return
        end

        -- Boss unit frames commonly appear/update during combat (e.g., INSTANCE_ENCOUNTER_ENGAGE_UNIT / UPDATE_BOSS_FRAMES).
        -- IMPORTANT (taint): Even "cosmetic-only" writes to Boss unit frame regions (including SetAlpha on textures)
        -- can taint the Boss system and later block protected layout calls like BossTargetFrameContainer:SetSize().
        -- Do not mutate protected unit frame regions during combat. If Boss needs a re-assertion,
        -- queue a post-combat reapply instead.
        if unit == "Boss" then
            if InCombatLockdown and InCombatLockdown() then
                queueUnitFrameTextureReapply("Boss")
            else
                for i = 1, 5 do
                    local bossFrame = _G["Boss" .. i .. "TargetFrame"]
                    if bossFrame then
                        -- FrameTexture (hide for useCustomBorders OR healthBarHideBorder)
                        local bossFT = bossFrame.TargetFrameContainer and bossFrame.TargetFrameContainer.FrameTexture
                        if bossFT then
                            local function computeBossFTAlpha()
                                local db2 = addon and addon.db and addon.db.profile
                                local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                                local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                                local hide = cfgBoss and (cfgBoss.useCustomBorders or cfgBoss.healthBarHideBorder)
                                return hide and 0 or 1
                            end
                            applyAlpha(bossFT, computeBossFTAlpha())
                            hookAlphaEnforcer(bossFT, computeBossFTAlpha)
                        end

                        -- Flash (aggro/threat glow) (hide for useCustomBorders)
                        local bossFlash = bossFrame.TargetFrameContainer and bossFrame.TargetFrameContainer.Flash
                        if bossFlash then
                            local function computeBossFlashAlpha()
                                local db2 = addon and addon.db and addon.db.profile
                                local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                                local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                                return (cfgBoss and cfgBoss.useCustomBorders) and 0 or 1
                            end
                            applyAlpha(bossFlash, computeBossFlashAlpha())
                            hookAlphaEnforcer(bossFlash, computeBossFlashAlpha)
                        end

                        -- ReputationColor strip (hide for useCustomBorders)
                        local bossReputationColor = bossFrame.TargetFrameContent
                            and bossFrame.TargetFrameContent.TargetFrameContentMain
                            and bossFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                        if bossReputationColor then
                            local function computeBossRepAlpha()
                                local db2 = addon and addon.db and addon.db.profile
                                local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                                local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                                return (cfgBoss and cfgBoss.useCustomBorders) and 0 or 1
                            end
                            applyAlpha(bossReputationColor, computeBossRepAlpha())
                            hookAlphaEnforcer(bossReputationColor, computeBossRepAlpha)
                        end
                    end
                end
            end
        end

        -- Target/Focus frames can be updated/rebuilt by Blizzard during combat (rapid target swaps, faction updates, etc.).
        -- We must NEVER touch protected StatusBars/layout during combat, but we CAN safely enforce visual-only overlays
        -- (like ReputationColor) via SetAlpha + alpha enforcers. Do this BEFORE the combat early-return so the element
        -- stays hidden even if Blizzard recreates the region while we're in combat.
        --
        -- IMPORTANT: Blizzard may recreate the ReputationColor texture during rapid target changes. We must:
        -- 1. Always apply alpha (even if _ScootAlphaEnforcerHooked is set on an old object)
        -- 2. Always try to install enforcer (it will skip if already hooked on THIS object)
        -- 3. Schedule a follow-up re-hide to catch late Blizzard updates
        if unit == "Target" or unit == "Focus" then
            local function computeUseCustomBordersAlpha()
                local db2 = addon and addon.db and addon.db.profile
                local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
                return (cfg2 and cfg2.useCustomBorders) and 0 or 1
            end

            local reputationColor
            if unit == "Target" and _G.TargetFrame then
                reputationColor = _G.TargetFrame.TargetFrameContent
                    and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                    and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
            elseif unit == "Focus" and _G.FocusFrame then
                reputationColor = _G.FocusFrame.TargetFrameContent
                    and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                    and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
            end

            if reputationColor then
                -- Always apply current alpha, regardless of hook state
                local desiredAlpha = computeUseCustomBordersAlpha()
                applyAlpha(reputationColor, desiredAlpha)
                hookAlphaEnforcer(reputationColor, computeUseCustomBordersAlpha)
                
                -- Belt-and-suspenders: schedule a follow-up re-hide after Blizzard's updates complete
                -- This catches cases where Blizzard resets alpha after our initial hide
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        -- Re-resolve in case the texture object changed
                        local repColor2
                        if unit == "Target" and _G.TargetFrame then
                            repColor2 = _G.TargetFrame.TargetFrameContent
                                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                        elseif unit == "Focus" and _G.FocusFrame then
                            repColor2 = _G.FocusFrame.TargetFrameContent
                                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                        end
                        if repColor2 and repColor2.SetAlpha then
                            local alpha2 = computeUseCustomBordersAlpha()
                            pcall(repColor2.SetAlpha, repColor2, alpha2)
                            -- Install enforcer on the (possibly new) object
                            hookAlphaEnforcer(repColor2, computeUseCustomBordersAlpha)
                        end
                    end)
                end
            end
        end

        -- Boss frames can also be updated by Blizzard during combat (boss target changes, etc.).
        -- Apply the same early ReputationColor handling pattern as Target/Focus: run BEFORE the combat
        -- early-return so the element stays hidden, with C_Timer follow-up to catch late Blizzard updates.
        if unit == "Boss" then
            local function computeBossUseCustomBordersAlpha()
                local db2 = addon and addon.db and addon.db.profile
                local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                return (cfgBoss and cfgBoss.useCustomBorders) and 0 or 1
            end

            for i = 1, 5 do
                local bossFrame = _G["Boss" .. i .. "TargetFrame"]
                if bossFrame then
                    local bossRepColor = bossFrame.TargetFrameContent
                        and bossFrame.TargetFrameContent.TargetFrameContentMain
                        and bossFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor

                    if bossRepColor then
                        -- Always apply current alpha, regardless of hook state
                        local desiredAlpha = computeBossUseCustomBordersAlpha()
                        applyAlpha(bossRepColor, desiredAlpha)
                        hookAlphaEnforcer(bossRepColor, computeBossUseCustomBordersAlpha)

                        -- Belt-and-suspenders: schedule a follow-up re-hide after Blizzard's updates complete
                        -- This catches cases where Blizzard resets alpha after our initial hide
                        if _G.C_Timer and _G.C_Timer.After then
                            local bossIndex = i  -- Capture loop variable for closure
                            _G.C_Timer.After(0, function()
                                -- Re-resolve in case the texture object changed
                                local bossFrame2 = _G["Boss" .. bossIndex .. "TargetFrame"]
                                local repColor2 = bossFrame2 and bossFrame2.TargetFrameContent
                                    and bossFrame2.TargetFrameContent.TargetFrameContentMain
                                    and bossFrame2.TargetFrameContent.TargetFrameContentMain.ReputationColor
                                if repColor2 and repColor2.SetAlpha then
                                    local alpha2 = computeBossUseCustomBordersAlpha()
                                    pcall(repColor2.SetAlpha, repColor2, alpha2)
                                    -- Install enforcer on the (possibly new) object
                                    hookAlphaEnforcer(repColor2, computeBossUseCustomBordersAlpha)
                                end
                            end)
                        end
                    end
                end
            end
        end

        -- Combat safety: do not touch protected unit frame bars during combat. Queue a post-combat reapply.
        if InCombatLockdown and InCombatLockdown() then
            queueUnitFrameTextureReapply(unit)
            return
        end

        -- Target-of-Target can get refreshed frequently by Blizzard (even out of combat),
        -- which can reset its bar textures. Install a lightweight, throttled hook on the
        -- ToT frame's Update() to re-assert our styling shortly after Blizzard updates it.
        if unit == "TargetOfTarget" and _G.hooksecurefunc then
            local tot = _G.TargetFrameToT
            local totState = getState(tot)
            if tot and totState and not totState.toTUpdateHooked and type(tot.Update) == "function" then
                totState.toTUpdateHooked = true
                _G.hooksecurefunc(tot, "Update", function()
                    if isEditModeActive() then return end
                    local db2 = addon and addon.db and addon.db.profile
                    if not db2 then return end
                    local unitFrames2 = rawget(db2, "unitFrames")
                    local cfgT = unitFrames2 and rawget(unitFrames2, "TargetOfTarget") or nil
                    if not cfgT then
                        return
                    end

                    local texKey = cfgT.healthBarTexture or "default"
                    local colorMode = cfgT.healthBarColorMode or "default"
                    local tint = cfgT.healthBarTint

                    local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                    local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                    if not hasCustomTexture and not hasCustomColor then
                        return
                    end

                    if InCombatLockdown and InCombatLockdown() then
                        queueUnitFrameTextureReapply("TargetOfTarget")
                        return
                    end

                    local state = getState(tot)
                    if state and state.toTReapplyPending then
                        return
                    end
                    if state then state.toTReapplyPending = true end

                    if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                        _G.C_Timer.After(0, function()
                            local st2 = getState(tot)
                            if st2 then st2.toTReapplyPending = nil end
                            addon.ApplyUnitFrameBarTexturesFor("TargetOfTarget")
                        end)
                    elseif addon.ApplyUnitFrameBarTexturesFor then
                        if state then state.toTReapplyPending = nil end
                        addon.ApplyUnitFrameBarTexturesFor("TargetOfTarget")
                    end
                end)
            end
        end

        -- FocusTarget can get refreshed frequently by Blizzard (even out of combat),
        -- which can reset its bar textures. Install a lightweight, throttled hook on the
        -- FoT frame's Update() to re-assert our styling shortly after Blizzard updates it.
        if unit == "FocusTarget" and _G.hooksecurefunc then
            local fot = _G.FocusFrameToT
            local fotState = getState(fot)
            if fot and fotState and not fotState.foTUpdateHooked and type(fot.Update) == "function" then
                fotState.foTUpdateHooked = true
                _G.hooksecurefunc(fot, "Update", function()
                    if isEditModeActive() then return end
                    local db2 = addon and addon.db and addon.db.profile
                    if not db2 then return end
                    local unitFrames2 = rawget(db2, "unitFrames")
                    local cfgF = unitFrames2 and rawget(unitFrames2, "FocusTarget") or nil
                    if not cfgF then
                        return
                    end

                    local texKey = cfgF.healthBarTexture or "default"
                    local colorMode = cfgF.healthBarColorMode or "default"
                    local tint = cfgF.healthBarTint

                    local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                    local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                    if not hasCustomTexture and not hasCustomColor then
                        return
                    end

                    if InCombatLockdown and InCombatLockdown() then
                        queueUnitFrameTextureReapply("FocusTarget")
                        return
                    end

                    local state = getState(fot)
                    if state and state.foTReapplyPending then
                        return
                    end
                    if state then state.foTReapplyPending = true end

                    if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                        _G.C_Timer.After(0, function()
                            local st2 = getState(fot)
                            if st2 then st2.foTReapplyPending = nil end
                            addon.ApplyUnitFrameBarTexturesFor("FocusTarget")
                        end)
                    elseif addon.ApplyUnitFrameBarTexturesFor then
                        if state then state.foTReapplyPending = nil end
                        addon.ApplyUnitFrameBarTexturesFor("FocusTarget")
                    end
                end)
            end
        end

        -- Boss frames: apply to Boss1..Boss5 frames (shared config: db.unitFrames.Boss), then return.
        -- Boss frames are individual TargetFrame variants and are NOT the same as the EditMode system frame.
        if unit == "Boss" then
            local function resolveBossHealthMask(bossFrame)
                -- Get mask from the health bar's parent container (HealthBarsContainer)
                local hb = bossFrame and bossFrame.healthbar
                if hb then
                    local parent = hb:GetParent()
                    if parent and parent.HealthBarMask then return parent.HealthBarMask end
                end
            end
            local function resolveBossPowerMask(bossFrame)
                -- Get mask from the mana bar directly
                local mb = bossFrame and bossFrame.manabar
                if mb and mb.ManaBarMask then return mb.ManaBarMask end
            end

            for i = 1, 5 do
                local bossFrame = _G["Boss" .. i .. "TargetFrame"]
                local unitId = "boss" .. i
                -- Apply styling whenever the frame exists. Let resolveHealthBar/resolvePowerBar
                -- handle finding the actual bars within the frame structure.
                if bossFrame then
                    local hb = resolveHealthBar(bossFrame, unit)
                        if hb then
                            local colorModeHB = cfg.healthBarColorMode or "default"
                            local texKeyHB = cfg.healthBarTexture or "default"
                            applyToBar(hb, texKeyHB, colorModeHB, cfg.healthBarTint, "player", "health", unitId)

                            -- Background overlay (only when explicitly customized)
                            do
                                local function hasBackgroundCustomization()
                                    local texKey = cfg.healthBarBackgroundTexture
                                    if type(texKey) == "string" and texKey ~= "" and texKey ~= "default" then
                                        return true
                                    end
                                    local mode = cfg.healthBarBackgroundColorMode
                                    if type(mode) == "string" and mode ~= "" and mode ~= "default" then
                                        return true
                                    end
                                    local op = cfg.healthBarBackgroundOpacity
                                    local opNum = tonumber(op)
                                    if op ~= nil and opNum ~= nil and opNum ~= 50 then
                                        return true
                                    end
                                    if mode == "custom" and type(cfg.healthBarBackgroundTint) == "table" then
                                        return true
                                    end
                                    return false
                                end
                                if hasBackgroundCustomization() then
                                    local bgTexKeyHB = cfg.healthBarBackgroundTexture or "default"
                                    local bgColorModeHB = cfg.healthBarBackgroundColorMode or "default"
                                    local bgOpacityHB = cfg.healthBarBackgroundOpacity or 50
                                    applyBackgroundToBar(hb, bgTexKeyHB, bgColorModeHB, cfg.healthBarBackgroundTint, bgOpacityHB, unit, "health")
                                end
                            end

                            ensureMaskOnBarTexture(hb, resolveBossHealthMask(bossFrame))

                            -- Rectangular overlay to fill top-left chip when using custom borders
                            ensureBossRectOverlay(bossFrame, hb, cfg, "health")

                            -- Health Bar custom border (same settings as other unit frames)
                            -- BOSS FRAME FIX: The HealthBar StatusBar has oversized dimensions spanning both
                            -- health and power bars. The HealthBarsContainer (parent of HealthBar) has the
                            -- correct bounds because ManaBar is a sibling of HealthBarsContainer, not a child.
                            -- We anchor the border to HealthBarsContainer instead of the StatusBar.
                            do
                                local styleKey = cfg.healthBarBorderStyle
                                local tintEnabled = not not cfg.healthBarBorderTintEnable
                                local tintColor = type(cfg.healthBarBorderTintColor) == "table" and {
                                    cfg.healthBarBorderTintColor[1] or 1,
                                    cfg.healthBarBorderTintColor[2] or 1,
                                    cfg.healthBarBorderTintColor[3] or 1,
                                    cfg.healthBarBorderTintColor[4] or 1,
                                } or {1, 1, 1, 1}
                                local thickness = tonumber(cfg.healthBarBorderThickness) or 1
                                if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
                                local insetH = tonumber(cfg.healthBarBorderInsetH) or tonumber(cfg.healthBarBorderInset) or 0
                                local insetV = tonumber(cfg.healthBarBorderInsetV) or tonumber(cfg.healthBarBorderInset) or 0

                                -- Resolve HealthBarsContainer which has correct bounds (just health bar area)
                                local hbContainer = resolveBossHealthBarsContainer(bossFrame)

                                -- Create or retrieve the anchor frame for border application
                                -- This frame matches the HealthBarsContainer bounds, not the oversized StatusBar
                                local anchorFrame = getProp(hb, "bossHealthBorderAnchor")
                                if not anchorFrame then
                                    anchorFrame = CreateFrame("Frame", nil, hb)
                                    anchorFrame:SetFrameLevel((hb:GetFrameLevel() or 0) + 1)
                                    setProp(hb, "bossHealthBorderAnchor", anchorFrame)
                                end

                                -- Anchor to HealthBarsContainer bounds if available, else clipping container or StatusBar
                                anchorFrame:ClearAllPoints()
                                if hbContainer then
                                    anchorFrame:SetPoint("TOPLEFT", hbContainer, "TOPLEFT", 0, 0)
                                    anchorFrame:SetPoint("BOTTOMRIGHT", hbContainer, "BOTTOMRIGHT", 0, 0)
                                else
                                    local st = getState(hb)
                                    local borderTarget = (st and st.heightClipContainer and st.heightClipActive) and st.heightClipContainer or hb
                                    anchorFrame:SetAllPoints(borderTarget)
                                end
                                anchorFrame:Show()

                                -- BOSS FRAME CLEANUP: Clear any stale borders on parent containers and the StatusBar.
                                -- Previously borders may have been applied to wrong frames (e.g., HealthBarsContainer,
                                -- TargetFrameContentMain, bossFrame.healthbar with wrong dimensions). Clear them all.
                                do
                                    local clearTargets = {
                                        bossFrame.healthbar,
                                        hb,
                                        hb and hb:GetParent(), -- HealthBarsContainer
                                        bossFrame.TargetFrameContent and bossFrame.TargetFrameContent.TargetFrameContentMain,
                                        bossFrame.TargetFrameContent,
                                    }
                                    for _, target in ipairs(clearTargets) do
                                        -- Don't clear the anchor frame itself (it's where we apply new borders)
                                        if target and target ~= anchorFrame then
                                            if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                                                addon.BarBorders.ClearBarFrame(target)
                                            end
                                            if addon.Borders and addon.Borders.HideAll then
                                                addon.Borders.HideAll(target)
                                            end
                                        end
                                    end
                                end

                                -- Apply border to anchor frame (not hb!) so it matches HealthBarTexture bounds
                                if cfg.useCustomBorders then
                                    if styleKey == "none" or styleKey == nil then
                                        if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(anchorFrame) end
                                        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(anchorFrame) end
                                    else
                                        local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
                                        local color
                                        if tintEnabled then
                                            color = tintColor
                                        else
                                            if styleDef then
                                                color = {1, 1, 1, 1}
                                            else
                                                color = {0, 0, 0, 1}
                                            end
                                        end
                                        local handled = false
                                        -- Clear old borders from anchor frame before applying new
                                        if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                                            addon.BarBorders.ClearBarFrame(anchorFrame)
                                        end
                                        if addon.Borders and addon.Borders.HideAll then
                                            addon.Borders.HideAll(anchorFrame)
                                        end
                                        -- Try ApplySquare for Boss health bar borders (simpler, more reliable)
                                        -- BarBorders.ApplyToBarFrame requires a StatusBar, but anchorFrame is a Frame
                                        if addon.Borders and addon.Borders.ApplySquare then
                                            local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
                                            local baseY = 1
                                            local baseX = 1
                                            local expandY = baseY - insetV
                                            local expandX = baseX - insetH
                                            if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                                            if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                                            addon.Borders.ApplySquare(anchorFrame, {
                                                size = thickness,
                                                color = sqColor,
                                                layer = "OVERLAY",
                                                layerSublevel = 3,
                                                expandX = expandX,
                                                expandY = expandY,
                                                skipDimensionCheck = true, -- Anchor frame may be small
                                            })
                                            handled = true
                                        end
                                        if handled then
                                            ensureTextAndBorderOrdering(unit)
                                        end
                                    end
                                else
                                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(anchorFrame) end
                                    if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(anchorFrame) end
                                end
                            end

                            -- Boss frames can get refreshed by Blizzard (HealthUpdate, Update) which resets textures.
                            -- Install a hook to re-assert our styling after Blizzard updates.
                            local bossState = getState(bossFrame)
                            if _G.hooksecurefunc and bossState and not bossState.bossHealthUpdateHooked then
                                local function installBossHealthHook(hookTarget, hookName)
                                    if hookTarget and type(hookTarget[hookName]) == "function" then
                                        bossState.bossHealthUpdateHooked = true
                                        _G.hooksecurefunc(hookTarget, hookName, function()
                                            if isEditModeActive() then return end
                                            local db2 = addon and addon.db and addon.db.profile
                                            if not db2 then return end
                                            local unitFrames2 = rawget(db2, "unitFrames")
                                            local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                                            if not cfgBoss then return end

                                            local texKey = cfgBoss.healthBarTexture or "default"
                                            local colorMode = cfgBoss.healthBarColorMode or "default"
                                            local tint = cfgBoss.healthBarTint

                                            local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                                            local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                                            if not hasCustomTexture and not hasCustomColor then return end

                                            -- Throttle: skip if a reapply is already pending for this frame
                                            local st = getState(bossFrame)
                                            if st and st.bossReapplyPending then return end
                                            if st then st.bossReapplyPending = true end

                                            -- Defer to next frame to let Blizzard finish its updates
                                            if _G.C_Timer and _G.C_Timer.After then
                                                _G.C_Timer.After(0, function()
                                                    local st2 = getState(bossFrame)
                                                    if st2 then st2.bossReapplyPending = nil end
                                                    -- Use direct property (most reliable)
                                                    local hbReapply = bossFrame.healthbar
                                                    if hbReapply then
                                                        local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)
                                                        if resolvedPath and hbReapply.SetStatusBarTexture then
                                                            pcall(hbReapply.SetStatusBarTexture, hbReapply, resolvedPath)
                                                        end
                                                        -- Reapply color
                                                        local tex = hbReapply:GetStatusBarTexture()
                                                        if tex and tex.SetVertexColor then
                                                            local r, g, b, a = 1, 1, 1, 1
                                                            if colorMode == "custom" and type(tint) == "table" then
                                                                r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
                                                            elseif colorMode == "class" and addon.GetClassColorRGB then
                                                                local cr, cg, cb = addon.GetClassColorRGB("player")
                                                                r, g, b = cr or 1, cg or 1, cb or 1
                                                            elseif colorMode == "texture" then
                                                                r, g, b, a = 1, 1, 1, 1
                                                            elseif colorMode == "default" and addon.GetDefaultHealthColorRGB then
                                                                local hr, hg, hb = addon.GetDefaultHealthColorRGB()
                                                                r, g, b = hr or 0, hg or 1, hb or 0
                                                            end
                                                            pcall(tex.SetVertexColor, tex, r, g, b, a)
                                                        end
                                                    end
                                                end)
                                            end
                                        end)
                                        return true
                                    end
                                    return false
                                end
                                -- Try HealthUpdate first (more targeted), fall back to Update
                                if not installBossHealthHook(bossFrame, "HealthUpdate") then
                                    installBossHealthHook(bossFrame, "Update")
                                end
                            end
                        end

                        local pb = resolvePowerBar(bossFrame, unit)
                        if pb then
                            local powerBarHidden = (cfg.powerBarHidden == true)
                            local powerBarHideTextureOnly = (cfg.powerBarHideTextureOnly == true)

                            if pb.GetAlpha and getProp(pb, "origPBAlpha") == nil then
                                local ok, a = pcall(pb.GetAlpha, pb)
                                setProp(pb, "origPBAlpha", ok and (a or 1) or 1)
                            end

                            if powerBarHidden then
                                if pb.SetAlpha then pcall(pb.SetAlpha, pb, 0) end
                                do local bg = getProp(pb, "ScooterModBG"); if bg and bg.SetAlpha then pcall(bg.SetAlpha, bg, 0) end end
                                if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                                if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(pb) end
                                if Util and Util.SetPowerBarTextureOnlyHidden then Util.SetPowerBarTextureOnlyHidden(pb, false) end
                            elseif powerBarHideTextureOnly then
                                local origAlpha = getProp(pb, "origPBAlpha")
                                if origAlpha and pb.SetAlpha then pcall(pb.SetAlpha, pb, origAlpha) end
                                if Util and Util.SetPowerBarTextureOnlyHidden then Util.SetPowerBarTextureOnlyHidden(pb, true) end
                                if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                                if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(pb) end
                            else
                                local origAlpha = getProp(pb, "origPBAlpha")
                                if origAlpha and pb.SetAlpha then pcall(pb.SetAlpha, pb, origAlpha) end
                                if Util and Util.SetPowerBarTextureOnlyHidden then Util.SetPowerBarTextureOnlyHidden(pb, false) end
                            end

                            local colorModePB = cfg.powerBarColorMode or "default"
                            local texKeyPB = cfg.powerBarTexture or "default"
                            applyToBar(pb, texKeyPB, colorModePB, cfg.powerBarTint, "player", "power", unitId)

                            do
                                local function hasBackgroundCustomization()
                                    local texKey = cfg.powerBarBackgroundTexture
                                    if type(texKey) == "string" and texKey ~= "" and texKey ~= "default" then
                                        return true
                                    end
                                    local mode = cfg.powerBarBackgroundColorMode
                                    if type(mode) == "string" and mode ~= "" and mode ~= "default" then
                                        return true
                                    end
                                    local op = cfg.powerBarBackgroundOpacity
                                    local opNum = tonumber(op)
                                    if op ~= nil and opNum ~= nil and opNum ~= 50 then
                                        return true
                                    end
                                    if mode == "custom" and type(cfg.powerBarBackgroundTint) == "table" then
                                        return true
                                    end
                                    return false
                                end
                                if hasBackgroundCustomization() then
                                    local bgTexKeyPB = cfg.powerBarBackgroundTexture or "default"
                                    local bgColorModePB = cfg.powerBarBackgroundColorMode or "default"
                                    local bgOpacityPB = cfg.powerBarBackgroundOpacity or 50
                                    applyBackgroundToBar(pb, bgTexKeyPB, bgColorModePB, cfg.powerBarBackgroundTint, bgOpacityPB, unit, "power")
                                end
                            end

                            if powerBarHideTextureOnly and not powerBarHidden then
                                if Util and Util.SetPowerBarTextureOnlyHidden then Util.SetPowerBarTextureOnlyHidden(pb, true) end
                            end

                            ensureMaskOnBarTexture(pb, resolveBossPowerMask(bossFrame))

                            -- Rectangular overlay to fill bottom-right chip when using custom borders
                            ensureBossRectOverlay(bossFrame, pb, cfg, "power")

                            -- Power Bar custom border (mirrors Health Bar border settings; supports power-specific overrides)
                            -- BOSS FRAME FIX: Use the same anchor frame pattern as Health Bar for consistency.
                            -- Unlike HealthBar, ManaBar is NOT inside a container - it's directly under TargetFrameContentMain.
                            -- The ManaBar StatusBar should have correct bounds (it's a sibling of HealthBarsContainer).
                            do
                                local styleKey = cfg.powerBarBorderStyle or cfg.healthBarBorderStyle
                                local tintEnabled
                                if cfg.powerBarBorderTintEnable ~= nil then
                                    tintEnabled = not not cfg.powerBarBorderTintEnable
                                else
                                    tintEnabled = not not cfg.healthBarBorderTintEnable
                                end
                                local baseTint = type(cfg.powerBarBorderTintColor) == "table" and cfg.powerBarBorderTintColor or cfg.healthBarBorderTintColor
                                local tintColor = type(baseTint) == "table" and {
                                    baseTint[1] or 1,
                                    baseTint[2] or 1,
                                    baseTint[3] or 1,
                                    baseTint[4] or 1,
                                } or {1, 1, 1, 1}
                                local thickness = tonumber(cfg.powerBarBorderThickness) or tonumber(cfg.healthBarBorderThickness) or 1
                                if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
                                local insetH = (cfg.powerBarBorderInsetH ~= nil) and tonumber(cfg.powerBarBorderInsetH) or (cfg.powerBarBorderInset ~= nil) and tonumber(cfg.powerBarBorderInset) or tonumber(cfg.healthBarBorderInsetH) or tonumber(cfg.healthBarBorderInset) or 0
                                local insetV = (cfg.powerBarBorderInsetV ~= nil) and tonumber(cfg.powerBarBorderInsetV) or (cfg.powerBarBorderInset ~= nil) and tonumber(cfg.powerBarBorderInset) or tonumber(cfg.healthBarBorderInsetV) or tonumber(cfg.healthBarBorderInset) or 0

                                -- Resolve ManaBar for correct bounds
                                local mbResolved = resolveBossManaBar(bossFrame)

                                -- Create or retrieve the anchor frame for border application
                                -- For consistency with Health Bar, use the same pattern even though ManaBar
                                -- may already have correct bounds (it's not inside an oversized container)
                                local anchorFrame = getProp(pb, "bossPowerBorderAnchor")
                                if not anchorFrame then
                                    anchorFrame = CreateFrame("Frame", nil, pb)
                                    anchorFrame:SetFrameLevel((pb:GetFrameLevel() or 0) + 1)
                                    setProp(pb, "bossPowerBorderAnchor", anchorFrame)
                                end

                                -- Anchor to resolved ManaBar bounds if available, else fall back to pb
                                anchorFrame:ClearAllPoints()
                                if mbResolved then
                                    anchorFrame:SetPoint("TOPLEFT", mbResolved, "TOPLEFT", 0, 0)
                                    anchorFrame:SetPoint("BOTTOMRIGHT", mbResolved, "BOTTOMRIGHT", 0, 0)
                                else
                                    anchorFrame:SetAllPoints(pb)
                                end
                                anchorFrame:Show()

                                -- BOSS FRAME CLEANUP: Clear any stale borders on the StatusBar
                                do
                                    local clearTargets = {
                                        bossFrame.manabar,
                                        pb,
                                        pb and pb:GetParent(),
                                    }
                                    for _, target in ipairs(clearTargets) do
                                        -- Don't clear the anchor frame itself (it's where we apply new borders)
                                        if target and target ~= anchorFrame then
                                            if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                                                addon.BarBorders.ClearBarFrame(target)
                                            end
                                            if addon.Borders and addon.Borders.HideAll then
                                                addon.Borders.HideAll(target)
                                            end
                                        end
                                    end
                                end

                                -- Apply border to anchor frame
                                -- Skip border application when power bar is fully hidden.
                                if cfg.useCustomBorders and not powerBarHidden then
                                    if styleKey == "none" or styleKey == nil then
                                        if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(anchorFrame) end
                                        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(anchorFrame) end
                                    else
                                        local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
                                        local color
                                        if tintEnabled then
                                            color = tintColor
                                        else
                                            if styleDef then
                                                color = {1, 1, 1, 1}
                                            else
                                                color = {0, 0, 0, 1}
                                            end
                                        end
                                        -- Clear old borders from anchor frame before applying new
                                        if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                                            addon.BarBorders.ClearBarFrame(anchorFrame)
                                        end
                                        if addon.Borders and addon.Borders.HideAll then
                                            addon.Borders.HideAll(anchorFrame)
                                        end
                                        -- Use ApplySquare for Boss power bar borders (same pattern as health bar)
                                        if addon.Borders and addon.Borders.ApplySquare then
                                            local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
                                            local baseY = 1
                                            local baseX = 1
                                            local expandY = baseY - insetV
                                            local expandX = baseX - insetH
                                            if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                                            if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                                            addon.Borders.ApplySquare(anchorFrame, {
                                                size = thickness,
                                                color = sqColor,
                                                layer = "OVERLAY",
                                                layerSublevel = 3,
                                                expandX = expandX,
                                                expandY = expandY,
                                                skipDimensionCheck = true, -- Anchor frame may be small
                                            })
                                        end
                                        ensureTextAndBorderOrdering(unit)
                                    end
                                else
                                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(anchorFrame) end
                                    if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(anchorFrame) end
                                end
                            end

                            -- Boss power bars can get refreshed by Blizzard which resets textures.
                            -- Install a hook to re-assert our styling after Blizzard updates.
                            local bossState = getState(bossFrame)
                            if _G.hooksecurefunc and bossState and not bossState.bossPowerUpdateHooked then
                                bossState.bossPowerUpdateHooked = true
                                -- Hook the power bar's SetValue which is called on every power change
                                if pb.SetValue and type(pb.SetValue) == "function" then
                                    _G.hooksecurefunc(pb, "SetValue", function()
                                        if isEditModeActive() then return end
                                        local db2 = addon and addon.db and addon.db.profile
                                        if not db2 then return end
                                        local unitFrames2 = rawget(db2, "unitFrames")
                                        local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                                        if not cfgBoss then return end

                                        local texKey = cfgBoss.powerBarTexture or "default"
                                        local colorMode = cfgBoss.powerBarColorMode or "default"
                                        local tint = cfgBoss.powerBarTint

                                        local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                                        local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                                        if not hasCustomTexture and not hasCustomColor then return end

                                        -- Throttle: skip if a reapply is already pending
                                        local st = getState(bossFrame)
                                        if st and st.bossPowerReapplyPending then return end
                                        if st then st.bossPowerReapplyPending = true end

                                        if _G.C_Timer and _G.C_Timer.After then
                                            _G.C_Timer.After(0, function()
                                                local st2 = getState(bossFrame)
                                                if st2 then st2.bossPowerReapplyPending = nil end
                                                local pbReapply = bossFrame.manabar
                                                if pbReapply then
                                                    local resolvedPath = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(texKey)
                                                    if resolvedPath and pbReapply.SetStatusBarTexture then
                                                        pcall(pbReapply.SetStatusBarTexture, pbReapply, resolvedPath)
                                                    end
                                                    local tex = pbReapply:GetStatusBarTexture()
                                                    if tex and tex.SetVertexColor then
                                                        local r, g, b, a = 1, 1, 1, 1
                                                        if colorMode == "custom" and type(tint) == "table" then
                                                            r, g, b, a = tint[1] or 1, tint[2] or 1, tint[3] or 1, tint[4] or 1
                                                        elseif colorMode == "class" and addon.GetClassColorRGB then
                                                            local cr, cg, cb = addon.GetClassColorRGB("player")
                                                            r, g, b = cr or 1, cg or 1, cb or 1
                                                        elseif colorMode == "texture" then
                                                            r, g, b, a = 1, 1, 1, 1
                                                        end
                                                        pcall(tex.SetVertexColor, tex, r, g, b, a)
                                                    end
                                                end
                                            end)
                                        end
                                    end)
                                end
                            end
                        end
                end
            end

            -- Boss frame art: Handle all 5 Boss frames (Boss1TargetFrame through Boss5TargetFrame)
            for i = 1, 5 do
                local bossFrame = _G["Boss" .. i .. "TargetFrame"]
                if bossFrame and bossFrame.TargetFrameContainer then
                    local bossFT = bossFrame.TargetFrameContainer.FrameTexture
                    if bossFT then
                        local function computeBossAlpha()
                            local db2 = addon and addon.db and addon.db.profile
                            local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                            local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                            local hide = cfgBoss and (cfgBoss.useCustomBorders or cfgBoss.healthBarHideBorder)
                            return hide and 0 or 1
                        end
                        applyAlpha(bossFT, computeBossAlpha())
                        hookAlphaEnforcer(bossFT, computeBossAlpha)
                    end
                    -- Also hide the Flash (aggro/threat glow) if present on Boss frames
                    local bossFlash = bossFrame.TargetFrameContainer.Flash
                    if bossFlash then
                        local function computeBossFlashAlpha()
                            local db2 = addon and addon.db and addon.db.profile
                            local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                            local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                            return (cfgBoss and cfgBoss.useCustomBorders) and 0 or 1
                        end
                        applyAlpha(bossFlash, computeBossFlashAlpha())
                        hookAlphaEnforcer(bossFlash, computeBossFlashAlpha)
                    end
                end
            end

            return
        end

        local hb = resolveHealthBar(frame, unit)
        if hb then
            local colorModeHB = cfg.healthBarColorMode or "default"
            local texKeyHB = cfg.healthBarTexture or "default"
            local unitId = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or (unit == "Pet" and "pet") or (unit == "TargetOfTarget" and "targettarget") or (unit == "FocusTarget" and "focustarget") or "player"
			-- Avoid applying styling to Target/Focus/ToT/FoT before they exist; Blizzard will reset sizes on first Update
			if (unit == "Target" or unit == "Focus" or unit == "TargetOfTarget" or unit == "FocusTarget") and _G.UnitExists and not _G.UnitExists(unitId) then
				return
			end
			local healthBarHideTextureOnly = (cfg.healthBarHideTextureOnly == true)
			if healthBarHideTextureOnly then
				if Util and Util.SetHealthBarTextureOnlyHidden then
					Util.SetHealthBarTextureOnlyHidden(hb, true)
				end
				-- Clear any custom borders so only text remains
				if addon.BarBorders and addon.BarBorders.ClearBarFrame then
					addon.BarBorders.ClearBarFrame(hb)
				end
				if addon.Borders and addon.Borders.HideAll then
					addon.Borders.HideAll(hb)
				end
			else
				if Util and Util.SetHealthBarTextureOnlyHidden then
					Util.SetHealthBarTextureOnlyHidden(hb, false)
				end
			end
            applyToBar(hb, texKeyHB, colorModeHB, cfg.healthBarTint, "player", "health", unitId)
            
            -- Apply background texture and color for Health Bar
            do
                -- IMPORTANT: Default/clean profiles should not change the look of Blizzard's bars.
                -- Only apply our background overlay if the user actually customized background settings.
                local function hasBackgroundCustomization()
                    local texKey = cfg.healthBarBackgroundTexture
                    if type(texKey) == "string" and texKey ~= "" and texKey ~= "default" then
                        return true
                    end
                    local mode = cfg.healthBarBackgroundColorMode
                    if type(mode) == "string" and mode ~= "" and mode ~= "default" then
                        return true
                    end
                    local op = cfg.healthBarBackgroundOpacity
                    local opNum = tonumber(op)
                    if op ~= nil and opNum ~= nil and opNum ~= 50 then
                        return true
                    end
                    if mode == "custom" and type(cfg.healthBarBackgroundTint) == "table" then
                        return true
                    end
                    return false
                end
                if hasBackgroundCustomization() then
                    local bgTexKeyHB = cfg.healthBarBackgroundTexture or "default"
                    local bgColorModeHB = cfg.healthBarBackgroundColorMode or "default"
                    local bgOpacityHB = cfg.healthBarBackgroundOpacity or 50
                    applyBackgroundToBar(hb, bgTexKeyHB, bgColorModeHB, cfg.healthBarBackgroundTint, bgOpacityHB, unit, "health")
                end
            end

            -- Re-apply texture-only hide after styling (ensures newly created ScooterModBG is also hidden)
            if healthBarHideTextureOnly then
                if Util and Util.SetHealthBarTextureOnlyHidden then
                    Util.SetHealthBarTextureOnlyHidden(hb, true)
                end
            end

			-- When Target/Focus portraits are hidden, draw a rectangular overlay that fills the
			-- right-side "chip" area using the same texture/tint as the health bar.
			ensureRectHealthOverlay(unit, hb, cfg)
            -- If restoring default texture and we lack a captured original, restore to the known stock atlas for this unit
            local isDefaultHB = (texKeyHB == "default" or not addon.Media.ResolveBarTexturePath(texKeyHB))
            if isDefaultHB and not getProp(hb, "ufOrigAtlas") and not getProp(hb, "ufOrigPath") then
				local stockAtlas
				if unit == "Player" then
					stockAtlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health"
				elseif unit == "Target" then
					stockAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health"
				elseif unit == "Focus" then
					stockAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health" -- Focus reuses Target visuals
				elseif unit == "Pet" then
					stockAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health" -- Pet frame shares party atlas
				elseif unit == "TargetOfTarget" then
					stockAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health" -- ToT shares party atlas
				elseif unit == "FocusTarget" then
					stockAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health" -- FoT shares party atlas
				end
                if stockAtlas then
                    local hbTex = hb.GetStatusBarTexture and hb:GetStatusBarTexture()
                    if hbTex and hbTex.SetAtlas then pcall(hbTex.SetAtlas, hbTex, stockAtlas, true) end
					-- Best-effort: ensure the mask uses the matching atlas
					local mask = resolveHealthMask(unit)
					if mask and mask.SetAtlas then
						local maskAtlas
						if unit == "Player" then
							maskAtlas = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Mask"
						elseif unit == "Target" or unit == "Focus" then
							maskAtlas = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health-Mask"
						elseif unit == "Pet" then
							maskAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Mask"
						elseif unit == "TargetOfTarget" then
							maskAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Mask" -- ToT shares party mask
						elseif unit == "FocusTarget" then
							maskAtlas = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Mask" -- FoT shares party mask
						end
						if maskAtlas then pcall(mask.SetAtlas, mask, maskAtlas) end
					end
                    -- Re-apply value-based color after SetAtlas (which resets vertex color to white)
                    if (colorModeHB == "value" or colorModeHB == "valueDark") and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                        addon.BarsTextures.applyValueBasedColor(hb, unitId, nil, colorModeHB == "valueDark")
                    end
				end
			end
			ensureMaskOnBarTexture(hb, resolveHealthMask(unit))
            
            -- Apply reverse fill for Target/Focus if configured
            if (unit == "Target" or unit == "Focus") and hb and hb.SetReverseFill then
                local shouldReverse = not not cfg.healthBarReverseFill
                pcall(hb.SetReverseFill, hb, shouldReverse)
            end
            
            -- Hide/Show Over Absorb Glow (Player/Target/Focus)
            if (unit == "Player" or unit == "Target" or unit == "Focus") and hb and Util and Util.SetOverAbsorbGlowHidden then
                Util.SetOverAbsorbGlowHidden(hb, cfg.healthBarHideOverAbsorbGlow == true)
            end

            -- Hide/Show Heal Prediction (Player/Target/Focus)
            if (unit == "Player" or unit == "Target" or unit == "Focus") and hb and Util and Util.SetHealPredictionHidden then
                Util.SetHealPredictionHidden(hb, cfg.healthBarHideHealPrediction == true)
            end

            -- Hide/Show Health Loss Animation (Player only)
            -- Frame: PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.PlayerFrameHealthBarAnimatedLoss
            if unit == "Player" and hb and Util and Util.SetHealthLossAnimationHidden then
                Util.SetHealthLossAnimationHidden(hb, cfg.healthBarHideHealthLossAnimation == true)
            end

            -- Health Bar custom border (Health Bar only)
            -- PetFrame is a managed/protected frame. Even innocuous getters (GetWidth, GetFrameLevel)
            -- on PetFrame's health bar can trigger Blizzard internal updates that error on "secret values".
            -- Skip ALL border operations for Pet to guarantee preset/profile application doesn't provoke that path.
            if unit ~= "Pet" and unit ~= "TargetOfTarget" and unit ~= "FocusTarget" and not healthBarHideTextureOnly then
            do
				local styleKey = cfg.healthBarBorderStyle
				local tintEnabled = not not cfg.healthBarBorderTintEnable
				local tintColor = type(cfg.healthBarBorderTintColor) == "table" and {
					cfg.healthBarBorderTintColor[1] or 1,
					cfg.healthBarBorderTintColor[2] or 1,
					cfg.healthBarBorderTintColor[3] or 1,
					cfg.healthBarBorderTintColor[4] or 1,
				} or {1, 1, 1, 1}
                local thickness = tonumber(cfg.healthBarBorderThickness) or 1
				if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
                local insetH = tonumber(cfg.healthBarBorderInsetH) or tonumber(cfg.healthBarBorderInset) or 0
                local insetV = tonumber(cfg.healthBarBorderInsetV) or tonumber(cfg.healthBarBorderInset) or 0
				-- Only draw custom border when Use Custom Borders is enabled
				if hb then
					if cfg.useCustomBorders then
						-- Handle style = "none" to explicitly clear any custom border
						if styleKey == "none" or styleKey == nil then
							if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(hb) end
							if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(hb) end
						else
							-- Match Tracked Bars: when tint is disabled use white for textured styles,
							-- and black only for the pixel fallback case.
							local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
							local color
							if tintEnabled then
								color = tintColor
							else
								if styleDef then
									color = {1, 1, 1, 1}
								else
									color = {0, 0, 0, 1}
								end
							end
                            -- Determine border anchor target: use clipping container if height reduction active
                            local st = getState(hb)
                            local borderAnchorTarget = (st and st.heightClipContainer and st.heightClipActive) and st.heightClipContainer or nil
                            local handled = false
                            if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
								-- Clear any prior holder/state to avoid stale tinting when toggling
								if addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(hb) end
                                handled = addon.BarBorders.ApplyToBarFrame(hb, styleKey, {
                                    color = color,
                                    thickness = thickness,
                                    levelOffset = 1, -- just above bar fill; text will be raised above holder
                                    containerParent = (hb and hb:GetParent()) or nil,
                                    insetH = insetH,
                                    insetV = insetV,
                                    anchorTarget = borderAnchorTarget, -- anchor to clipping container if active
                                })
							end
                            if not handled then
                                -- Fallback: pixel (square) border drawn with our lightweight helper
								if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(hb) end
                                if addon.Borders and addon.Borders.ApplySquare then
									local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
                                    -- Always extend border by 1 pixel to cover any texture bleeding above the frame
                                    local baseY = 1
                                    local baseX = 1
                                    local expandY = baseY - insetV
                                    local expandX = baseX - insetH
                                    if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                                    if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                                    -- Pet is already excluded by the outer guard
                                    -- Apply to clipping container if height reduction active, else to health bar
                                    local squareBorderTarget = borderAnchorTarget or hb
                                    addon.Borders.ApplySquare(squareBorderTarget, {
                                        size = thickness,
                                        color = sqColor,
                                        layer = "OVERLAY",
                                        layerSublevel = 3,
                                        expandX = expandX,
                                        expandY = expandY,
                                    })
                                end
							end
                            -- Deterministically place border below text and ensure text wins
                            ensureTextAndBorderOrdering(unit)
                            -- Light hook: keep ordering stable on bar resize
                            if hb and not getProp(hb, "ufZOrderHooked") and hb.HookScript then
                                hb:HookScript("OnSizeChanged", function()
                                    if isEditModeActive() then return end
                                    if InCombatLockdown and InCombatLockdown() then
                                        return
                                    end
                                    ensureTextAndBorderOrdering(unit)
                                end)
                                setProp(hb, "ufZOrderHooked", true)
                            end
						end
					else
						-- Custom borders disabled -> ensure cleared
						if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(hb) end
						if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(hb) end
					end
				end
            end
            end -- Pet guard

            -- Lightweight persistence hooks for Player Health Bar:
            -- Texture: keep custom texture applied if Blizzard swaps StatusBarTexture.
            -- Color: keep Foreground Color applied if Blizzard calls SetStatusBarColor.
            if unit == "Player" and _G.hooksecurefunc then
                -- Texture hook: reapply custom texture when Blizzard resets it
                if not getProp(hb, "healthTextureHooked") then
                    setProp(hb, "healthTextureHooked", true)
                    _G.hooksecurefunc(hb, "SetStatusBarTexture", function(self, ...)
                        if isEditModeActive() then return end
                        -- Ignore ScooterMod's own writes to avoid recursion.
                        if getProp(self, "ufInternalTextureWrite") then
                            return
                        end
                        -- Skip during combat to avoid taint on protected StatusBar.
                        if InCombatLockdown and InCombatLockdown() then return end
                        local db = addon and addon.db and addon.db.profile
                        if not db then return end
                        local unitFrames = rawget(db, "unitFrames")
                        local cfgP = unitFrames and rawget(unitFrames, "Player") or nil
                        if not cfgP then return end
                        local texKey = cfgP.healthBarTexture or "default"
                        local colorMode = cfgP.healthBarColorMode or "default"
                        local tint = cfgP.healthBarTint
                        -- Re-apply if custom texture OR "value"/"valueDark" color mode (Blizzard's new texture needs coloring)
                        local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                        local needsValueColor = (colorMode == "value" or colorMode == "valueDark")
                        if not hasCustomTexture and not needsValueColor then
                            return
                        end
                        -- For value mode with default texture, just re-apply color to the new texture
                        -- Use small delay to ensure color is applied AFTER Blizzard's code completes
                        if needsValueColor and not hasCustomTexture then
                            local useDark = (colorMode == "valueDark")
                            C_Timer.After(0, function()
                                if addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                                    addon.BarsTextures.applyValueBasedColor(self, "player", nil, useDark)
                                end
                            end)
                        else
                            applyToBar(self, texKey, colorMode, tint, "player", "health", "player")
                        end
                    end)
                end
                -- Color hook: reapply custom color when Blizzard resets it
                if not getProp(hb, "healthColorHooked") then
                    setProp(hb, "healthColorHooked", true)
                    _G.hooksecurefunc(hb, "SetStatusBarColor", function(self, ...)
                        if isEditModeActive() then return end
                        -- Skip if we're the ones calling SetStatusBarColor (from applyValueBasedColor)
                        if getProp(self, "applyingValueBasedColor") then return end
                        -- CRITICAL: Do NOT call applyToBar during combat - it calls SetStatusBarTexture/SetVertexColor
                        -- on the protected StatusBar, which taints it and causes "blocked from an action" errors.
                        if InCombatLockdown and InCombatLockdown() then return end
                        local db = addon and addon.db and addon.db.profile
                        if not db then return end
                        local unitFrames = rawget(db, "unitFrames")
                        local cfgP = unitFrames and rawget(unitFrames, "Player") or nil
                        if not cfgP then return end
                        local texKey = cfgP.healthBarTexture or "default"
                        local colorMode = cfgP.healthBarColorMode or "default"
                        local tint = cfgP.healthBarTint
                        local unitIdP = "player"
                        -- Only do work when the user has customized either texture or color;
                        -- default settings can safely follow Blizzard's behavior.
                        local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                        local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "value") or (colorMode == "valueDark")
                        if not hasCustomTexture and not hasCustomColor then
                            return
                        end
                        applyToBar(self, texKey, colorMode, tint, "player", "health", unitIdP)
                    end)
                end
            end

            -- Lightweight persistence hooks for Target-of-Target Health Bar:
            -- Blizzard can reset the ToT StatusBar's fill texture during rapid updates (often in combat).
            -- We re-assert the configured texture/color by writing to the underlying Texture region
            -- (avoids calling SetStatusBarTexture again inside a secure callstack).
            if unit == "TargetOfTarget" and _G.hooksecurefunc then
                if not getProp(hb, "toTHealthTextureHooked") then
                    setProp(hb, "toTHealthTextureHooked", true)
                    _G.hooksecurefunc(hb, "SetStatusBarTexture", function(self, ...)
                        if isEditModeActive() then return end
                        -- Ignore ScooterMod's own writes to avoid feedback loops.
                        if getProp(self, "ufInternalTextureWrite") then
                            return
                        end

                        local db = addon and addon.db and addon.db.profile
                        if not db then return end
                        local unitFrames = rawget(db, "unitFrames")
                        local cfgT = unitFrames and rawget(unitFrames, "TargetOfTarget") or nil
                        if not cfgT then return end

                        local texKey = cfgT.healthBarTexture or "default"
                        local colorMode = cfgT.healthBarColorMode or "default"
                        local tint = cfgT.healthBarTint

                        local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                        local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                        if not hasCustomTexture and not hasCustomColor then
                            return
                        end

                        -- Avoid any writes during combat; defer until after combat.
                        if InCombatLockdown and InCombatLockdown() then
                            queueUnitFrameTextureReapply("TargetOfTarget")
                            return
                        end

                        -- Throttle: coalesce rapid refreshes into a single 0s re-apply.
                        if getProp(self, "toTReapplyPending") then
                            return
                        end
                        setProp(self, "toTReapplyPending", true)
                        if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                            _G.C_Timer.After(0, function()
                                setProp(self, "toTReapplyPending", nil)
                                addon.ApplyUnitFrameBarTexturesFor("TargetOfTarget")
                            end)
                        elseif addon.ApplyUnitFrameBarTexturesFor then
                            setProp(self, "toTReapplyPending", nil)
                            addon.ApplyUnitFrameBarTexturesFor("TargetOfTarget")
                        end
                    end)
                end

                if not getProp(hb, "toTHealthColorHooked") then
                    setProp(hb, "toTHealthColorHooked", true)
                    _G.hooksecurefunc(hb, "SetStatusBarColor", function(self, ...)
                        if isEditModeActive() then return end
                        local db = addon and addon.db and addon.db.profile
                        if not db then return end
                        local unitFrames = rawget(db, "unitFrames")
                        local cfgT = unitFrames and rawget(unitFrames, "TargetOfTarget") or nil
                        if not cfgT then return end

                        local texKey = cfgT.healthBarTexture or "default"
                        local colorMode = cfgT.healthBarColorMode or "default"
                        local tint = cfgT.healthBarTint

                        local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                        local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                        if not hasCustomTexture and not hasCustomColor then
                            return
                        end

                        if InCombatLockdown and InCombatLockdown() then
                            queueUnitFrameTextureReapply("TargetOfTarget")
                            return
                        end

                        if getProp(self, "toTReapplyPending") then
                            return
                        end
                        setProp(self, "toTReapplyPending", true)
                        if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                            _G.C_Timer.After(0, function()
                                setProp(self, "toTReapplyPending", nil)
                                addon.ApplyUnitFrameBarTexturesFor("TargetOfTarget")
                            end)
                        elseif addon.ApplyUnitFrameBarTexturesFor then
                            setProp(self, "toTReapplyPending", nil)
                            addon.ApplyUnitFrameBarTexturesFor("TargetOfTarget")
                        end
                    end)
                end
            end

            -- Lightweight persistence hooks for Focus-Target Health Bar:
            -- Blizzard can reset the FoT StatusBar's fill texture during rapid updates (often in combat).
            -- We re-assert the configured texture/color by writing to the underlying Texture region
            -- (avoids calling SetStatusBarTexture again inside a secure callstack).
            if unit == "FocusTarget" and _G.hooksecurefunc then
                if not getProp(hb, "foTHealthTextureHooked") then
                    setProp(hb, "foTHealthTextureHooked", true)
                    _G.hooksecurefunc(hb, "SetStatusBarTexture", function(self, ...)
                        if isEditModeActive() then return end
                        -- Ignore ScooterMod's own writes to avoid feedback loops.
                        if getProp(self, "ufInternalTextureWrite") then
                            return
                        end

                        local db = addon and addon.db and addon.db.profile
                        if not db then return end
                        local unitFrames = rawget(db, "unitFrames")
                        local cfgF = unitFrames and rawget(unitFrames, "FocusTarget") or nil
                        if not cfgF then return end

                        local texKey = cfgF.healthBarTexture or "default"
                        local colorMode = cfgF.healthBarColorMode or "default"
                        local tint = cfgF.healthBarTint

                        local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                        local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                        if not hasCustomTexture and not hasCustomColor then
                            return
                        end

                        -- Avoid any writes during combat; defer until after combat.
                        if InCombatLockdown and InCombatLockdown() then
                            queueUnitFrameTextureReapply("FocusTarget")
                            return
                        end

                        -- Throttle: coalesce rapid refreshes into a single 0s re-apply.
                        if getProp(self, "foTReapplyPending") then
                            return
                        end
                        setProp(self, "foTReapplyPending", true)
                        if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                            _G.C_Timer.After(0, function()
                                setProp(self, "foTReapplyPending", nil)
                                addon.ApplyUnitFrameBarTexturesFor("FocusTarget")
                            end)
                        elseif addon.ApplyUnitFrameBarTexturesFor then
                            setProp(self, "foTReapplyPending", nil)
                            addon.ApplyUnitFrameBarTexturesFor("FocusTarget")
                        end
                    end)
                end

                if not getProp(hb, "foTHealthColorHooked") then
                    setProp(hb, "foTHealthColorHooked", true)
                    _G.hooksecurefunc(hb, "SetStatusBarColor", function(self, ...)
                        if isEditModeActive() then return end
                        local db = addon and addon.db and addon.db.profile
                        if not db then return end
                        local unitFrames = rawget(db, "unitFrames")
                        local cfgF = unitFrames and rawget(unitFrames, "FocusTarget") or nil
                        if not cfgF then return end

                        local texKey = cfgF.healthBarTexture or "default"
                        local colorMode = cfgF.healthBarColorMode or "default"
                        local tint = cfgF.healthBarTint

                        local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                        local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class") or (colorMode == "texture")
                        if not hasCustomTexture and not hasCustomColor then
                            return
                        end

                        if InCombatLockdown and InCombatLockdown() then
                            queueUnitFrameTextureReapply("FocusTarget")
                            return
                        end

                        if getProp(self, "foTReapplyPending") then
                            return
                        end
                        setProp(self, "foTReapplyPending", true)
                        if _G.C_Timer and _G.C_Timer.After and addon.ApplyUnitFrameBarTexturesFor then
                            _G.C_Timer.After(0, function()
                                setProp(self, "foTReapplyPending", nil)
                                addon.ApplyUnitFrameBarTexturesFor("FocusTarget")
                            end)
                        elseif addon.ApplyUnitFrameBarTexturesFor then
                            setProp(self, "foTReapplyPending", nil)
                            addon.ApplyUnitFrameBarTexturesFor("FocusTarget")
                        end
                    end)
                end
            end
		end

        local pb = resolvePowerBar(frame, unit)
        if pb then
            -- Cache combat state once for this styling pass. We avoid all geometry
            -- changes (width/height/anchors/offsets) while in combat to prevent
            -- taint on protected unit frames (see taint.log: TargetFrameToT:Show()).
            local inCombat = InCombatLockdown and InCombatLockdown()
			local powerBarHidden = (cfg.powerBarHidden == true)
			local powerBarHideTextureOnly = (cfg.powerBarHideTextureOnly == true)

			-- Capture original alpha once so we can restore when the bar is un-hidden.
			if pb.GetAlpha and getProp(pb, "origPBAlpha") == nil then
				local ok, a = pcall(pb.GetAlpha, pb)
				setProp(pb, "origPBAlpha", ok and (a or 1) or 1)
			end

			-- When the user chooses to hide the Power Bar:
			-- - Fade the StatusBar frame to alpha 0 so the fill/background vanish.
			-- - Hide any ScooterMod-drawn borders/backgrounds associated with this bar.
			if powerBarHidden then
				if pb.SetAlpha then
					pcall(pb.SetAlpha, pb, 0)
				end
				do local bg = getProp(pb, "ScooterModBG"); if bg and bg.SetAlpha then pcall(bg.SetAlpha, bg, 0) end end
				if addon.BarBorders and addon.BarBorders.ClearBarFrame then
					addon.BarBorders.ClearBarFrame(pb)
				end
				if addon.Borders and addon.Borders.HideAll then
					addon.Borders.HideAll(pb)
				end
				-- Ensure texture-only mode is disabled when full bar is hidden
				if Util and Util.SetPowerBarTextureOnlyHidden then
					Util.SetPowerBarTextureOnlyHidden(pb, false)
				end
				-- Also hide the power overlay if present
				local pbSt = getState(pb)
				if pbSt and pbSt.powerFill then pbSt.powerFill:Hide() end
			elseif powerBarHideTextureOnly then
				-- Number-only display: Hide the bar texture/fill while keeping text visible.
				-- Use the utility function which installs persistent hooks to survive combat.
				-- Restore bar frame alpha first (in case user toggled from full-hide to texture-only).
				local origAlpha = getProp(pb, "origPBAlpha")
				if origAlpha and pb.SetAlpha then
					pcall(pb.SetAlpha, pb, origAlpha)
				end

				-- Use persistent utility to hide textures (installs hooks that survive combat)
				if Util and Util.SetPowerBarTextureOnlyHidden then
					Util.SetPowerBarTextureOnlyHidden(pb, true)
				end

				-- Clear any custom borders so only text remains
				if addon.BarBorders and addon.BarBorders.ClearBarFrame then
					addon.BarBorders.ClearBarFrame(pb)
				end
				if addon.Borders and addon.Borders.HideAll then
					addon.Borders.HideAll(pb)
				end
				-- Also hide the power overlay if present
				local pbSt = getState(pb)
				if pbSt and pbSt.powerFill then pbSt.powerFill:Hide() end
			else
				-- Restore alpha when coming back from a hidden state so the bar is visible again.
				local origAlpha = getProp(pb, "origPBAlpha")
				if origAlpha and pb.SetAlpha then
					pcall(pb.SetAlpha, pb, origAlpha)
				end
				-- Disable texture-only hiding (restores texture visibility)
				if Util and Util.SetPowerBarTextureOnlyHidden then
					Util.SetPowerBarTextureOnlyHidden(pb, false)
				end
			end
            local colorModePB = cfg.powerBarColorMode or "default"
            local texKeyPB = cfg.powerBarTexture or "default"
            local unitId = (unit == "Player" and "player") or (unit == "Target" and "target") or (unit == "Focus" and "focus") or (unit == "Pet" and "pet") or (unit == "TargetOfTarget" and "targettarget") or (unit == "FocusTarget" and "focustarget") or "player"

            -- Use the combat-safe power overlay when non-default settings are configured.
            -- The overlay is addon-owned and immune to Blizzard's combat texture resets.
            ensureRectPowerOverlay(unit, pb, cfg)

            local pbSt = getState(pb)
            if not (pbSt and pbSt.powerOverlayActive) then
                -- Overlay not active (default+default): use legacy passthrough
                applyToBar(pb, texKeyPB, colorModePB, cfg.powerBarTint, "player", "power", unitId)
            end

            -- Apply background texture and color for Power Bar
            do
                -- IMPORTANT: Default/clean profiles should not change the look of Blizzard's bars.
                -- Only apply our background overlay if the user actually customized background settings.
                local function hasBackgroundCustomization()
                    local texKey = cfg.powerBarBackgroundTexture
                    if type(texKey) == "string" and texKey ~= "" and texKey ~= "default" then
                        return true
                    end
                    local mode = cfg.powerBarBackgroundColorMode
                    if type(mode) == "string" and mode ~= "" and mode ~= "default" then
                        return true
                    end
                    local op = cfg.powerBarBackgroundOpacity
                    local opNum = tonumber(op)
                    if op ~= nil and opNum ~= nil and opNum ~= 50 then
                        return true
                    end
                    if mode == "custom" and type(cfg.powerBarBackgroundTint) == "table" then
                        return true
                    end
                    return false
                end
                if hasBackgroundCustomization() then
                    local bgTexKeyPB = cfg.powerBarBackgroundTexture or "default"
                    local bgColorModePB = cfg.powerBarBackgroundColorMode or "default"
                    local bgOpacityPB = cfg.powerBarBackgroundOpacity or 50
                    applyBackgroundToBar(pb, bgTexKeyPB, bgColorModePB, cfg.powerBarBackgroundTint, bgOpacityPB, unit, "power")
                end
            end
            
            -- Re-apply texture-only hide after styling (ensures newly created ScooterModBG is also hidden)
            if powerBarHideTextureOnly and not powerBarHidden then
                if Util and Util.SetPowerBarTextureOnlyHidden then
                    Util.SetPowerBarTextureOnlyHidden(pb, true)
                end
            end
            
            ensureMaskOnBarTexture(pb, resolvePowerMask(unit))

            -- When texture-only hide is enabled, also hide animations/feedback/spark (they'd look weird floating)
            local hideAllVisuals = powerBarHidden or powerBarHideTextureOnly
            
            if unit == "Player" and Util and Util.SetFullPowerSpikeHidden then
                Util.SetFullPowerSpikeHidden(pb, cfg.powerBarHideFullSpikes == true or hideAllVisuals)
            end

            -- Hide power feedback animation (Builder/Spender flash when power is spent/gained)
            if unit == "Player" and Util and Util.SetPowerFeedbackHidden then
                Util.SetPowerFeedbackHidden(pb, cfg.powerBarHideFeedback == true or hideAllVisuals)
            end

            -- Hide power bar spark (e.g., Elemental Shaman Maelstrom indicator)
            if unit == "Player" and Util and Util.SetPowerBarSparkHidden then
                Util.SetPowerBarSparkHidden(pb, cfg.powerBarHideSpark == true or hideAllVisuals)
            end

            -- Hide mana cost prediction overlay (shows predicted power cost of current spell)
            if unit == "Player" and Util and Util.SetManaCostPredictionHidden then
                Util.SetManaCostPredictionHidden(pb, cfg.powerBarHideManaCostPrediction == true or hideAllVisuals)
            end

            -- Apply reverse fill for Target/Focus if configured
            if (unit == "Target" or unit == "Focus") and pb and pb.SetReverseFill then
                local shouldReverse = not not cfg.powerBarReverseFill
                pcall(pb.SetReverseFill, pb, shouldReverse)
            end

            -- Lightweight persistence hooks for Player Power Bar:
            --  - Texture: keep custom texture applied if Blizzard swaps StatusBarTexture.
            --  - Color:   keep Foreground Color (default/class/custom) applied if Blizzard calls SetStatusBarColor.
            -- IMPORTANT: Do NOT re-apply during combat. Even "cosmetic-only" calls like
            -- SetStatusBarTexture/SetVertexColor on protected unitframe StatusBars can taint the
            -- execution context and later surface as blocked calls in unrelated Blizzard code paths
            -- (e.g., AlternatePowerBar:Hide()).
            --
            -- Also IMPORTANT: Defer work with C_Timer.After(0) to break Blizzard's execution chain
            -- to break Blizzard's execution chain and avoid taint propagation.
            if unit == "Player" and _G.hooksecurefunc then
                if not getProp(pb, "powerTextureHooked") then
                    setProp(pb, "powerTextureHooked", true)
                    _G.hooksecurefunc(pb, "SetStatusBarTexture", function(self, ...)
                        if isEditModeActive() then return end
                        -- Ignore ScooterMod's own writes to avoid recursion.
                        if getProp(self, "ufInternalTextureWrite") then
                            return
                        end
                        -- When overlay is active, it handles everything (combat-safe).
                        -- Just re-anchor and re-hide the new fill texture.
                        local st = getState(self)
                        if st and st.powerOverlayActive then
                            updateRectPowerOverlay("Player", self)
                            local newTex = self:GetStatusBarTexture()
                            if newTex then pcall(newTex.SetAlpha, newTex, 0) end
                            return
                        end
                        if InCombatLockdown and InCombatLockdown() then
                            queuePowerBarReapply("Player")
                            return
                        end

                        -- Throttle: coalesce rapid texture resets into a single 0s re-apply.
                        if getProp(self, "powerReapplyPending") then
                            return
                        end
                        setProp(self, "powerReapplyPending", true)

                        local bar = self
                        if _G.C_Timer and _G.C_Timer.After then
                            _G.C_Timer.After(0, function()
                                if not bar then return end
                                setProp(bar, "powerReapplyPending", nil)
                                if InCombatLockdown and InCombatLockdown() then
                                    queuePowerBarReapply("Player")
                                    return
                                end
                                local db = addon and addon.db and addon.db.profile
                                if not db then return end
                                local unitFrames = rawget(db, "unitFrames")
                                local cfgP = unitFrames and rawget(unitFrames, "Player") or nil
                                if not cfgP then return end
                                local texKey = cfgP.powerBarTexture or "default"
                                local colorMode = cfgP.powerBarColorMode or "default"
                                local tint = cfgP.powerBarTint
                                -- Only re-apply if the user has configured a non-default texture.
                                if not (type(texKey) == "string" and texKey ~= "" and texKey ~= "default") then
                                    return
                                end
                                applyToBar(bar, texKey, colorMode, tint, "player", "power", "player")
                                -- Re-assert texture-only hide after any texture swap. The hide feature
                                -- attaches to the current fill/background textures, so a SetStatusBarTexture
                                -- can create a fresh texture that needs to be re-hidden.
                                if Util and Util.SetPowerBarTextureOnlyHidden and cfgP.powerBarHideTextureOnly == true and not (cfgP.powerBarHidden == true) then
                                    Util.SetPowerBarTextureOnlyHidden(bar, true)
                                end
                            end)
                        else
                            setProp(self, "powerReapplyPending", nil)
                        end
                    end)
                end
                if not getProp(pb, "powerColorHooked") then
                    setProp(pb, "powerColorHooked", true)
                    _G.hooksecurefunc(pb, "SetStatusBarColor", function(self, ...)
                        if isEditModeActive() then return end
                        -- When overlay is active, it handles color sync directly
                        -- (the sync hook in ensureRectPowerOverlay updates vertex color).
                        local st = getState(self)
                        if st and st.powerOverlayActive then
                            return
                        end
                        if InCombatLockdown and InCombatLockdown() then
                            queuePowerBarReapply("Player")
                            return
                        end

                        if getProp(self, "powerReapplyPending") then
                            return
                        end
                        setProp(self, "powerReapplyPending", true)

                        local bar = self
                        if _G.C_Timer and _G.C_Timer.After then
                            _G.C_Timer.After(0, function()
                                if not bar then return end
                                setProp(bar, "powerReapplyPending", nil)
                                if InCombatLockdown and InCombatLockdown() then
                                    queuePowerBarReapply("Player")
                                    return
                                end
                                local db = addon and addon.db and addon.db.profile
                                if not db then return end
                                local unitFrames = rawget(db, "unitFrames")
                                local cfgP = unitFrames and rawget(unitFrames, "Player") or nil
                                if not cfgP then return end
                                local texKey = cfgP.powerBarTexture or "default"
                                local colorMode = cfgP.powerBarColorMode or "default"
                                local tint = cfgP.powerBarTint

                                -- If color mode is "texture", the user wants the texture's original colors;
                                -- in that case we allow Blizzard's SetStatusBarColor to stand.
                                if colorMode == "texture" then
                                    return
                                end

                                -- Only do work when the user has customized either texture or color;
                                -- default settings can safely follow Blizzard's behavior.
                                local hasCustomTexture = (type(texKey) == "string" and texKey ~= "" and texKey ~= "default")
                                local hasCustomColor = (colorMode == "custom" and type(tint) == "table") or (colorMode == "class")
                                if not hasCustomTexture and not hasCustomColor then
                                    return
                                end

                                applyToBar(bar, texKey, colorMode, tint, "player", "power", "player")
                                -- Re-assert texture-only hide after any styling pass that may refresh textures.
                                if Util and Util.SetPowerBarTextureOnlyHidden and cfgP.powerBarHideTextureOnly == true and not (cfgP.powerBarHidden == true) then
                                    Util.SetPowerBarTextureOnlyHidden(bar, true)
                                end
                            end)
                        else
                            setProp(self, "powerReapplyPending", nil)
                        end
                    end)
                end
            end

            -- Alternate Power Bar styling (Player-only, class/spec gated)
            if unit == "Player" and addon.UnitFrames_PlayerHasAlternatePowerBar and addon.UnitFrames_PlayerHasAlternatePowerBar() then
                local apb = resolveAlternatePowerBar()
                if apb then
                    -- Zero‑Touch: only style Alternate Power Bar when explicitly configured.
                    local acfg = rawget(cfg, "altPowerBar")
                    if acfg then

                    -- Optional hide toggle
                    local altHidden = (acfg.hidden == true)
                    if apb.GetAlpha and getProp(apb, "origAltAlpha") == nil then
                        local ok, a = pcall(apb.GetAlpha, apb)
                        setProp(apb, "origAltAlpha", ok and (a or 1) or 1)
                    end
                    if altHidden then
                        if apb.SetAlpha then pcall(apb.SetAlpha, apb, 0) end
                    else
                        local origAlpha = getProp(apb, "origAltAlpha")
                        if origAlpha and apb.SetAlpha then
                            pcall(apb.SetAlpha, apb, origAlpha)
                        end
                    end

                    -- Foreground texture / color
                    local altTexKey = acfg.texture or "default"
                    local altColorMode = acfg.colorMode or "default"
                    local altTint = acfg.tint
                    applyToBar(apb, altTexKey, altColorMode, altTint, "player", "altpower", "player")

                    -- Background texture / color / opacity
                    local altBgTexKey = acfg.backgroundTexture or "default"
                    local altBgColorMode = acfg.backgroundColorMode or "default"
                    local altBgOpacity = acfg.backgroundOpacity or 50
                    applyBackgroundToBar(apb, altBgTexKey, altBgColorMode, acfg.backgroundTint, altBgOpacity, unit, "altpower")

                    -- Hide texture only (bar visible=false but text visible=true)
                    local altHideTextureOnly = (acfg.hideTextureOnly == true)
                    if Util and Util.SetPowerBarTextureOnlyHidden then
                        Util.SetPowerBarTextureOnlyHidden(apb, altHideTextureOnly and not altHidden)
                    end

                    -- Clear custom borders when texture-only hide is enabled (so only text remains)
                    if altHideTextureOnly and not altHidden then
                        if addon.BarBorders and addon.BarBorders.ClearBarFrame then
                            addon.BarBorders.ClearBarFrame(apb)
                        end
                        if addon.Borders and addon.Borders.HideAll then
                            addon.Borders.HideAll(apb)
                        end
                    end

                    -- Determine if all visuals should be hidden (when bar is fully hidden or texture-only hidden)
                    local hideAllVisuals = altHidden or altHideTextureOnly

                    -- Full power spike animations
                    if Util and Util.SetFullPowerSpikeHidden then
                        Util.SetFullPowerSpikeHidden(apb, acfg.hideFullSpikes == true or hideAllVisuals)
                    end

                    -- Power feedback flash
                    if Util and Util.SetPowerFeedbackHidden then
                        Util.SetPowerFeedbackHidden(apb, acfg.hideFeedback == true or hideAllVisuals)
                    end

                    -- Spark/glow indicator
                    if Util and Util.SetPowerBarSparkHidden then
                        Util.SetPowerBarSparkHidden(apb, acfg.hideSpark == true or hideAllVisuals)
                    end

                    -- Mana cost prediction overlay
                    if Util and Util.SetManaCostPredictionHidden then
                        Util.SetManaCostPredictionHidden(apb, acfg.hideManaCostPrediction == true or hideAllVisuals)
                    end

                    -- Custom border (shares global Use Custom Borders; Alt Power has its own style/tint/thickness/inset)
                    do
                        -- Global unit-frame switch; borders only draw when this is enabled.
                        -- Skip borders when bar is hidden or texture-only mode (only text should remain).
                        local useCustomBorders = not not cfg.useCustomBorders
                        if useCustomBorders and not altHidden and not altHideTextureOnly then
                            -- Style resolution: prefer Alternate Power–specific, then Power, then Health.
                            local styleKey = acfg.borderStyle
                                or cfg.powerBarBorderStyle
                                or cfg.healthBarBorderStyle

                            -- Tint enable: prefer Alternate Power–specific, then Power, then Health.
                            local tintEnabled
                            if acfg.borderTintEnable ~= nil then
                                tintEnabled = not not acfg.borderTintEnable
                            elseif cfg.powerBarBorderTintEnable ~= nil then
                                tintEnabled = not not cfg.powerBarBorderTintEnable
                            else
                                tintEnabled = not not cfg.healthBarBorderTintEnable
                            end

                            -- Tint color: prefer Alternate Power–specific, then Power, then Health.
                            local baseTint = type(acfg.borderTintColor) == "table" and acfg.borderTintColor
                                or cfg.powerBarBorderTintColor
                                or cfg.healthBarBorderTintColor
                            local tintColor = type(baseTint) == "table" and {
                                baseTint[1] or 1,
                                baseTint[2] or 1,
                                baseTint[3] or 1,
                                baseTint[4] or 1,
                            } or { 1, 1, 1, 1 }

                            -- Thickness / inset: prefer Alternate Power–specific, then Power, then Health.
                            local thickness = tonumber(acfg.borderThickness)
                                or tonumber(cfg.powerBarBorderThickness)
                                or tonumber(cfg.healthBarBorderThickness)
                                or 1
                            if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end

                            local insetH, insetV
                            if acfg.borderInsetH ~= nil or acfg.borderInsetV ~= nil then
                                insetH = tonumber(acfg.borderInsetH) or tonumber(acfg.borderInset) or 0
                                insetV = tonumber(acfg.borderInsetV) or tonumber(acfg.borderInset) or 0
                            elseif cfg.powerBarBorderInsetH ~= nil or cfg.powerBarBorderInsetV ~= nil or cfg.powerBarBorderInset ~= nil then
                                insetH = tonumber(cfg.powerBarBorderInsetH) or tonumber(cfg.powerBarBorderInset) or 0
                                insetV = tonumber(cfg.powerBarBorderInsetV) or tonumber(cfg.powerBarBorderInset) or 0
                            else
                                insetH = tonumber(cfg.healthBarBorderInsetH) or tonumber(cfg.healthBarBorderInset) or 0
                                insetV = tonumber(cfg.healthBarBorderInsetV) or tonumber(cfg.healthBarBorderInset) or 0
                            end

                            if styleKey == "none" or styleKey == nil then
                                if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(apb) end
                                if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(apb) end
                            else
                                local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
                                local color
                                if tintEnabled then
                                    color = tintColor
                                else
                                    if styleDef then
                                        color = { 1, 1, 1, 1 }
                                    else
                                        color = { 0, 0, 0, 1 }
                                    end
                                end

                                local handled = false
                                if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
                                    if addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(apb) end
                                    handled = addon.BarBorders.ApplyToBarFrame(apb, styleKey, {
                                        color = color,
                                        thickness = thickness,
                                        levelOffset = 1,
                                        containerParent = (apb and apb:GetParent()) or nil,
                                        insetH = insetH,
                                        insetV = insetV,
                                    })
                                end

                                if not handled then
                                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(apb) end
                                    if addon.Borders and addon.Borders.ApplySquare then
                                        local sqColor = tintEnabled and tintColor or { 0, 0, 0, 1 }
                                        local baseY = (thickness <= 1) and 0 or 1
                                        local baseX = 1
                                        local expandY = baseY - insetV
                                        local expandX = baseX - insetH
                                        if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                                        if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                                        addon.Borders.ApplySquare(apb, {
                                            size = thickness,
                                            color = sqColor,
                                            layer = "OVERLAY",
                                            layerSublevel = 3,
                                            expandX = expandX,
                                            expandY = expandY,
                                        })
                                    end
                                end
                            end
                        else
                            -- Global custom borders disabled: clear any previous Alternate Power border.
                            if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(apb) end
                            if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(apb) end
                        end
                    end

                    -- % Text and Value Text (AlternatePowerBar.LeftText / RightText)
                    do
                        local leftFS = apb.LeftText
                        local rightFS = apb.RightText
                        -- Also resolve the center TextString (used in NUMERIC display mode)
                        -- This ensures styling persists when Blizzard switches between BOTH and NUMERIC modes
                        local textStringFS = apb.TextString or apb.text

                        -- Helper: Apply visibility using SetAlpha (combat-safe) instead of SetShown (taint-prone).
                        -- Hooks Show(), SetAlpha(), and SetText() to re-enforce BOTH alpha=0 AND font styling when Blizzard updates.
                        local function applyAltPowerTextVisibility(fs, hidden)
                            if not fs then return end
                            local st = getState(fs)
                            if not st then return end
                            if hidden then
                                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 0) end
                                -- Install hooks once to re-enforce alpha when Blizzard calls Show(), SetAlpha(), or SetText()
                                if not st.altPowerTextVisibilityHooked then
                                    st.altPowerTextVisibilityHooked = true
                                    if _G.hooksecurefunc then
                                        -- Hook Show() to re-enforce alpha=0
                                        _G.hooksecurefunc(fs, "Show", function(self)
                                            if isEditModeActive() then return end
                                            local s = getState(self)
                                            if s and s.altPowerTextHidden and self.SetAlpha then
                                                pcall(self.SetAlpha, self, 0)
                                            end
                                        end)
                                        -- Hook SetAlpha() to re-enforce alpha=0 when Blizzard tries to make it visible
                                        _G.hooksecurefunc(fs, "SetAlpha", function(self, alpha)
                                            if isEditModeActive() then return end
                                            local s = getState(self)
                                            if s and s.altPowerTextHidden and alpha and alpha > 0 then
                                                -- Use C_Timer to avoid infinite recursion (hook calls SetAlpha which triggers hook)
                                                if not s.altPowerTextAlphaDeferred then
                                                    s.altPowerTextAlphaDeferred = true
                                                    C_Timer.After(0, function()
                                                        local s2 = getState(self)
                                                        if s2 then s2.altPowerTextAlphaDeferred = nil end
                                                        if s2 and s2.altPowerTextHidden and self.SetAlpha then
                                                            pcall(self.SetAlpha, self, 0)
                                                        end
                                                    end)
                                                end
                                            end
                                        end)
                                        -- Hook SetText() to re-enforce alpha=0 when Blizzard updates text content
                                        _G.hooksecurefunc(fs, "SetText", function(self)
                                            if isEditModeActive() then return end
                                            local s = getState(self)
                                            if s and s.altPowerTextHidden and self.SetAlpha then
                                                pcall(self.SetAlpha, self, 0)
                                            end
                                        end)
                                    end
                                end
                                st.altPowerTextHidden = true
                            else
                                st.altPowerTextHidden = false
                                if fs.SetAlpha then pcall(fs.SetAlpha, fs, 1) end
                            end
                        end

                        -- NOTE: SetFont/SetFontObject hooks removed for performance reasons.
                        -- Font persistence is handled by the Character Frame hook in text.lua.

                        -- Visibility: respect both the bar-wide hidden flag and the per-text toggles.
                        local percentHidden = (acfg.percentHidden == true)
                        local valueHidden = (acfg.valueHidden == true)

                        applyAltPowerTextVisibility(leftFS, altHidden or percentHidden)
                        applyAltPowerTextVisibility(rightFS, altHidden or valueHidden)

                        -- Install SetText hook for center TextString to enforce hidden state only
                        local tsState = getState(textStringFS)
                        if textStringFS and tsState and not tsState.altPowerTextCenterSetTextHooked then
                            tsState.altPowerTextCenterSetTextHooked = true
                            if _G.hooksecurefunc then
                                _G.hooksecurefunc(textStringFS, "SetText", function(self)
                                    if isEditModeActive() then return end
                                    -- Enforce hidden state immediately if configured
                                    local s = getState(self)
                                    if s and s.altPowerTextCenterHidden and self.SetAlpha then
                                        pcall(self.SetAlpha, self, 0)
                                    end
                                end)
                            end
                        end

                        -- Styling (font/size/style/color/offset) using stable baseline anchors
                        addon._ufAltPowerTextBaselines = addon._ufAltPowerTextBaselines or {}
                        local function ensureBaseline(fs, key)
                            addon._ufAltPowerTextBaselines[key] = addon._ufAltPowerTextBaselines[key] or {}
                            local b = addon._ufAltPowerTextBaselines[key]
                            if b.point == nil then
                                if fs and fs.GetPoint then
                                    local p, relTo, rp, x, y = fs:GetPoint(1)
                                    -- Store raw values; sanitization happens at use time
                                    b.point = p
                                    b.relTo = relTo or (fs.GetParent and fs:GetParent()) or apb
                                    b.relPoint = rp
                                    b.x = x
                                    b.y = y
                                else
                                    b.point, b.relTo, b.relPoint, b.x, b.y =
                                        "CENTER", (fs and fs.GetParent and fs:GetParent()) or apb, "CENTER", 0, 0
                                end
                            end
                            return b
                        end

                        local function applyAltTextStyle(fs, styleCfg, baselineKey)
                            if not fs or not styleCfg then return end
                            -- Default/clean profiles should not modify Blizzard text.
                            -- Only apply styling if the user has configured any text settings.
                            local function hasTextCustomization(cfgT)
                                if not cfgT then return false end
                                -- Font face may be present as a structural default; treat the stock face as non-customization
                                -- unless other settings are set.
                                if cfgT.fontFace ~= nil and cfgT.fontFace ~= "" and cfgT.fontFace ~= "FRIZQT__" then
                                    return true
                                end
                                if cfgT.size ~= nil or cfgT.style ~= nil or cfgT.color ~= nil or cfgT.alignment ~= nil then
                                    return true
                                end
                                -- colorMode is used for APB text to support "classPower" color
                                if cfgT.colorMode ~= nil and cfgT.colorMode ~= "default" then
                                    return true
                                end
                                if cfgT.offset and (cfgT.offset.x ~= nil or cfgT.offset.y ~= nil) then
                                    local ox = tonumber(cfgT.offset.x) or 0
                                    local oy = tonumber(cfgT.offset.y) or 0
                                    if ox ~= 0 or oy ~= 0 then
                                        return true
                                    end
                                end
                                return false
                            end
                            if not hasTextCustomization(styleCfg) then
                                return
                            end
                            local face = addon.ResolveFontFace
                                and addon.ResolveFontFace(styleCfg.fontFace or "FRIZQT__")
                                or (select(1, _G.GameFontNormal:GetFont()))
                            local size = tonumber(styleCfg.size) or 14
                            local outline = tostring(styleCfg.style or "OUTLINE")
                            -- Set flag to prevent our SetFont hook from triggering a reapply loop
                            local fsState = getState(fs)
                            if fsState then fsState.applyingFont = true end
                            if addon.ApplyFontStyle then addon.ApplyFontStyle(fs, face, size, outline) elseif fs.SetFont then pcall(fs.SetFont, fs, face, size, outline) end
                            if fsState then fsState.applyingFont = nil end
                            -- Determine effective color based on colorMode
                            local c = styleCfg.color or {1, 1, 1, 1}
                            local colorMode = styleCfg.colorMode or "default"
                            if colorMode == "classPower" then
                                -- Use the class's power bar color (Energy = yellow, Rage = red, Mana = blue, etc.)
                                if addon.GetPowerColorRGB then
                                    local pr, pg, pb = addon.GetPowerColorRGB("player")
                                    -- Lighten mana blue for text readability (mana = powerType 0)
                                    local powerType = UnitPowerType("player")
                                    if powerType == 0 then -- MANA
                                        local lightenFactor = 0.25
                                        pr = (pr or 0) + (1 - (pr or 0)) * lightenFactor
                                        pg = (pg or 0) + (1 - (pg or 0)) * lightenFactor
                                        pb = (pb or 0) + (1 - (pb or 0)) * lightenFactor
                                    end
                                    c = {pr or 1, pg or 1, pb or 1, 1}
                                end
                            elseif colorMode == "class" then
                                local cr, cg, cb = addon.GetClassColorRGB("player")
                                c = {cr or 1, cg or 1, cb or 1, 1}
                            elseif colorMode == "default" then
                                -- Default white for Blizzard's standard bar text color
                                c = {1, 1, 1, 1}
                            end
                            -- colorMode == "custom" uses styleCfg.color as-is
                            if fs.SetTextColor then
                                pcall(fs.SetTextColor, fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
                            end

                            -- Apply text alignment using two-point anchoring (matches text.lua pattern).
                            -- This makes SetJustifyH work correctly without needing GetWidth() (which can
                            -- trigger secret value errors on unit frame StatusBars).
                            -- Check for both :right and -right patterns to handle all key formats
                            local defaultAlign = "LEFT"
                            if baselineKey and (baselineKey:find(":right", 1, true) or baselineKey:find("-right", 1, true)) then
                                defaultAlign = "RIGHT"
                            elseif baselineKey and (baselineKey:find(":center", 1, true) or baselineKey:find("-center", 1, true)) then
                                defaultAlign = "CENTER"
                            end
                            local alignment = styleCfg.alignment or defaultAlign
                            local parentBar = fs:GetParent()

                            local ox = (styleCfg.offset and tonumber(styleCfg.offset.x)) or 0
                            local oy = (styleCfg.offset and tonumber(styleCfg.offset.y)) or 0

                            -- Get baseline Y position for vertical offset
                            local b = ensureBaseline(fs, baselineKey)
                            local yOffset = safeOffset(b.y) + oy

                            -- Use two-point anchoring to span the parent bar width.
                            if fs.ClearAllPoints and fs.SetPoint and parentBar then
                                fs:ClearAllPoints()
                                -- Anchor both left and right edges to span the bar
                                local leftPad = 2 + ox
                                local rightPad = -2 + ox
                                pcall(fs.SetPoint, fs, "LEFT", parentBar, "LEFT", leftPad, yOffset)
                                pcall(fs.SetPoint, fs, "RIGHT", parentBar, "RIGHT", rightPad, yOffset)
                            end

                            if fs.SetJustifyH then
                                pcall(fs.SetJustifyH, fs, alignment)
                            end

                            -- Force text redraw to apply alignment visually (secret-value safe)
                            if fs and fs.GetText and fs.SetText then
                                local ok, txt = pcall(fs.GetText, fs)
                                if ok and txt and type(txt) == "string" then
                                    fs:SetText("")
                                    fs:SetText(txt)
                                else
                                    -- Fallback: toggle alpha to force redraw without needing text value
                                    local okAlpha, alpha = pcall(function() return fs.GetAlpha and fs:GetAlpha() end)
                                    if okAlpha and alpha then
                                        pcall(fs.SetAlpha, fs, 0)
                                        pcall(fs.SetAlpha, fs, alpha)
                                    end
                                end
                            end
                        end

                        if leftFS then
                            applyAltTextStyle(leftFS, acfg.textPercent or {}, "Player:altpower-left")
                        end
                        if rightFS then
                            applyAltTextStyle(rightFS, acfg.textValue or {}, "Player:altpower-right")
                        end
                        -- Style center TextString using Value settings (used in NUMERIC display mode)
                        -- If Value text is hidden (or entire bar is hidden), also hide center text
                        if textStringFS then
                            local centerHidden = altHidden or valueHidden
                            local tsState = getState(textStringFS)
                            if centerHidden then
                                if textStringFS.SetAlpha then pcall(textStringFS.SetAlpha, textStringFS, 0) end
                                if tsState then tsState.altPowerTextCenterHidden = true end
                            else
                                if tsState and tsState.altPowerTextCenterHidden then
                                    if textStringFS.SetAlpha then pcall(textStringFS.SetAlpha, textStringFS, 1) end
                                    tsState.altPowerTextCenterHidden = nil
                                end
                                applyAltTextStyle(textStringFS, acfg.textValue or {}, "Player:altpower-center")
                            end
                        end
                    end

                    -- Width / height scaling (simple frame SetWidth/SetHeight based on %),
                    -- plus additive X/Y offsets applied from the captured baseline points.
                    if not inCombat then
                        local apbState = getState(apb)
                        if not apbState then return end
                        -- Capture originals once
                        if not apbState.ufOrigWidth then
                            if apb.GetWidth then
                                local ok, w = pcall(apb.GetWidth, apb)
                                if ok and w then apbState.ufOrigWidth = w end
                            end
                        end
                        if not apbState.ufOrigHeight then
                            if apb.GetHeight then
                                local ok, h = pcall(apb.GetHeight, apb)
                                if ok and h then apbState.ufOrigHeight = h end
                            end
                        end
                        if not apbState.ufOrigPoints then
                            local pts = {}
                            local n = (apb.GetNumPoints and apb:GetNumPoints()) or 0
                            for i = 1, n do
                                local p, rel, rp, x, y = apb:GetPoint(i)
                                table.insert(pts, { p, rel, rp, x or 0, y or 0 })
                            end
                            apbState.ufOrigPoints = pts
                        end

                        local wPct = tonumber(acfg.widthPct) or 100
                        local hPct = tonumber(acfg.heightPct) or 100
                        local scaleX = math.max(0.5, math.min(1.5, wPct / 100))
                        local scaleY = math.max(0.5, math.min(2.0, hPct / 100))

                        -- Restore baseline first
                        if apbState.ufOrigWidth and apb.SetWidth then
                            pcall(apb.SetWidth, apb, apbState.ufOrigWidth)
                        end
                        if apbState.ufOrigHeight and apb.SetHeight then
                            pcall(apb.SetHeight, apb, apbState.ufOrigHeight)
                        end
                        if apbState.ufOrigPoints and apb.ClearAllPoints and apb.SetPoint then
                            pcall(apb.ClearAllPoints, apb)
                            for _, pt in ipairs(apbState.ufOrigPoints) do
                                pcall(apb.SetPoint, apb, pt[1] or "CENTER", pt[2], pt[3] or pt[1] or "CENTER", pt[4] or 0, pt[5] or 0)
                            end
                        end

                        -- Apply width/height scaling (from center)
                        if apbState.ufOrigWidth and apb.SetWidth then
                            pcall(apb.SetWidth, apb, apbState.ufOrigWidth * scaleX)
                        end
                        if apbState.ufOrigHeight and apb.SetHeight then
                            pcall(apb.SetHeight, apb, apbState.ufOrigHeight * scaleY)
                        end

                        -- Apply positioning offsets relative to the original anchor points.
                        local offsetX = tonumber(acfg.offsetX) or 0
                        local offsetY = tonumber(acfg.offsetY) or 0
                        if apbState.ufOrigPoints and apb.ClearAllPoints and apb.SetPoint then
                            pcall(apb.ClearAllPoints, apb)
                            for _, pt in ipairs(apbState.ufOrigPoints) do
                                local baseX = pt[4] or 0
                                local baseY = pt[5] or 0
                                local newX = baseX + offsetX
                                local newY = baseY + offsetY
                                pcall(apb.SetPoint, apb, pt[1] or "CENTER", pt[2], pt[3] or pt[1] or "CENTER", newX, newY)
                            end
                        end
                    end
                    end -- acfg
                end
            end

            -- Experimental: Power Bar Width scaling (texture/mask only)
            -- For Target/Focus: Only when reverse fill is enabled
            -- For Player: Always available
            -- Pet excluded - even pcall-wrapped GetWidth on PetFrame's power bar
            -- can trigger Blizzard internal updates that error on "secret values".
            do
                local canScale = false
                if unit == "Player" then
                    canScale = true
                elseif (unit == "Target" or unit == "Focus") and cfg.powerBarReverseFill then
                    canScale = true
                end

                local pbState = getState(pb)
                if not pbState then return end
                if canScale and not inCombat then
                    local pct = tonumber(cfg.powerBarWidthPct) or 100
                    local tex = pb.GetStatusBarTexture and pb:GetStatusBarTexture()
                    local mask = resolvePowerMask(unit)
					local isMirroredUnit = (unit == "Target" or unit == "Focus")
					local scaleX = math.min(1.5, math.max(0.5, (pct or 100) / 100))

                    -- Capture original PB width once
                    if pb and not pbState.ufOrigWidth then
                        if pb.GetWidth then
                            local ok, w = pcall(pb.GetWidth, pb)
                            if ok and w then pbState.ufOrigWidth = w end
                        end
                    end

                    -- Capture original PB anchors
                    if pb and not pbState.ufOrigPoints then
                        local pts = {}
                        local n = (pb.GetNumPoints and pb:GetNumPoints()) or 0
                        for i = 1, n do
                            local p, rel, rp, x, y = pb:GetPoint(i)
                            table.insert(pts, { p, rel, rp, x or 0, y or 0 })
                        end
                        pbState.ufOrigPoints = pts
                    end

                    -- Helper: reanchor PB to grow left
                    local function reapplyPBPointsWithLeftOffset(dx)
                        if not pb or not pb.ClearAllPoints or not pb.SetPoint or not (pbState and pbState.ufOrigPoints) then return end
                        pcall(pb.ClearAllPoints, pb)
                        for _, pt in ipairs(pbState.ufOrigPoints) do
                            pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", (pt[4] or 0) - dx, pt[5] or 0)
                        end
                    end

                    -- Helper: reanchor PB to grow right
                    local function reapplyPBPointsWithRightOffset(dx)
                        if not pb or not pb.ClearAllPoints or not pb.SetPoint or not (pbState and pbState.ufOrigPoints) then return end
                        pcall(pb.ClearAllPoints, pb)
                        for _, pt in ipairs(pbState.ufOrigPoints) do
                            pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", (pt[4] or 0) + dx, pt[5] or 0)
                        end
                    end

					-- CRITICAL: Always restore to original state FIRST before applying new width
					-- Always start from the captured baseline to avoid cumulative offsets.
					if pb and pbState.ufOrigWidth and pb.SetWidth then
						pcall(pb.SetWidth, pb, pbState.ufOrigWidth)
					end
					if pb and pbState.ufOrigPoints and pb.ClearAllPoints and pb.SetPoint then
						pcall(pb.ClearAllPoints, pb)
						for _, pt in ipairs(pbState.ufOrigPoints) do
							pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", pt[4] or 0, pt[5] or 0)
						end
					end

                    if pct > 100 then
                        -- Widen the status bar frame
                        if pb and pb.SetWidth and pbState.ufOrigWidth then
                            pcall(pb.SetWidth, pb, pbState.ufOrigWidth * scaleX)
                        end

                        -- Reposition the frame to control growth direction
                        if pb and pbState.ufOrigWidth then
                            local dx = (pbState.ufOrigWidth * (scaleX - 1))
                            if dx and dx ~= 0 then
                                if unit == "Target" or unit == "Focus" then
                                    reapplyPBPointsWithLeftOffset(dx)
                                else
                                    reapplyPBPointsWithRightOffset(dx)
                                end
                            end
                        end

                        -- DO NOT touch the StatusBar texture - it's managed automatically by the StatusBar widget
                        -- REMOVE the mask entirely when widening - it causes rendering artifacts
                        if tex and mask and tex.RemoveMaskTexture then
                            pcall(tex.RemoveMaskTexture, tex, mask)
                        end
                        -- NOTE: Do NOT call SetValue to "refresh" the texture - it taints the protected StatusBar
                        -- and causes "blocked from an action" errors when Blizzard later calls Show().
                        -- The StatusBar refreshes automatically when its dimensions change.
                    elseif pct < 100 then
						-- Narrow the status bar frame
						if pb and pb.SetWidth and pbState.ufOrigWidth then
							pcall(pb.SetWidth, pb, pbState.ufOrigWidth * scaleX)
						end
						-- Reposition so mirrored bars keep the portrait edge anchored
						if pb and pbState.ufOrigWidth then
							local shrinkDx = pbState.ufOrigWidth * (1 - scaleX)
							if shrinkDx and shrinkDx ~= 0 and isMirroredUnit then
								reapplyPBPointsWithLeftOffset(-shrinkDx)
							end
						end
						-- Ensure mask remains applied when narrowing
						if pb and mask then
							ensureMaskOnBarTexture(pb, mask)
						end
                    else
                        -- Restore power bar frame
                        if pb and pbState.ufOrigWidth and pb.SetWidth then
                            pcall(pb.SetWidth, pb, pbState.ufOrigWidth)
                        end
                        if pb and pbState.ufOrigPoints and pb.ClearAllPoints and pb.SetPoint then
                            pcall(pb.ClearAllPoints, pb)
                            for _, pt in ipairs(pbState.ufOrigPoints) do
                                pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", pt[4] or 0, pt[5] or 0)
                            end
                        end
                        -- Re-apply mask to texture at original dimensions
                        if pb and mask then
                            ensureMaskOnBarTexture(pb, mask)
                        end
                    end
				elseif not inCombat then
					-- Not scalable (Target/Focus with default fill): ensure we restore any prior width/anchors/mask
					local tex = pb.GetStatusBarTexture and pb:GetStatusBarTexture()
					local mask = resolvePowerMask(unit)
					-- Restore power bar frame
					if pb and pbState.ufOrigWidth and pb.SetWidth then
						pcall(pb.SetWidth, pb, pbState.ufOrigWidth)
					end
					if pb and pbState.ufOrigPoints and pb.ClearAllPoints and pb.SetPoint then
						pcall(pb.ClearAllPoints, pb)
						for _, pt in ipairs(pbState.ufOrigPoints) do
							pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", pt[4] or 0, pt[5] or 0)
						end
					end
					-- Re-apply mask to texture at original dimensions
					if pb and mask then
						ensureMaskOnBarTexture(pb, mask)
					end
							end
						end
			
			-- Power Bar Height scaling (texture/mask only)
			-- For Target/Focus: Only when reverse fill is enabled
			-- For Player: Always available
			-- Pet excluded - even pcall-wrapped GetHeight on PetFrame's power bar
			-- can trigger Blizzard internal updates that error on "secret values".
			do
                -- Skip all Power Bar height scaling while in combat; defer to the next
                -- out-of-combat styling pass instead to avoid taint.
                if not inCombat then
				    local canScale = false
				    if unit == "Player" then
					    canScale = true
				    elseif (unit == "Target" or unit == "Focus") and cfg.powerBarReverseFill then
					    canScale = true
				    end
				
				    local pbState = getState(pb)
				    if not pbState then return end
				    if canScale then
					    local pct = tonumber(cfg.powerBarHeightPct) or 100
					    local widthPct = tonumber(cfg.powerBarWidthPct) or 100
					    local tex = pb.GetStatusBarTexture and pb:GetStatusBarTexture()
					    local mask = resolvePowerMask(unit)
					    local texState = getState(tex)
					    local maskState = getState(mask)
					
					    -- Capture originals once (height and anchor points)
					    if tex and texState and not texState.origCapturedHeight then
						    if tex.GetHeight then
							    local ok, h = pcall(tex.GetHeight, tex)
							    if ok and h then texState.origHeight = h end
						    end
						    -- Texture anchor points already captured by width scaling
						    texState.origCapturedHeight = true
					    end
					    if mask and maskState and not maskState.origCapturedHeight then
						    if mask.GetHeight then
							    local ok, h = pcall(mask.GetHeight, mask)
							    if ok and h then maskState.origHeight = h end
						    end
						    -- Mask anchor points already captured by width scaling
						    maskState.origCapturedHeight = true
					    end
					
					    -- Anchor points should already be captured by width scaling
					    -- If not, capture them now
					    if pb and not pbState.ufOrigPoints then
						    local pts = {}
						    local n = (pb.GetNumPoints and pb:GetNumPoints()) or 0
						    for i = 1, n do
							    local p, rel, rp, x, y = pb:GetPoint(i)
							    table.insert(pts, { p, rel, rp, x or 0, y or 0 })
						    end
						    pbState.ufOrigPoints = pts
					    end
					
					    -- Helper: reanchor PB to grow downward (keep top fixed)
					    local function reapplyPBPointsWithBottomOffset(dy)
						    -- Positive dy moves BOTTOM/CENTER anchors downward (keep top edge fixed)
						    local pts = pbState and pbState.ufOrigPoints
						    if not (pb and pts and pb.ClearAllPoints and pb.SetPoint) then return end
						    pcall(pb.ClearAllPoints, pb)
						    for _, pt in ipairs(pts) do
							    local p, rel, rp, x, y = pt[1], pt[2], pt[3], pt[4], pt[5]
							    local yy = y or 0
							    local anchor = tostring(p or "")
							    local relp = tostring(rp or "")
							    if string.find(anchor, "BOTTOM", 1, true) or string.find(relp, "BOTTOM", 1, true) then
								    yy = (y or 0) - (dy or 0)
							    elseif string.find(anchor, "CENTER", 1, true) or string.find(relp, "CENTER", 1, true) then
								    yy = (y or 0) - ((dy or 0) * 0.5)
							    end
							    pcall(pb.SetPoint, pb, p or "TOP", rel, rp or p or "TOP", x or 0, yy or 0)
						    end
					    end
					
					    local scaleY = math.max(0.5, math.min(2.0, pct / 100))
					
					    -- Capture original PowerBar height once
					    if pb and not pbState.ufOrigHeight then
						    if pb.GetHeight then
							    local ok, h = pcall(pb.GetHeight, pb)
							    if ok and h then pbState.ufOrigHeight = h end
						    end
					    end
					
					    -- CRITICAL: Always restore to original state FIRST
					    if pb and pbState.ufOrigHeight and pb.SetHeight then
						    pcall(pb.SetHeight, pb, pbState.ufOrigHeight)
					    end
					    if pb and pbState.ufOrigPoints and pb.ClearAllPoints and pb.SetPoint then
						    pcall(pb.ClearAllPoints, pb)
						    for _, pt in ipairs(pbState.ufOrigPoints) do
							    pcall(pb.SetPoint, pb, pt[1] or "TOP", pt[2], pt[3] or pt[1] or "TOP", pt[4] or 0, pt[5] or 0)
						    end
					    end
					
					    if pct ~= 100 then
						    -- Scale the status bar frame height
						    if pb and pb.SetHeight and pbState.ufOrigHeight then
							    pcall(pb.SetHeight, pb, pbState.ufOrigHeight * scaleY)
						    end
						
						    -- Reposition the frame to grow downward (keep top fixed)
						    if pb and pbState.ufOrigHeight then
							    local dy = (pbState.ufOrigHeight * (scaleY - 1))
							    if dy and dy ~= 0 then
								    reapplyPBPointsWithBottomOffset(dy)
							    end
						    end
						
						    -- DO NOT touch the StatusBar texture - it's managed automatically by the StatusBar widget
						    -- REMOVE the mask entirely when scaling - it causes rendering artifacts
						    if tex and mask and tex.RemoveMaskTexture then
							    pcall(tex.RemoveMaskTexture, tex, mask)
						    end

							if Util and Util.ApplyFullPowerSpikeScale then
								Util.ApplyFullPowerSpikeScale(pb, scaleY)
							end
						    -- NOTE: Do NOT call SetValue to "refresh" the texture - it taints the protected StatusBar
						    -- and causes "blocked from an action" errors when Blizzard later calls Show().
						    -- The StatusBar refreshes automatically when its dimensions change.
					    else
						    -- Restore (already done above in the restore-first step)
						    -- Re-apply mask ONLY if both Width and Height are at 100%
						    -- (Width scaling removes the mask, so we shouldn't re-apply it if Width is still scaled)
						    if pb and mask and widthPct == 100 then
							    ensureMaskOnBarTexture(pb, mask)
						    end

							if Util and Util.ApplyFullPowerSpikeScale then
								Util.ApplyFullPowerSpikeScale(pb, 1)
							end
					    end
				    else
					    -- Not scalable (Target/Focus with default fill): ensure we restore any prior height/anchors
					    -- Restore power bar frame
					    if pb and pbState.ufOrigHeight and pb.SetHeight then
						    pcall(pb.SetHeight, pb, pbState.ufOrigHeight)
					    end
					    if pb and pbState.ufOrigPoints and pb.ClearAllPoints and pb.SetPoint then
						    pcall(pb.ClearAllPoints, pb)
						    for _, pt in ipairs(pbState.ufOrigPoints) do
							    pcall(pb.SetPoint, pb, pt[1] or "TOP", pt[2], pt[3] or pt[1] or "TOP", pt[4] or 0, pt[5] or 0)
						    end
					    end
						if Util and Util.ApplyFullPowerSpikeScale then
							Util.ApplyFullPowerSpikeScale(pb, 1)
						end
				    end
                end
			end
						
            -- Power Bar positioning offsets / custom positioning (Player only)
            do
                local customHandled = applyCustomPowerBarPosition(unit, pb, cfg)
                if not customHandled and not inCombat then
                    local offsetX = tonumber(cfg.powerBarOffsetX) or 0
                    local offsetY = tonumber(cfg.powerBarOffsetY) or 0

                    local pbState = getState(pb)
                    if pbState and not pbState.powerBarOrigPoints then
                        pbState.powerBarOrigPoints = {}
                        for i = 1, pb:GetNumPoints() do
                            local point, relativeTo, relativePoint, xOfs, yOfs = pb:GetPoint(i)
                            table.insert(pbState.powerBarOrigPoints, { point, relativeTo, relativePoint, xOfs, yOfs })
                        end
                    end

                    if offsetX ~= 0 or offsetY ~= 0 then
                        if pb.ClearAllPoints and pb.SetPoint then
                            pcall(pb.ClearAllPoints, pb)
                            local origPoints = pbState and pbState.powerBarOrigPoints or nil
                            if origPoints then
                                for _, pt in ipairs(origPoints) do
                                local newX = (pt[4] or 0) + offsetX
                                local newY = (pt[5] or 0) + offsetY
                                pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", newX, newY)
                                end
                            end
                        end
                    else
                        if pb.ClearAllPoints and pb.SetPoint then
                            pcall(pb.ClearAllPoints, pb)
                            local origPoints = pbState and pbState.powerBarOrigPoints or nil
                            if origPoints then
                                for _, pt in ipairs(origPoints) do
                                    pcall(pb.SetPoint, pb, pt[1] or "LEFT", pt[2], pt[3] or pt[1] or "LEFT", pt[4] or 0, pt[5] or 0)
                                end
                            end
                        end
                    end
                end
            end

            -- Power Bar custom border (mirrors Health Bar border settings; supports power-specific overrides)
            do
                local styleKey = cfg.powerBarBorderStyle or cfg.healthBarBorderStyle
                local tintEnabled
                if cfg.powerBarBorderTintEnable ~= nil then
                    tintEnabled = not not cfg.powerBarBorderTintEnable
                else
                    tintEnabled = not not cfg.healthBarBorderTintEnable
                end
                local baseTint = type(cfg.powerBarBorderTintColor) == "table" and cfg.powerBarBorderTintColor or cfg.healthBarBorderTintColor
                local tintColor = type(baseTint) == "table" and {
                    baseTint[1] or 1,
                    baseTint[2] or 1,
                    baseTint[3] or 1,
                    baseTint[4] or 1,
                } or {1, 1, 1, 1}
                local thickness = tonumber(cfg.powerBarBorderThickness) or tonumber(cfg.healthBarBorderThickness) or 1
                if thickness < 1 then thickness = 1 elseif thickness > 16 then thickness = 16 end
                local insetH = (cfg.powerBarBorderInsetH ~= nil) and tonumber(cfg.powerBarBorderInsetH) or (cfg.powerBarBorderInset ~= nil) and tonumber(cfg.powerBarBorderInset) or tonumber(cfg.healthBarBorderInsetH) or tonumber(cfg.healthBarBorderInset) or 0
                local insetV = (cfg.powerBarBorderInsetV ~= nil) and tonumber(cfg.powerBarBorderInsetV) or (cfg.powerBarBorderInset ~= nil) and tonumber(cfg.powerBarBorderInset) or tonumber(cfg.healthBarBorderInsetV) or tonumber(cfg.healthBarBorderInset) or 0
                -- PetFrame is managed/protected: do not create or level custom border frames.
                -- Skip border application when bar texture is hidden (number-only display).
                -- Skip border application when power bar is fully hidden.
                if unit ~= "Pet" and cfg.useCustomBorders and not powerBarHideTextureOnly and not powerBarHidden then
                    if styleKey == "none" or styleKey == nil then
                        if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                        if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(pb) end
                    else
                        local styleDef = addon.BarBorders and addon.BarBorders.GetStyle and addon.BarBorders.GetStyle(styleKey)
                        local color
                        if tintEnabled then
                            color = tintColor
                        else
                            if styleDef then
                                color = {1, 1, 1, 1}
                            else
                                color = {0, 0, 0, 1}
                            end
                        end
                        local handled = false
                        if addon.BarBorders and addon.BarBorders.ApplyToBarFrame then
                            if addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                            handled = addon.BarBorders.ApplyToBarFrame(pb, styleKey, {
                                color = color,
                                thickness = thickness,
                                levelOffset = 1,
                                containerParent = (pb and pb:GetParent()) or nil,
                                insetH = insetH,
                                insetV = insetV,
                            })
                        end
                        if not handled then
                            if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                            if addon.Borders and addon.Borders.ApplySquare then
                                local sqColor = tintEnabled and tintColor or {0, 0, 0, 1}
                                local baseY = (thickness <= 1) and 0 or 1
                                local baseX = 1
                                local expandY = baseY - insetV
                                local expandX = baseX - insetH
                                if expandX < -6 then expandX = -6 elseif expandX > 6 then expandX = 6 end
                                if expandY < -6 then expandY = -6 elseif expandY > 6 then expandY = 6 end
                                -- Pet is already excluded by the outer guard
                                addon.Borders.ApplySquare(pb, {
                                    size = thickness,
                                    color = sqColor,
                                    layer = "OVERLAY",
                                    layerSublevel = 3,
                                    expandX = expandX,
                                    expandY = expandY,
                                })
                            end
                        end
                        -- Keep ordering stable for power bar borders as well
                        ensureTextAndBorderOrdering(unit)
                        if pb and not getProp(pb, "ufZOrderHooked") and pb.HookScript then
                            pb:HookScript("OnSizeChanged", function()
                                if InCombatLockdown and InCombatLockdown() then
                                    return
                                end
                                ensureTextAndBorderOrdering(unit)
                            end)
                            setProp(pb, "ufZOrderHooked", true)
                        end
                    end
                else
                    if addon.BarBorders and addon.BarBorders.ClearBarFrame then addon.BarBorders.ClearBarFrame(pb) end
                    if addon.Borders and addon.Borders.HideAll then addon.Borders.HideAll(pb) end
                end

                -- NOTE: Spark height adjustment code was removed. The previous implementation
                -- of shrinking the spark to prevent it from extending below custom borders
                -- was causing worse visual artifacts than the original minor issue.
                -- Letting Blizzard manage the spark naturally produces better results.
            end
        end

        -- PlayerFrame_Update / TargetFrame_Update / FocusFrame_Update calls REMOVED —
        -- calling these global Blizzard update functions from addon context taints the
        -- registered system frames (PlayerFrame, TargetFrame, FocusFrame), causing secret
        -- value errors when Edit Mode later iterates them. Blizzard's own event-driven
        -- refresh cycle handles atlas/mask updates.

        -- Stock frame art (includes the health bar border)
        do
            local ft = resolveUnitFrameFrameTexture(unit)
            if ft then
                local function compute()
                    local db2 = addon and addon.db and addon.db.profile
                    local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                    local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
                    local hide = cfg2 and (cfg2.useCustomBorders or cfg2.healthBarHideBorder)
                    return hide and 0 or 1
                end
                applyAlpha(ft, compute())
                hookAlphaEnforcer(ft, compute)
            end
        end

        -- Target-specific prestige elements (PvP badge/portrait)
        if unit == "Target" then
            local contextual = _G.TargetFrame
                and _G.TargetFrame.TargetFrameContent
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentContextual
            if contextual then
                local prestigePortrait = contextual.PrestigePortrait
                if prestigePortrait then
                    local function computePrestigeAlpha()
                        local db2 = addon and addon.db and addon.db.profile
                        local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                        local cfg2 = unitFrames2 and rawget(unitFrames2, "Target") or nil
                        return (cfg2 and cfg2.useCustomBorders) and 0 or 1
                    end
                    applyAlpha(prestigePortrait, computePrestigeAlpha())
                    hookAlphaEnforcer(prestigePortrait, computePrestigeAlpha)
                end
                local prestigeBadge = contextual.PrestigeBadge
                if prestigeBadge then
                    local function computePrestigeAlpha()
                        local db2 = addon and addon.db and addon.db.profile
                        local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                        local cfg2 = unitFrames2 and rawget(unitFrames2, "Target") or nil
                        return (cfg2 and cfg2.useCustomBorders) and 0 or 1
                    end
                    applyAlpha(prestigeBadge, computePrestigeAlpha())
                    hookAlphaEnforcer(prestigeBadge, computePrestigeAlpha)
                end
                local pvpIcon = contextual.PvpIcon
                if pvpIcon then
                    local function computePvpIconAlpha()
                        local db2 = addon and addon.db and addon.db.profile
                        local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                        local cfg2 = unitFrames2 and rawget(unitFrames2, "Target") or nil
                        return (cfg2 and cfg2.useCustomBorders) and 0 or 1
                    end
                    applyAlpha(pvpIcon, computePvpIconAlpha())
                    hookAlphaEnforcer(pvpIcon, computePvpIconAlpha)
                end
            end
        end

        -- Boss-specific frame art: Handle all 5 Boss frames (Boss1TargetFrame through Boss5TargetFrame)
        -- Unlike other unit frames where there's a single frame per unit, Boss frames have 5 individual frames
        -- that all share the same config (db.unitFrames.Boss). We must apply hiding to each one.
        if unit == "Boss" then
            for i = 1, 5 do
                local bossFrame = _G["Boss" .. i .. "TargetFrame"]
                if bossFrame and bossFrame.TargetFrameContainer then
                    local bossFT = bossFrame.TargetFrameContainer.FrameTexture
                    if bossFT then
                        local function computeBossAlpha()
                            local db2 = addon and addon.db and addon.db.profile
                            local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                            local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                            local hide = cfgBoss and (cfgBoss.useCustomBorders or cfgBoss.healthBarHideBorder)
                            return hide and 0 or 1
                        end
                        applyAlpha(bossFT, computeBossAlpha())
                        hookAlphaEnforcer(bossFT, computeBossAlpha)
                    end
                    -- Also hide the Flash (aggro/threat glow) if present on Boss frames
                    local bossFlash = bossFrame.TargetFrameContainer.Flash
                    if bossFlash then
                        local function computeBossFlashAlpha()
                            local db2 = addon and addon.db and addon.db.profile
                            local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                            local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                            return (cfgBoss and cfgBoss.useCustomBorders) and 0 or 1
                        end
                        applyAlpha(bossFlash, computeBossFlashAlpha())
                        hookAlphaEnforcer(bossFlash, computeBossFlashAlpha)
                    end

                    -- Hide ReputationColor strip (Boss1TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor)
                    -- when "Hide Blizzard Frame Art & Animations" (useCustomBorders) is enabled.
                    local bossReputationColor = bossFrame.TargetFrameContent
                        and bossFrame.TargetFrameContent.TargetFrameContentMain
                        and bossFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                    if bossReputationColor then
                        local function computeBossReputationAlpha()
                            local db2 = addon and addon.db and addon.db.profile
                            local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                            local cfgBoss = unitFrames2 and rawget(unitFrames2, "Boss") or nil
                            return (cfgBoss and cfgBoss.useCustomBorders) and 0 or 1
                        end
                        applyAlpha(bossReputationColor, computeBossReputationAlpha())
                        hookAlphaEnforcer(bossReputationColor, computeBossReputationAlpha)
                    end
                end
            end
        end

        -- Player-specific frame art
        if unit == "Player" and _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer then
            local container = _G.PlayerFrame.PlayerFrameContainer
            local altTex = container.AlternatePowerFrameTexture
            local vehicleTex = container.VehicleFrameTexture

            local function compute()
                local db2 = addon and addon.db and addon.db.profile
                local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                local cfg2 = unitFrames2 and rawget(unitFrames2, "Player") or nil
                return (cfg2 and cfg2.useCustomBorders) and 0 or 1
            end

            if altTex then
                applyAlpha(altTex, compute())
                hookAlphaEnforcer(altTex, compute)
            end
            if vehicleTex then
                applyAlpha(vehicleTex, compute())
                hookAlphaEnforcer(vehicleTex, compute)
            end
        end
        
        -- Hide static visual elements when Use Custom Borders is enabled.
        -- Rationale: These elements (ReputationColor for Target/Focus, FrameFlash for Player, Flash for Target) have
        -- fixed positions that cannot be adjusted. Since ScooterMod allows users to reposition and
        -- resize health/power bars independently, these static overlays would remain in their original
        -- positions while the bars they're meant to surround/backdrop move elsewhere. This creates
        -- visual confusion, so we disable them when custom borders are active.
        
        -- Hide ReputationColor frame for Target/Focus when Use Custom Borders is enabled
        if (unit == "Target" or unit == "Focus") and cfg.useCustomBorders then
            local frame = getUnitFrameFor(unit)
            if frame then
                local reputationColor
                if unit == "Target" and _G.TargetFrame then
                    reputationColor = _G.TargetFrame.TargetFrameContent 
                        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                elseif unit == "Focus" and _G.FocusFrame then
                    reputationColor = _G.FocusFrame.TargetFrameContent
                        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                end
                if reputationColor then
                    local function computeAlpha()
                        local db2 = addon and addon.db and addon.db.profile
                        local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                        local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
                        return (cfg2 and cfg2.useCustomBorders) and 0 or 1
                    end
                    applyAlpha(reputationColor, 0)
                    hookAlphaEnforcer(reputationColor, computeAlpha)
                end
            end
        elseif (unit == "Target" or unit == "Focus") then
            -- Restore ReputationColor when Use Custom Borders is disabled
            local frame = getUnitFrameFor(unit)
            if frame then
                local reputationColor
                if unit == "Target" and _G.TargetFrame then
                    reputationColor = _G.TargetFrame.TargetFrameContent 
                        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                elseif unit == "Focus" and _G.FocusFrame then
                    reputationColor = _G.FocusFrame.TargetFrameContent
                        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                end
                if reputationColor then
                    local function computeAlpha()
                        local db2 = addon and addon.db and addon.db.profile
                        local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                        local cfg2 = unitFrames2 and rawget(unitFrames2, unit) or nil
                        return (cfg2 and cfg2.useCustomBorders) and 0 or 1
                    end
                    applyAlpha(reputationColor, 1)
                    hookAlphaEnforcer(reputationColor, computeAlpha)
                end
            end

    function addon.UnitFrames_GetPowerBarScreenPosition()
        local frame = getUnitFrameFor("Player")
        if not frame then
            return 0, 0
        end
        local pb = resolvePowerBar(frame, "Player")
        if not pb then
            return 0, 0
        end
        local x, y = getFrameScreenOffsets(pb)
        return clampScreenCoordinate(x), clampScreenCoordinate(y)
    end
        end
        
        -- Hide FrameFlash (aggro/threat glow) for Player when Use Custom Borders is enabled
        if unit == "Player" then
            if _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer then
                local frameFlash = _G.PlayerFrame.PlayerFrameContainer.FrameFlash
                if frameFlash then
                    local function computeAlpha()
                        local db2 = addon and addon.db and addon.db.profile
                        local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                        local cfgP = unitFrames2 and rawget(unitFrames2, "Player") or nil
                        return (cfgP and cfgP.useCustomBorders) and 0 or 1
                    end
                    applyAlpha(frameFlash, computeAlpha())
                    hookAlphaEnforcer(frameFlash, computeAlpha)
                end
            end
        end
        
        -- Hide Flash (aggro/threat glow) for Target when Use Custom Borders is enabled
        if unit == "Target" then
            if _G.TargetFrame and _G.TargetFrame.TargetFrameContainer then
                local targetFlash = _G.TargetFrame.TargetFrameContainer.Flash
                if targetFlash then
                    local function computeAlpha()
                        local db2 = addon and addon.db and addon.db.profile
                        local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                        local cfgT = unitFrames2 and rawget(unitFrames2, "Target") or nil
                        return (cfgT and cfgT.useCustomBorders) and 0 or 1
                    end
                    applyAlpha(targetFlash, computeAlpha())
                    hookAlphaEnforcer(targetFlash, computeAlpha)
                end
            end
        end
        
        -- Hide Flash (aggro/threat glow) for Focus when Use Custom Borders is enabled
        if unit == "Focus" then
            if _G.FocusFrame and _G.FocusFrame.TargetFrameContainer then
                local focusFlash = _G.FocusFrame.TargetFrameContainer.Flash
                if focusFlash then
                    local function computeAlpha()
                        local db2 = addon and addon.db and addon.db.profile
                        local unitFrames2 = db2 and rawget(db2, "unitFrames") or nil
                        local cfgF = unitFrames2 and rawget(unitFrames2, "Focus") or nil
                        return (cfgF and cfgF.useCustomBorders) and 0 or 1
                    end
                    applyAlpha(focusFlash, computeAlpha())
                    hookAlphaEnforcer(focusFlash, computeAlpha)
                end
            end
        end
    end

    function addon.ApplyUnitFrameBarTexturesFor(unit)
        applyForUnit(unit)
    end

    function addon.ApplyAllUnitFrameBarTextures()
        -- Styling passes must be resilient to Blizzard "secret value" errors that can
        -- surface from innocuous getters on managed UnitFrames (e.g., PetFrame heal prediction).
        -- Never allow those to hard-fail profile switching/preset apply.
        local function safeApply(unit)
            pcall(applyForUnit, unit)
        end
        safeApply("Player")
        safeApply("Target")
        safeApply("Focus")
        safeApply("Boss")
        safeApply("Pet")
        safeApply("TargetOfTarget")
        safeApply("FocusTarget")
    end

    -- Re-enforce Vehicle/AlternatePower frame texture hiding after Blizzard art transitions.

    -- Enforce VehicleFrameTexture visibility based on Use Custom Borders setting
    local function EnforceVehicleFrameTextureVisibility()
        if isEditModeActive() then return end
        local db = addon and addon.db and addon.db.profile
        local unitFrames = db and rawget(db, "unitFrames") or nil
        local cfg = unitFrames and rawget(unitFrames, "Player") or nil
        if not cfg then return end
        if cfg.useCustomBorders ~= true then return end -- Only enforce when custom borders enabled
        
        local container = _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer
        local vehicleTex = container and container.VehicleFrameTexture
        if vehicleTex and vehicleTex.SetShown then
            pcall(vehicleTex.SetShown, vehicleTex, false)
        end
    end

    -- Enforce AlternatePowerFrameTexture visibility based on Use Custom Borders setting
    local function EnforceAlternatePowerFrameTextureVisibility()
        if isEditModeActive() then return end
        local db = addon and addon.db and addon.db.profile
        local unitFrames = db and rawget(db, "unitFrames") or nil
        local cfg = unitFrames and rawget(unitFrames, "Player") or nil
        if not cfg then return end
        if cfg.useCustomBorders ~= true then return end -- Only enforce when custom borders enabled
        
        local container = _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer
        local altTex = container and container.AlternatePowerFrameTexture
        if altTex and altTex.SetShown then
            pcall(altTex.SetShown, altTex, false)
        end
    end

    -- Install stable hooks to re-assert z-order after Blizzard refreshers
    local function installUFZOrderHooks()
        local function defer(unit)
            if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0, function() ensureTextAndBorderOrdering(unit) end) else ensureTextAndBorderOrdering(unit) end
        end
    end

    if not addon._UFZOrderHooksInstalled then
        addon._UFZOrderHooksInstalled = true
        -- Install hooks synchronously to ensure they're ready before ApplyStyles() runs
        installUFZOrderHooks()
    end

    -- Hook Blizzard's vehicle art transitions to re-enforce hiding.

    if not addon._VehicleArtHooksInstalled then
        addon._VehicleArtHooksInstalled = true

        -- Hook PlayerFrame_ToVehicleArt to re-enforce VehicleFrameTexture hiding
        -- This is called when entering a vehicle (Blizzard shows VehicleFrameTexture)
        if _G.hooksecurefunc and type(_G.PlayerFrame_ToVehicleArt) == "function" then
            _G.hooksecurefunc("PlayerFrame_ToVehicleArt", function()
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, EnforceVehicleFrameTextureVisibility)
                else
                    EnforceVehicleFrameTextureVisibility()
                end
            end)
        end

        -- Hook PlayerFrame_ToPlayerArt to re-enforce AlternatePowerFrameTexture hiding
        -- This is called when exiting a vehicle (Blizzard shows AlternatePowerFrameTexture)
        if _G.hooksecurefunc and type(_G.PlayerFrame_ToPlayerArt) == "function" then
            _G.hooksecurefunc("PlayerFrame_ToPlayerArt", function()
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, EnforceAlternatePowerFrameTextureVisibility)
                else
                    EnforceAlternatePowerFrameTextureVisibility()
                end
            end)
        end

        -- Install Show() hooks directly on the textures for extra coverage.
        -- This catches ANY Show() call, not just those from known Blizzard functions.
        local container = _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContainer
        
        -- VehicleFrameTexture Show() hook
        local vehicleTex = container and container.VehicleFrameTexture
        if vehicleTex and not getProp(vehicleTex, "showHooked") then
            setProp(vehicleTex, "showHooked", true)
            hooksecurefunc(vehicleTex, "Show", function(self)
                local db = addon and addon.db and addon.db.profile
                local unitFrames = db and rawget(db, "unitFrames") or nil
                local cfgP = unitFrames and rawget(unitFrames, "Player") or nil
                if cfgP and cfgP.useCustomBorders == true then
                    if self.Hide then pcall(self.Hide, self) end
                end
            end)
        end

        -- AlternatePowerFrameTexture Show() hook
        local altTex = container and container.AlternatePowerFrameTexture
        if altTex and not getProp(altTex, "showHooked") then
            setProp(altTex, "showHooked", true)
            hooksecurefunc(altTex, "Show", function(self)
                local db = addon and addon.db and addon.db.profile
                local unitFrames = db and rawget(db, "unitFrames") or nil
                local cfgP = unitFrames and rawget(unitFrames, "Player") or nil
                if cfgP and cfgP.useCustomBorders == true then
                    if self.Hide then pcall(self.Hide, self) end
                end
            end)
        end
    end

    -- Pre-emptive hiding and alpha hooks are now provided by the Preemptive module
    addon.PreemptiveHideTargetElements = Preemptive.hideTargetElements
    addon.PreemptiveHideFocusElements = Preemptive.hideFocusElements
    addon.PreemptiveHideBossElements = Preemptive.hideBossElements
    addon.InstallEarlyUnitFrameAlphaHooks = Preemptive.installEarlyAlphaHooks
    addon.InstallBossFrameHooks = Preemptive.installBossFrameHooks

    -- Note: Portal/Vehicle event handlers for power bar custom positioning have been
    -- removed. The Custom Position feature is deprecated in favor of PRD (Personal
    -- Resource Display) with Edit Mode positioning.

end

-- Note: Raid Frame Health Bar Styling and Overlay have been moved to bars/raidframes.lua
-- The module provides: addon.ApplyRaidFrameHealthBarStyle, addon.ApplyRaidFrameHealthOverlays,
-- addon.RestoreRaidFrameHealthOverlays

-- Note: Raid Frame Text Styling has been moved to bars/raidframes.lua
-- The module provides: addon.ApplyRaidFrameTextStyle, addon.ApplyRaidFrameNameOverlays,
-- addon.RestoreRaidFrameNameOverlays, addon.ApplyRaidFrameStatusTextStyle, addon.ApplyRaidFrameGroupTitlesStyle


-- Note: Party Frame Health Bar Styling and Overlay have been moved to bars/partyframes.lua
-- The module provides: addon.ApplyPartyFrameHealthBarStyle, addon.ApplyPartyFrameHealthOverlays,
-- addon.RestorePartyFrameHealthOverlays

-- Note: Party Frame Text Styling has been moved to bars/partyframes.lua
-- The module provides: addon.ApplyPartyFrameTextStyle, addon.ApplyPartyFrameNameOverlays,
-- addon.RestorePartyFrameNameOverlays, addon.ApplyPartyFrameTitleStyle


-- Restore all party frames to stock Blizzard appearance (profile switch / category reset).

function addon.RestoreAllPartyFrameOverlays()
    -- Restore health bar overlays
    if addon.RestorePartyFrameHealthOverlays then
        addon.RestorePartyFrameHealthOverlays()
    end
    -- Restore name text overlays
    if addon.RestorePartyFrameNameOverlays then
        addon.RestorePartyFrameNameOverlays()
    end
end

-- Restore all raid frames to stock Blizzard appearance (profile switch / category reset).

function addon.RestoreAllRaidFrameOverlays()
    -- Restore health bar overlays
    if addon.RestoreRaidFrameHealthOverlays then
        addon.RestoreRaidFrameHealthOverlays()
    end
    -- Restore name text overlays
    if addon.RestoreRaidFrameNameOverlays then
        addon.RestoreRaidFrameNameOverlays()
    end
end

-- UNIT_HEALTH event handler for value-based health bar coloring.
-- Uses UnitHealthPercent(unit, false, colorCurve) for secret-safe color computation.

do
    -- Map unit tokens to their health bar frames
    -- Returns: bar, useDark (both nil if not using value-based color mode)
    local function getHealthBarForUnit(unit)
        local db = addon and addon.db and addon.db.profile
        local unitFrames = db and rawget(db, "unitFrames") or nil

        if unit == "player" then
            local cfg = unitFrames and rawget(unitFrames, "Player") or nil
            local colorMode = cfg and cfg.healthBarColorMode
            if not colorMode or (colorMode ~= "value" and colorMode ~= "valueDark") then return nil, nil end
            local hb = _G.PlayerFrame and _G.PlayerFrame.PlayerFrameContent
                and _G.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
                and _G.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
                and _G.PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
            return hb, (colorMode == "valueDark")
        elseif unit == "target" then
            local cfg = unitFrames and rawget(unitFrames, "Target") or nil
            local colorMode = cfg and cfg.healthBarColorMode
            if not colorMode or (colorMode ~= "value" and colorMode ~= "valueDark") then return nil, nil end
            local hb = _G.TargetFrame and _G.TargetFrame.TargetFrameContent
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
            return hb, (colorMode == "valueDark")
        elseif unit == "focus" then
            local cfg = unitFrames and rawget(unitFrames, "Focus") or nil
            local colorMode = cfg and cfg.healthBarColorMode
            if not colorMode or (colorMode ~= "value" and colorMode ~= "valueDark") then return nil, nil end
            local hb = _G.FocusFrame and _G.FocusFrame.TargetFrameContent
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
            return hb, (colorMode == "valueDark")
        elseif unit:match("^boss%d$") then
            local cfg = unitFrames and rawget(unitFrames, "Boss") or nil
            local colorMode = cfg and cfg.healthBarColorMode
            if not colorMode or (colorMode ~= "value" and colorMode ~= "valueDark") then return nil, nil end
            local bossIndex = tonumber(unit:match("^boss(%d)$"))
            if bossIndex and bossIndex >= 1 and bossIndex <= 5 then
                local bossFrame = _G["Boss" .. bossIndex .. "TargetFrame"]
                local hb = bossFrame and bossFrame.TargetFrameContent
                    and bossFrame.TargetFrameContent.TargetFrameContentMain
                    and bossFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                    and bossFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
                return hb, (colorMode == "valueDark")
            end
        elseif unit == "targettarget" then
            local cfg = unitFrames and rawget(unitFrames, "TargetOfTarget") or nil
            local colorMode = cfg and cfg.healthBarColorMode
            if not colorMode or (colorMode ~= "value" and colorMode ~= "valueDark") then return nil, nil end
            local tot = _G.TargetFrameToT
            return (tot and tot.HealthBar or nil), (colorMode == "valueDark")
        elseif unit == "focustarget" then
            local cfg = unitFrames and rawget(unitFrames, "FocusTarget") or nil
            local colorMode = cfg and cfg.healthBarColorMode
            if not colorMode or (colorMode ~= "value" and colorMode ~= "valueDark") then return nil, nil end
            local fot = _G.FocusFrameToT
            return (fot and fot.HealthBar or nil), (colorMode == "valueDark")
        end
    end

    -- Helper to get the value color overlay for a bar (if active)
    local function getValueColorOverlay(bar)
        local st = bar and addon.FrameState and addon.FrameState.Get(bar)
        if st and st.rectActive and st.valueColorOverlay then
            return st.valueColorOverlay
        end
    end

    -- UNIT_HEALTH event handler for value-based coloring
    -- Also register UNIT_MAXHEALTH and UNIT_HEAL_PREDICTION to catch edge cases:
    -- - UNIT_MAXHEALTH: When max health changes (buffs, potions that heal to cap)
    -- - UNIT_HEAL_PREDICTION: Incoming heal updates that may affect display
    -- This fixes "stuck colors" when healing to exactly 100% (no subsequent UNIT_HEALTH fires)
    local healthColorEventFrame = CreateFrame("Frame")
    healthColorEventFrame:RegisterEvent("UNIT_HEALTH")
    healthColorEventFrame:RegisterEvent("UNIT_MAXHEALTH")
    healthColorEventFrame:RegisterEvent("UNIT_HEAL_PREDICTION")
    healthColorEventFrame:SetScript("OnEvent", function(self, event, unit)
        if not unit then return end

        local bar, useDark = getHealthBarForUnit(unit)
        if not bar then return end

        -- Apply value-based color using the color curve
        -- Use the overlay texture if available (cleaner than modifying Blizzard's textures)
        if addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
            local overlay = getValueColorOverlay(bar)
            addon.BarsTextures.applyValueBasedColor(bar, unit, overlay, useDark)

            -- Schedule reapply loop to catch timing edge cases (stuck colors at 100%)
            -- UnitHealthPercent can have timing lag, so we reapply at multiple intervals
            if addon.BarsTextures.scheduleColorValidation then
                addon.BarsTextures.scheduleColorValidation(bar, unit, overlay, useDark)
            end
        end
    end)

    -- Also register for PLAYER_TARGET_CHANGED and PLAYER_FOCUS_CHANGED
    -- to apply initial color when target/focus changes
    healthColorEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    healthColorEventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    healthColorEventFrame:HookScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_TARGET_CHANGED" then
            local bar, useDark = getHealthBarForUnit("target")
            if bar and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                local overlay = getValueColorOverlay(bar)
                addon.BarsTextures.applyValueBasedColor(bar, "target", overlay, useDark)
            end
        elseif event == "PLAYER_FOCUS_CHANGED" then
            local bar, useDark = getHealthBarForUnit("focus")
            if bar and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                local overlay = getValueColorOverlay(bar)
                addon.BarsTextures.applyValueBasedColor(bar, "focus", overlay, useDark)
            end
        end
    end)

    -- SetValue hooks for instant color updates (bypasses UNIT_HEALTH event delay)
    -- SetValue fires immediately when health changes, providing zero-delay response.
    local function hookSetValueForValueColor(bar, unitKey, unitToken)
        if not bar or not bar.SetValue then return end
        local barState = addon.FrameState and addon.FrameState.Get(bar)
        if barState and barState.valueColorSetValueHooked then return end
        if barState then barState.valueColorSetValueHooked = true end

        hooksecurefunc(bar, "SetValue", function(self)
            local cfg = addon.db and addon.db.profile
            cfg = cfg and cfg.unitFrames and cfg.unitFrames[unitKey]
            local colorMode = cfg and cfg.healthBarColorMode
            if colorMode == "value" or colorMode == "valueDark" then
                local useDark = (colorMode == "valueDark")
                if addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                    local overlay = getValueColorOverlay(self)
                    addon.BarsTextures.applyValueBasedColor(self, unitToken, overlay, useDark)

                    -- Schedule reapply loop to catch timing edge cases (stuck colors at 100%)
                    -- UnitHealthPercent can have timing lag, so we reapply at multiple intervals
                    if addon.BarsTextures.scheduleColorValidation then
                        addon.BarsTextures.scheduleColorValidation(self, unitToken, overlay, useDark)
                    end
                end
            end
        end)
    end

    -- Apply SetValue hooks after a short delay to ensure frames exist
    C_Timer.After(1, function()
        -- Player
        local playerHB = PlayerFrame and PlayerFrame.PlayerFrameContent
            and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
            and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
            and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
        if playerHB then
            hookSetValueForValueColor(playerHB, "Player", "player")
        end

        -- Target
        local targetHB = TargetFrame and TargetFrame.TargetFrameContent
            and TargetFrame.TargetFrameContent.TargetFrameContentMain
            and TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
            and TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
        if targetHB then
            hookSetValueForValueColor(targetHB, "Target", "target")
        end

        -- Focus
        local focusHB = FocusFrame and FocusFrame.TargetFrameContent
            and FocusFrame.TargetFrameContent.TargetFrameContentMain
            and FocusFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
            and FocusFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
        if focusHB then
            hookSetValueForValueColor(focusHB, "Focus", "focus")
        end

        -- Boss frames (1-5)
        for i = 1, 5 do
            local bossFrame = _G["Boss" .. i .. "TargetFrame"]
            local bossHB = bossFrame and bossFrame.TargetFrameContent
                and bossFrame.TargetFrameContent.TargetFrameContentMain
                and bossFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
                and bossFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
            if bossHB then
                hookSetValueForValueColor(bossHB, "Boss", "boss" .. i)
            end
        end

        -- TargetOfTarget
        local totHB = TargetFrameToT and TargetFrameToT.HealthBar
        if totHB then
            hookSetValueForValueColor(totHB, "TargetOfTarget", "targettarget")
        end

        -- FocusTarget
        local fotHB = FocusFrameToT and FocusFrameToT.HealthBar
        if fotHB then
            hookSetValueForValueColor(fotHB, "FocusTarget", "focustarget")
        end

        -- Hook RefreshOpacityState to re-apply value-based colors after opacity changes.
        -- This ensures color persists through opacity transitions (e.g., 20% -> 100% when target acquired).
        if addon.RefreshOpacityState and not addon._valueColorOpacityHooked then
            addon._valueColorOpacityHooked = true
            hooksecurefunc(addon, "RefreshOpacityState", function()
                -- Slightly defer to ensure opacity change is complete
                C_Timer.After(0.01, function()
                    local unitMappings = {
                        { key = "Player", token = "player" },
                        { key = "Target", token = "target" },
                        { key = "Focus", token = "focus" },
                        { key = "TargetOfTarget", token = "targettarget" },
                        { key = "FocusTarget", token = "focustarget" },
                    }
                    for _, mapping in ipairs(unitMappings) do
                        local cfg = addon.db and addon.db.profile
                            and addon.db.profile.unitFrames
                            and addon.db.profile.unitFrames[mapping.key]
                        local colorMode = cfg and cfg.healthBarColorMode
                        if colorMode == "value" or colorMode == "valueDark" then
                            local bar, useDark = getHealthBarForUnit(mapping.token)
                            if bar and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                                local overlay = getValueColorOverlay(bar)
                                addon.BarsTextures.applyValueBasedColor(bar, mapping.token, overlay, useDark)
                            end
                        end
                    end
                    -- Boss frames
                    local bossCfg = addon.db and addon.db.profile
                        and addon.db.profile.unitFrames
                        and addon.db.profile.unitFrames.Boss
                    local bossColorMode = bossCfg and bossCfg.healthBarColorMode
                    if bossColorMode == "value" or bossColorMode == "valueDark" then
                        local useDark = (bossColorMode == "valueDark")
                        for i = 1, 5 do
                            local bar = getHealthBarForUnit("boss" .. i)
                            if bar and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
                                local overlay = getValueColorOverlay(bar)
                                addon.BarsTextures.applyValueBasedColor(bar, "boss" .. i, overlay, useDark)
                            end
                        end
                    end
                end)
            end)
        end

    end)
end

