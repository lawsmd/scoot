--------------------------------------------------------------------------------
-- bars/preemptive.lua
-- Pre-emptive hiding functions and early hook installation
--
-- These functions hide elements BEFORE Blizzard's Update runs, preventing
-- visual "flashes" that occur when relying solely on post-update hooks.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Get modules
local Resolvers = addon.BarsResolvers
local Alpha = addon.BarsAlpha

-- Reference to FrameState module for safe property storage (avoids writing to Blizzard frames)
local FS = addon.FrameState

local function getState(frame)
    return FS.Get(frame)
end

-- Create module namespace
addon.BarsPreemptive = addon.BarsPreemptive or {}
local Preemptive = addon.BarsPreemptive

--------------------------------------------------------------------------------
-- Pre-emptive Hiding for Target/Focus Frame Elements
--------------------------------------------------------------------------------
-- Called SYNCHRONOUSLY from PLAYER_TARGET_CHANGED and PLAYER_FOCUS_CHANGED
-- event handlers. Hides elements BEFORE Blizzard's TargetFrame_Update runs.

-- Direct upvalue to the event-driven guard (editmode/core.lua loads first in TOC)
local isEditModeActive = addon.EditMode.IsEditModeActiveOrOpening

-- Pre-emptive hide for Target frame elements (ReputationColor, FrameTexture, Flash)
-- Runs SYNCHRONOUSLY from PLAYER_TARGET_CHANGED, BEFORE Blizzard's TargetFrame_Update.
-- The texture might not exist yet at this moment, so a micro-delay follow-up is also scheduled.
function Preemptive.hideTargetElements()
    local db = addon and addon.db and addon.db.profile
    local unitFrames = db and rawget(db, "unitFrames")
    local cfg = unitFrames and rawget(unitFrames, "Target")
    if not cfg then
        -- Post-reload the texture defaults to alpha 1, so a silently missed hide
        -- here leaves the banner visible until the next target change. The
        -- retries scheduled by PLAYER_ENTERING_WORLD / PLAYER_TARGET_CHANGED
        -- cover this window; the trace records that it happened.
        if addon.RepColorTrace then addon.RepColorTrace("hideTarget", "bail: cfg unreadable") end
        return
    end

    -- Shared computeAlpha for enforcers - re-reads config each call.
    -- Returns nil when config is unreadable so enforcers SKIP instead of
    -- restoring alpha 1 during transient windows (profile/layout sync).
    local function computeAlpha()
        local db2 = addon and addon.db and addon.db.profile
        local unitFrames2 = db2 and rawget(db2, "unitFrames")
        local cfg2 = unitFrames2 and rawget(unitFrames2, "Target")
        if not cfg2 then return nil end
        return cfg2.useCustomBorders and 0 or 1
    end

    -- Helper to hide ReputationColor and install enforcer
    local function hideRepColor()
        local repColor = _G.TargetFrame and _G.TargetFrame.TargetFrameContent
            and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
            and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
        if repColor and repColor.SetAlpha then
            pcall(repColor.SetAlpha, repColor, 0)
            if Alpha and Alpha.hookAlphaEnforcer then
                Alpha.hookAlphaEnforcer(repColor, computeAlpha)
            end
        end
    end

    -- Only hide if useCustomBorders is enabled
    if cfg.useCustomBorders then
        -- Immediate hide (texture may not exist yet)
        hideRepColor()
        if addon.RepColorTrace then addon.RepColorTrace("hideTarget", "hide pass applied") end

        -- Hide frame texture immediately
        local ft = Resolvers.resolveUnitFrameFrameTexture("Target")
        if ft and ft.SetAlpha then
            pcall(ft.SetAlpha, ft, 0)
        end

        -- Hide Flash (aggro/threat glow) immediately
        local targetFlash = _G.TargetFrame and _G.TargetFrame.TargetFrameContainer
            and _G.TargetFrame.TargetFrameContainer.Flash
        if targetFlash and targetFlash.SetAlpha then
            pcall(targetFlash.SetAlpha, targetFlash, 0)
        end

        -- Schedule a micro-delay follow-up to catch the texture if Blizzard creates it
        -- AFTER the synchronous pre-emptive hide but BEFORE the main deferred styling pass.
        -- This closes the timing gap where ReputationColor becomes visible briefly.
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, hideRepColor)
        end
    end

    -- Hide frame texture if healthBarHideBorder is enabled (separate from useCustomBorders)
    if cfg.healthBarHideBorder then
        local ft = Resolvers.resolveUnitFrameFrameTexture("Target")
        if ft and ft.SetAlpha then
            pcall(ft.SetAlpha, ft, 0)
        end
    end
end

-- Pre-emptive hide for Focus frame elements (ReputationColor, FrameTexture, Flash)
-- Runs SYNCHRONOUSLY from PLAYER_FOCUS_CHANGED, BEFORE Blizzard's FocusFrame_Update.
-- The texture might not exist yet at this moment, so a micro-delay follow-up is also scheduled.
function Preemptive.hideFocusElements()
    local db = addon and addon.db and addon.db.profile
    local unitFrames = db and rawget(db, "unitFrames")
    local cfg = unitFrames and rawget(unitFrames, "Focus")
    if not cfg then
        if addon.RepColorTrace then addon.RepColorTrace("hideFocus", "bail: cfg unreadable") end
        return
    end

    -- Shared computeAlpha for enforcers - re-reads config each call.
    -- nil = config unreadable: enforcers skip instead of restoring alpha 1.
    local function computeAlpha()
        local db2 = addon and addon.db and addon.db.profile
        local unitFrames2 = db2 and rawget(db2, "unitFrames")
        local cfg2 = unitFrames2 and rawget(unitFrames2, "Focus")
        if not cfg2 then return nil end
        return cfg2.useCustomBorders and 0 or 1
    end

    -- Helper to hide ReputationColor and install enforcer
    local function hideRepColor()
        local repColor = _G.FocusFrame and _G.FocusFrame.TargetFrameContent
            and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
            and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
        if repColor and repColor.SetAlpha then
            pcall(repColor.SetAlpha, repColor, 0)
            if Alpha and Alpha.hookAlphaEnforcer then
                Alpha.hookAlphaEnforcer(repColor, computeAlpha)
            end
        end
    end

    -- Only hide if useCustomBorders is enabled
    if cfg.useCustomBorders then
        -- Immediate hide (texture may not exist yet)
        hideRepColor()
        if addon.RepColorTrace then addon.RepColorTrace("hideFocus", "hide pass applied") end

        -- Hide frame texture immediately
        local ft = Resolvers.resolveUnitFrameFrameTexture("Focus")
        if ft and ft.SetAlpha then
            pcall(ft.SetAlpha, ft, 0)
        end

        -- Hide Flash (aggro/threat glow) immediately
        local focusFlash = _G.FocusFrame and _G.FocusFrame.TargetFrameContainer
            and _G.FocusFrame.TargetFrameContainer.Flash
        if focusFlash and focusFlash.SetAlpha then
            pcall(focusFlash.SetAlpha, focusFlash, 0)
        end

        -- Schedule a micro-delay follow-up to catch the texture if Blizzard creates it
        -- AFTER the synchronous pre-emptive hide but BEFORE the main deferred styling pass.
        -- This closes the timing gap where ReputationColor becomes visible briefly.
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, hideRepColor)
        end
    end

    -- Hide frame texture if healthBarHideBorder is enabled (separate from useCustomBorders)
    if cfg.healthBarHideBorder then
        local ft = Resolvers.resolveUnitFrameFrameTexture("Focus")
        if ft and ft.SetAlpha then
            pcall(ft.SetAlpha, ft, 0)
        end
    end
end

--------------------------------------------------------------------------------
-- Early Alpha Hook Installation
--------------------------------------------------------------------------------
-- Install alpha enforcement hooks on Target/Focus frame elements during
-- PLAYER_ENTERING_WORLD, BEFORE the first target is acquired.

function Preemptive.installEarlyAlphaHooks()
    -- Helper to compute alpha based on useCustomBorders setting.
    -- nil = config unreadable: enforcers skip instead of restoring alpha 1
    -- (the explicit restore lives in the settings-driven pass in bars.lua).
    local function makeComputeAlpha(unit)
        return function()
            local db2 = addon and addon.db and addon.db.profile
            local unitFrames2 = db2 and rawget(db2, "unitFrames")
            local cfg2 = unitFrames2 and rawget(unitFrames2, unit)
            if not cfg2 then return nil end
            return cfg2.useCustomBorders and 0 or 1
        end
    end

    local function makeComputeAlphaWithBorder(unit)
        return function()
            local db2 = addon and addon.db and addon.db.profile
            local unitFrames2 = db2 and rawget(db2, "unitFrames")
            local cfg2 = unitFrames2 and rawget(unitFrames2, unit)
            if not cfg2 then return nil end
            return (cfg2.useCustomBorders or cfg2.healthBarHideBorder) and 0 or 1
        end
    end

    -- Target frame elements
    do
        -- ReputationColor
        local targetRepColor = _G.TargetFrame and _G.TargetFrame.TargetFrameContent
            and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
            and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
        if targetRepColor then
            Alpha.hookAlphaEnforcer(targetRepColor, makeComputeAlpha("Target"))
        end

        -- FrameTexture
        local targetFT = Resolvers.resolveUnitFrameFrameTexture("Target")
        if targetFT then
            Alpha.hookAlphaEnforcer(targetFT, makeComputeAlphaWithBorder("Target"))
        end

        -- Flash (aggro/threat glow)
        local targetFlash = _G.TargetFrame and _G.TargetFrame.TargetFrameContainer
            and _G.TargetFrame.TargetFrameContainer.Flash
        if targetFlash then
            Alpha.hookAlphaEnforcer(targetFlash, makeComputeAlpha("Target"))
        end
    end

    -- Focus frame elements
    do
        -- ReputationColor
        local focusRepColor = _G.FocusFrame and _G.FocusFrame.TargetFrameContent
            and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
            and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
        if focusRepColor then
            Alpha.hookAlphaEnforcer(focusRepColor, makeComputeAlpha("Focus"))
        end

        -- FrameTexture
        local focusFT = Resolvers.resolveUnitFrameFrameTexture("Focus")
        if focusFT then
            Alpha.hookAlphaEnforcer(focusFT, makeComputeAlphaWithBorder("Focus"))
        end

        -- Flash (aggro/threat glow)
        local focusFlash = _G.FocusFrame and _G.FocusFrame.TargetFrameContainer
            and _G.FocusFrame.TargetFrameContainer.Flash
        if focusFlash then
            Alpha.hookAlphaEnforcer(focusFlash, makeComputeAlpha("Focus"))
        end
    end

    -- Also do initial hide pass for currently configured settings
    Preemptive.hideTargetElements()
    Preemptive.hideFocusElements()

    -- Re-assert after faction updates via addon-owned unit events.
    -- (Replaces pre-12.0 hooks on the TargetFrame_Update/FocusFrame_Update
    -- globals, which no longer exist in 12.0 — those blocks were dead code.)
    -- RegisterUnitEvent filters units C-side, so the handler never compares
    -- unit tokens (frame-wide unit events can deliver secret tokens).
    if not addon._ScootRepColorFactionWatch and _G.C_Timer and _G.C_Timer.After then
        addon._ScootRepColorFactionWatch = true

        local targetWatch = CreateFrame("Frame")
        targetWatch:RegisterUnitEvent("UNIT_FACTION", "target", "player")
        targetWatch:SetScript("OnEvent", function()
            _G.C_Timer.After(0, function()
                if isEditModeActive() then return end
                -- A "player" faction change also drives Focus when focus is the player.
                Preemptive.hideTargetElements()
                Preemptive.hideFocusElements()
            end)
        end)

        local focusWatch = CreateFrame("Frame")
        focusWatch:RegisterUnitEvent("UNIT_FACTION", "focus")
        focusWatch:SetScript("OnEvent", function()
            _G.C_Timer.After(0, function()
                if isEditModeActive() then return end
                Preemptive.hideFocusElements()
            end)
        end)
    end

    --------------------------------------------------------------------------------
    -- CRITICAL: Hook CheckFaction method directly on TargetFrame/FocusFrame
    --------------------------------------------------------------------------------
    -- When UNIT_FACTION fires (e.g., neutral mob becomes hostile), Blizzard calls
    -- CheckFaction() and CheckLevel() DIRECTLY - NOT through Update(). This means
    -- the TargetFrame_Update hook never fires. These methods must be hooked directly.

    -- Helper to re-hide elements after CheckFaction/CheckLevel
    -- Handles ReputationColor, Flash, AND LevelText/NameText
    local function rehideTargetElements()
        if isEditModeActive() then return end
        local db = addon and addon.db and addon.db.profile
        local unitFrames = db and rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, "Target")
        if not cfg then return end

        -- Re-hide ReputationColor (if useCustomBorders is enabled)
        if cfg.useCustomBorders then
            local repColor = _G.TargetFrame and _G.TargetFrame.TargetFrameContent
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
            if repColor and repColor.SetAlpha then
                pcall(repColor.SetAlpha, repColor, 0)
                if Alpha and Alpha.hookAlphaEnforcer then
                    Alpha.hookAlphaEnforcer(repColor, makeComputeAlpha("Target"))
                end
            end

            -- Re-hide Flash (threat glow)
            local flash = _G.TargetFrame and _G.TargetFrame.TargetFrameContainer
                and _G.TargetFrame.TargetFrameContainer.Flash
            if flash and flash.SetAlpha then
                pcall(flash.SetAlpha, flash, 0)
                if Alpha and Alpha.hookAlphaEnforcer then
                    Alpha.hookAlphaEnforcer(flash, makeComputeAlpha("Target"))
                end
            end
        end

        -- Re-hide LevelText (if levelTextHidden is enabled)
        -- CheckLevel() calls levelText:Show() which overrides the hidden state
        if cfg.levelTextHidden == true then
            local levelFS = _G.TargetFrame and _G.TargetFrame.TargetFrameContent
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.LevelText
            if levelFS and levelFS.SetShown then
                pcall(levelFS.SetShown, levelFS, false)
            end
        end

        -- Re-hide NameText (if nameTextHidden is enabled)
        if cfg.nameTextHidden == true then
            local nameFS = _G.TargetFrame and _G.TargetFrame.TargetFrameContent
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
                and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.Name
            if nameFS and nameFS.SetShown then
                pcall(nameFS.SetShown, nameFS, false)
            end
        end
    end

    local function rehideFocusElements()
        if isEditModeActive() then return end
        local db = addon and addon.db and addon.db.profile
        local unitFrames = db and rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, "Focus")
        if not cfg then return end

        -- Re-hide ReputationColor (if useCustomBorders is enabled)
        if cfg.useCustomBorders then
            local repColor = _G.FocusFrame and _G.FocusFrame.TargetFrameContent
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
            if repColor and repColor.SetAlpha then
                pcall(repColor.SetAlpha, repColor, 0)
                if Alpha and Alpha.hookAlphaEnforcer then
                    Alpha.hookAlphaEnforcer(repColor, makeComputeAlpha("Focus"))
                end
            end

            -- Re-hide Flash (threat glow)
            local flash = _G.FocusFrame and _G.FocusFrame.TargetFrameContainer
                and _G.FocusFrame.TargetFrameContainer.Flash
            if flash and flash.SetAlpha then
                pcall(flash.SetAlpha, flash, 0)
                if Alpha and Alpha.hookAlphaEnforcer then
                    Alpha.hookAlphaEnforcer(flash, makeComputeAlpha("Focus"))
                end
            end
        end

        -- Re-hide LevelText (if levelTextHidden is enabled)
        -- CheckLevel() calls levelText:Show() which overrides the hidden state
        if cfg.levelTextHidden == true then
            local levelFS = _G.FocusFrame and _G.FocusFrame.TargetFrameContent
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.LevelText
            if levelFS and levelFS.SetShown then
                pcall(levelFS.SetShown, levelFS, false)
            end
        end

        -- Re-hide NameText (if nameTextHidden is enabled)
        if cfg.nameTextHidden == true then
            local nameFS = _G.FocusFrame and _G.FocusFrame.TargetFrameContent
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
                and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.Name
            if nameFS and nameFS.SetShown then
                pcall(nameFS.SetShown, nameFS, false)
            end
        end
    end

    -- Hook CheckFaction on TargetFrame (called when UNIT_FACTION fires)
    if _G.TargetFrame and _G.TargetFrame.CheckFaction and not addon._ScootTargetCheckFactionHooked then
        addon._ScootTargetCheckFactionHooked = true
        _G.hooksecurefunc(_G.TargetFrame, "CheckFaction", rehideTargetElements)
    end

    -- Hook CheckLevel on TargetFrame (also called when UNIT_FACTION fires)
    if _G.TargetFrame and _G.TargetFrame.CheckLevel and not addon._ScootTargetCheckLevelHooked then
        addon._ScootTargetCheckLevelHooked = true
        _G.hooksecurefunc(_G.TargetFrame, "CheckLevel", rehideTargetElements)
    end

    -- Hook CheckFaction on FocusFrame
    if _G.FocusFrame and _G.FocusFrame.CheckFaction and not addon._ScootFocusCheckFactionHooked then
        addon._ScootFocusCheckFactionHooked = true
        _G.hooksecurefunc(_G.FocusFrame, "CheckFaction", rehideFocusElements)
    end

    -- Hook CheckLevel on FocusFrame
    if _G.FocusFrame and _G.FocusFrame.CheckLevel and not addon._ScootFocusCheckLevelHooked then
        addon._ScootFocusCheckLevelHooked = true
        _G.hooksecurefunc(_G.FocusFrame, "CheckLevel", rehideFocusElements)
    end

    --------------------------------------------------------------------------------
    -- Hook SetVertexColor on ReputationColor for extra coverage
    --------------------------------------------------------------------------------
    -- CheckFaction calls SetVertexColor to change the reputation strip color.
    -- If Blizzard changes the color, it means the texture is being updated,
    -- so alpha hiding should be re-enforced.

    local targetRepColor = _G.TargetFrame and _G.TargetFrame.TargetFrameContent
        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain
        and _G.TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
    local targetState = getState(targetRepColor)
    if targetRepColor and targetRepColor.SetVertexColor and not (targetState and targetState.repColorSetVertexColorHooked) then
        if targetState then targetState.repColorSetVertexColorHooked = true end
        _G.hooksecurefunc(targetRepColor, "SetVertexColor", function(self)
            if isEditModeActive() then return end
            local db = addon and addon.db and addon.db.profile
            local unitFrames = db and rawget(db, "unitFrames")
            local cfg = unitFrames and rawget(unitFrames, "Target")
            if cfg and cfg.useCustomBorders and self and self.SetAlpha then
                pcall(self.SetAlpha, self, 0)
            end
        end)
    end

    local focusRepColor = _G.FocusFrame and _G.FocusFrame.TargetFrameContent
        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain
        and _G.FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
    local focusState = getState(focusRepColor)
    if focusRepColor and focusRepColor.SetVertexColor and not (focusState and focusState.repColorSetVertexColorHooked) then
        if focusState then focusState.repColorSetVertexColorHooked = true end
        _G.hooksecurefunc(focusRepColor, "SetVertexColor", function(self)
            if isEditModeActive() then return end
            local db = addon and addon.db and addon.db.profile
            local unitFrames = db and rawget(db, "unitFrames")
            local cfg = unitFrames and rawget(unitFrames, "Focus")
            if cfg and cfg.useCustomBorders and self and self.SetAlpha then
                pcall(self.SetAlpha, self, 0)
            end
        end)
    end
end

--------------------------------------------------------------------------------
-- Pre-emptive Hiding for Boss Frame Elements
--------------------------------------------------------------------------------
-- Boss frames (Boss1TargetFrame through Boss5TargetFrame) can appear/update
-- during combat. Unlike Target/Focus which have dedicated PLAYER_X_CHANGED events,
-- Boss frames update via INSTANCE_ENCOUNTER_ENGAGE_UNIT and UPDATE_BOSS_FRAMES.
-- These events fire during combat, but the handlers currently skip applying
-- during combat lockdown. These functions provide direct hooks to catch updates.

-- Pre-emptive hide for all Boss frame elements (ReputationColor, FrameTexture, Flash)
function Preemptive.hideBossElements()
    local db = addon and addon.db and addon.db.profile
    local unitFrames = db and rawget(db, "unitFrames")
    local cfg = unitFrames and rawget(unitFrames, "Boss")
    if not cfg then return end

    -- Shared computeAlpha for enforcers - re-reads config each call.
    -- nil = config unreadable: enforcers skip instead of restoring alpha 1.
    local function computeAlpha()
        local db2 = addon and addon.db and addon.db.profile
        local unitFrames2 = db2 and rawget(db2, "unitFrames")
        local cfg2 = unitFrames2 and rawget(unitFrames2, "Boss")
        if not cfg2 then return nil end
        return cfg2.useCustomBorders and 0 or 1
    end

    local function computeAlphaWithBorder()
        local db2 = addon and addon.db and addon.db.profile
        local unitFrames2 = db2 and rawget(db2, "unitFrames")
        local cfg2 = unitFrames2 and rawget(unitFrames2, "Boss")
        if not cfg2 then return nil end
        return (cfg2.useCustomBorders or cfg2.healthBarHideBorder) and 0 or 1
    end

    -- Helper to hide ReputationColor on a specific Boss frame and install enforcer
    local function hideRepColorOnBoss(bossFrame)
        if not bossFrame then return end
        local repColor = bossFrame.TargetFrameContent
            and bossFrame.TargetFrameContent.TargetFrameContentMain
            and bossFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
        if repColor and repColor.SetAlpha then
            pcall(repColor.SetAlpha, repColor, 0)
            if Alpha and Alpha.hookAlphaEnforcer then
                Alpha.hookAlphaEnforcer(repColor, computeAlpha)
            end
        end
    end

    -- Only hide if useCustomBorders is enabled
    if cfg.useCustomBorders then
        for i = 1, addon.NUM_BOSS_FRAMES do
            local bossFrame = addon.GetBossFrame(i)
            if bossFrame then
                -- Hide ReputationColor immediately
                hideRepColorOnBoss(bossFrame)

                -- Hide FrameTexture immediately
                local ft = bossFrame.TargetFrameContainer and bossFrame.TargetFrameContainer.FrameTexture
                if ft and ft.SetAlpha then
                    pcall(ft.SetAlpha, ft, 0)
                    if Alpha and Alpha.hookAlphaEnforcer then
                        Alpha.hookAlphaEnforcer(ft, computeAlphaWithBorder)
                    end
                end

                -- Hide Flash (aggro/threat glow) immediately
                local flash = bossFrame.TargetFrameContainer and bossFrame.TargetFrameContainer.Flash
                if flash and flash.SetAlpha then
                    pcall(flash.SetAlpha, flash, 0)
                    if Alpha and Alpha.hookAlphaEnforcer then
                        Alpha.hookAlphaEnforcer(flash, computeAlpha)
                    end
                end
            end
        end

        -- Schedule a micro-delay follow-up to catch textures if Blizzard creates them
        -- AFTER the synchronous pre-emptive hide
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, function()
                addon.ForEachBossFrame(hideRepColorOnBoss)
            end)
        end
    end

    -- Hide frame texture if healthBarHideBorder is enabled (separate from useCustomBorders)
    if cfg.healthBarHideBorder then
        for i = 1, addon.NUM_BOSS_FRAMES do
            local bossFrame = addon.GetBossFrame(i)
            if bossFrame then
                local ft = bossFrame.TargetFrameContainer and bossFrame.TargetFrameContainer.FrameTexture
                if ft and ft.SetAlpha then
                    pcall(ft.SetAlpha, ft, 0)
                end
            end
        end
    end

    -- Hide health bar fill/background when texture-only hiding is enabled
    -- (keeps text overlays visible). Uses pcall + hooksecurefunc internally = combat-safe.
    if cfg.healthBarHideTextureOnly then
        local Util = addon.ComponentsUtil
        if Util and Util.SetHealthBarTextureOnlyHidden then
            for i = 1, addon.NUM_BOSS_FRAMES do
                local bossFrame = addon.GetBossFrame(i)
                if bossFrame then
                    local hb = bossFrame.healthbar
                    if hb then
                        Util.SetHealthBarTextureOnlyHidden(hb, true)
                    end
                end
            end
            -- Follow-up for late frame construction (matches ReputationColor pattern)
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    local db2 = addon and addon.db and addon.db.profile
                    local uf2 = db2 and rawget(db2, "unitFrames")
                    local cfg2 = uf2 and rawget(uf2, "Boss")
                    if not cfg2 or not cfg2.healthBarHideTextureOnly then return end
                    local Util2 = addon.ComponentsUtil
                    if not Util2 or not Util2.SetHealthBarTextureOnlyHidden then return end
                    addon.ForEachBossFrame(function(bf)
                        if bf.healthbar then
                            Util2.SetHealthBarTextureOnlyHidden(bf.healthbar, true)
                        end
                    end)
                end)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Boss Frame Hook Installation
--------------------------------------------------------------------------------
-- Install hooks on Boss frame methods to catch updates during combat.

function Preemptive.installBossFrameHooks()
    -- nil = config unreadable: enforcers skip instead of restoring alpha 1.
    local function makeComputeAlpha()
        return function()
            local db2 = addon and addon.db and addon.db.profile
            local unitFrames2 = db2 and rawget(db2, "unitFrames")
            local cfg2 = unitFrames2 and rawget(unitFrames2, "Boss")
            if not cfg2 then return nil end
            return cfg2.useCustomBorders and 0 or 1
        end
    end

    -- Helper to re-hide Boss elements after Blizzard updates
    local function rehideBossElements()
        local db = addon and addon.db and addon.db.profile
        local unitFrames = db and rawget(db, "unitFrames")
        local cfg = unitFrames and rawget(unitFrames, "Boss")
        if not cfg then return end

        for i = 1, addon.NUM_BOSS_FRAMES do
            local bossFrame = addon.GetBossFrame(i)
            if bossFrame then
                if cfg.useCustomBorders then
                    -- Re-hide ReputationColor
                    local repColor = bossFrame.TargetFrameContent
                        and bossFrame.TargetFrameContent.TargetFrameContentMain
                        and bossFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
                    if repColor and repColor.SetAlpha then
                        pcall(repColor.SetAlpha, repColor, 0)
                        if Alpha and Alpha.hookAlphaEnforcer then
                            Alpha.hookAlphaEnforcer(repColor, makeComputeAlpha())
                        end
                    end

                    -- Re-hide Flash
                    local flash = bossFrame.TargetFrameContainer
                        and bossFrame.TargetFrameContainer.Flash
                    if flash and flash.SetAlpha then
                        pcall(flash.SetAlpha, flash, 0)
                    end
                end

                -- Re-hide health bar fill if texture-only hiding is enabled
                if cfg.healthBarHideTextureOnly then
                    local Util = addon.ComponentsUtil
                    if Util and Util.SetHealthBarTextureOnlyHidden then
                        local hb = bossFrame.healthbar
                        if hb then
                            Util.SetHealthBarTextureOnlyHidden(hb, true)
                        end
                    end
                end

                -- Re-hide power bar fill if texture-only hiding is enabled
                if cfg.powerBarHideTextureOnly then
                    local Util = addon.ComponentsUtil
                    if Util and Util.SetPowerBarTextureOnlyHidden then
                        local pb = bossFrame.TargetFrameContent
                            and bossFrame.TargetFrameContent.TargetFrameContentMain
                            and bossFrame.TargetFrameContent.TargetFrameContentMain.ManaBar
                        if pb then
                            Util.SetPowerBarTextureOnlyHidden(pb, true)
                        end
                    end
                end

                -- Re-hide LevelText (CheckLevel() calls levelText:Show() and undoes the hide)
                if cfg.levelTextHidden == true then
                    local levelFS = bossFrame.TargetFrameContent
                        and bossFrame.TargetFrameContent.TargetFrameContentMain
                        and bossFrame.TargetFrameContent.TargetFrameContentMain.LevelText
                    if levelFS and levelFS.SetShown then
                        pcall(levelFS.SetShown, levelFS, false)
                    end
                end

                -- Re-hide NameText (for symmetry with Target/Focus)
                if cfg.nameTextHidden == true then
                    local nameFS = bossFrame.TargetFrameContent
                        and bossFrame.TargetFrameContent.TargetFrameContentMain
                        and bossFrame.TargetFrameContent.TargetFrameContentMain.Name
                    if nameFS and nameFS.SetShown then
                        pcall(nameFS.SetShown, nameFS, false)
                    end
                end
            end
        end
    end

    -- Install hooks on individual Boss frames
    for i = 1, addon.NUM_BOSS_FRAMES do
        local bossFrame = addon.GetBossFrame(i)
        if bossFrame then
            -- Hook OnShow to re-hide elements when the frame becomes visible
            local bossState = getState(bossFrame)
            if bossState and not bossState.bossOnShowHooked then
                bossState.bossOnShowHooked = true
                bossFrame:HookScript("OnShow", function()
                    -- Small delay to let Blizzard finish setting up the frame
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, rehideBossElements)
                    else
                        rehideBossElements()
                    end
                end)
            end

            -- Hook CheckFaction if it exists (called when faction/reputation updates)
            if bossFrame.CheckFaction and bossState and not bossState.bossCheckFactionHooked then
                bossState.bossCheckFactionHooked = true
                _G.hooksecurefunc(bossFrame, "CheckFaction", rehideBossElements)
            end

            -- Hook CheckLevel — fires when unit level info resolves. Adds often
            -- spawn before level is known, so CheckLevel() runs AFTER OnShow/Update
            -- and calls levelText:Show(), undoing the hide.
            if bossFrame.CheckLevel and bossState and not bossState.bossCheckLevelHooked then
                bossState.bossCheckLevelHooked = true
                _G.hooksecurefunc(bossFrame, "CheckLevel", function()
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, rehideBossElements)
                    else
                        rehideBossElements()
                    end
                end)
            end

            -- Hook SetVertexColor on ReputationColor for extra coverage
            local repColor = bossFrame.TargetFrameContent
                and bossFrame.TargetFrameContent.TargetFrameContentMain
                and bossFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor
            local repState = getState(repColor)
            if repColor and repColor.SetVertexColor and not (repState and repState.repColorSetVertexColorHooked) then
                if repState then repState.repColorSetVertexColorHooked = true end
                _G.hooksecurefunc(repColor, "SetVertexColor", function(self)
                    if isEditModeActive() then return end
                    local db = addon and addon.db and addon.db.profile
                    local unitFrames = db and rawget(db, "unitFrames")
                    local cfg = unitFrames and rawget(unitFrames, "Boss")
                    if cfg and cfg.useCustomBorders and self and self.SetAlpha then
                        pcall(self.SetAlpha, self, 0)
                    end
                end)
            end

            -- Install early alpha enforcer on ReputationColor
            if repColor then
                Alpha.hookAlphaEnforcer(repColor, makeComputeAlpha())
            end
        end
    end

    -- Hook BossTargetFrameContainer's UpdateShownState if available
    -- Called when boss frames are shown/hidden during encounters
    local container = _G.BossTargetFrameContainer
    if container and container.UpdateShownState and not addon._ScootBossContainerUpdateHooked then
        addon._ScootBossContainerUpdateHooked = true
        _G.hooksecurefunc(container, "UpdateShownState", function()
            -- Small delay to let Blizzard finish updating
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, rehideBossElements)
            else
                rehideBossElements()
            end
        end)
    end

    -- Do initial hide pass for currently configured settings
    Preemptive.hideBossElements()
end

-- Expose to addon namespace for backwards compatibility
addon.PreemptiveHideTargetElements = Preemptive.hideTargetElements
addon.PreemptiveHideFocusElements = Preemptive.hideFocusElements
addon.PreemptiveHideBossElements = Preemptive.hideBossElements
addon.InstallEarlyUnitFrameAlphaHooks = Preemptive.installEarlyAlphaHooks
addon.InstallBossFrameHooks = Preemptive.installBossFrameHooks
return Preemptive
