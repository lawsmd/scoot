--------------------------------------------------------------------------------
-- bars/partyframes/extras.lua
-- Party frame extras: role icons, event-based color updates, over-absorb glow,
-- texture visibility helpers, heal prediction visibility, absorb bars
-- visibility, and heal prediction clipping.
--
-- Loaded after partyframes/core.lua and partyframes/text.lua. Imports shared
-- state from addon.BarsPartyFrames.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Get modules
local Utils = addon.BarsUtils
local Combat = addon.BarsCombat

-- Get module namespace (created in core.lua)
local PartyFrames = addon.BarsPartyFrames

-- Import shared state from core.lua
local PartyFrameState = addon.BarsPartyFrames._PartyFrameState
local getState = addon.BarsPartyFrames._getState
local ensureState = addon.BarsPartyFrames._ensureState
local isEditModeActive = addon.BarsPartyFrames._isEditModeActive

--------------------------------------------------------------------------------
-- Apply Custom Role Icons for Party Frames
--------------------------------------------------------------------------------
-- Re-triggers Blizzard's CompactUnitFrame_UpdateRoleIcon on each party frame.
-- Blizzard sets the default atlas, then our post-hook swaps to the custom set.
-- Falls back to direct application if Blizzard's function errors (tainted widget).

function addon.ApplyPartyRoleIcons()
    local directApply = addon._applyCustomRoleIcon
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame and frame.roleIcon then
            if _G.CompactUnitFrame_UpdateRoleIcon then
                local ok = pcall(CompactUnitFrame_UpdateRoleIcon, frame)
                if not ok and directApply then
                    pcall(directApply, frame)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Event-Based Color Updates for Party Frames (Value Mode)
--------------------------------------------------------------------------------
-- The SetValue hook handles most color updates, but some edge cases require
-- explicit event handling:
-- - UNIT_MAXHEALTH: When max health changes (buffs, potions that heal to cap)
-- - UNIT_HEAL_PREDICTION: Incoming heal updates
-- - UNIT_HEALTH: Backup for any health changes the SetValue hook might miss
--
-- This fixes "stuck colors" when healing to exactly 100% where no subsequent
-- SetValue call might occur.
--------------------------------------------------------------------------------

local function isPartyUnit(unit)
    if not unit then return false end
    -- Include player since they can appear in party frames too
    return unit == "player" or unit == "party1" or unit == "party2" or unit == "party3" or unit == "party4"
end

local function getPartyHealthBarForUnit(unit)
    if not unit or not isPartyUnit(unit) then return nil, nil, nil end

    local db = addon and addon.db and addon.db.profile
    local groupFrames = db and rawget(db, "groupFrames") or nil
    local cfg = groupFrames and rawget(groupFrames, "party") or nil
    local colorMode = cfg and cfg.healthBarColorMode
    if not colorMode or (colorMode ~= "value" and colorMode ~= "valueDark") then return nil, nil, nil end

    local useDark = (colorMode == "valueDark")

    -- Party frames are dynamically assigned - check each frame's unit property
    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame and frame.healthBar then
            local frameUnit
            local ok, u = pcall(function() return frame.displayedUnit or frame.unit end)
            if ok and u then frameUnit = u end
            -- Check if this frame is displaying the unit we're looking for
            if frameUnit and UnitIsUnit(frameUnit, unit) then
                return frame.healthBar, frame, useDark
            end
        end
    end
end

local partyHealthColorEventFrame = CreateFrame("Frame")
partyHealthColorEventFrame:RegisterEvent("UNIT_HEALTH")
partyHealthColorEventFrame:RegisterEvent("UNIT_MAXHEALTH")
partyHealthColorEventFrame:RegisterEvent("UNIT_HEAL_PREDICTION")
partyHealthColorEventFrame:SetScript("OnEvent", function(self, event, unit)
    if not unit or not isPartyUnit(unit) then return end

    local bar, frame, useDark = getPartyHealthBarForUnit(unit)
    if not bar then return end

    -- Use the frame's actual unit token for color calculation
    local actualUnit = unit
    if frame then
        local ok, u = pcall(function() return frame.displayedUnit or frame.unit end)
        if ok and u then actualUnit = u end
    end

    local state = getState(bar)
    local overlay = state and state.healthOverlay or nil
    if overlay and addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
        addon.BarsTextures.applyValueBasedColor(bar, actualUnit, overlay, useDark)
        -- Schedule reapply loop to catch timing edge cases (stuck colors at 100%)
        if addon.BarsTextures.scheduleColorValidation then
            addon.BarsTextures.scheduleColorValidation(bar, actualUnit, overlay, useDark)
        end
    elseif addon.BarsTextures and addon.BarsTextures.applyValueBasedColor then
        addon.BarsTextures.applyValueBasedColor(bar, actualUnit, nil, useDark)
    end
end)

--------------------------------------------------------------------------------
-- Over Absorb Glow Visibility
--------------------------------------------------------------------------------
-- Hides or shows the OverAbsorbGlow texture on party frames.
-- This glow appears when absorb shields exceed the health bar width.
-- Frame: CompactPartyFrameMember[1-5].overAbsorbGlow (direct child of frame, not healthBar)
--
-- Uses alpha hiding with persistent hooks (same pattern as player frame OverAbsorbGlow).
--------------------------------------------------------------------------------

local function applyOverAbsorbGlowVisibility(frame, shouldHide)
    if not frame then return end
    -- overAbsorbGlow is a direct child of CompactUnitFrame, not healthBar
    -- Frame path: CompactPartyFrameMember[1-5].overAbsorbGlow
    local glow = frame.overAbsorbGlow
    if not glow then return end

    local state = ensureState(glow)
    if not state then return end

    if shouldHide then
        state.glowHidden = true
        if glow.SetAlpha then pcall(glow.SetAlpha, glow, 0) end

        -- Install persistence hooks (only once)
        if not state.glowHooked and _G.hooksecurefunc then
            state.glowHooked = true
            _G.hooksecurefunc(glow, "SetAlpha", function(self, alpha)
                local st = getState(self)
                if alpha and alpha > 0 and st and st.glowHidden then
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, function()
                            local st2 = getState(self)
                            if st2 and st2.glowHidden and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
            end)
            _G.hooksecurefunc(glow, "Show", function(self)
                local st = getState(self)
                if st and st.glowHidden and self.SetAlpha then
                    pcall(self.SetAlpha, self, 0)
                end
            end)
        end
    else
        state.glowHidden = false
        -- Restore visibility (let Blizzard control alpha)
        if glow.SetAlpha then pcall(glow.SetAlpha, glow, 1) end
    end
end

function PartyFrames.ApplyOverAbsorbGlowVisibility()
    local db = addon.db and addon.db.profile
    local partyCfg = db and db.groupFrames and db.groupFrames.party or nil

    -- Zero-Touch: if no party config exists, don't touch party frames at all
    if not partyCfg then return end

    -- Only process if user has explicitly set hideOverAbsorbGlow
    local shouldHide = partyCfg.hideOverAbsorbGlow or false
    if not shouldHide then return end

    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            applyOverAbsorbGlowVisibility(frame, shouldHide)
        end
    end
end

-- Export to addon namespace
addon.ApplyPartyOverAbsorbGlowVisibility = PartyFrames.ApplyOverAbsorbGlowVisibility

--------------------------------------------------------------------------------
-- Generic Texture Visibility Helper
--------------------------------------------------------------------------------
-- Parameterized version of the OverAbsorbGlow pattern.
-- Uses SetAlpha(0) with persistent hooks on SetAlpha/Show (deferred via C_Timer.After).
-- stateKey: unique string per texture type to avoid colliding with other state flags.
--------------------------------------------------------------------------------

local function applyTextureVisibility(texture, shouldHide, stateKey)
    if not texture then return end

    local state = ensureState(texture)
    if not state then return end

    local hiddenKey = stateKey .. "Hidden"
    local hookedKey = stateKey .. "Hooked"

    if shouldHide then
        state[hiddenKey] = true
        if texture.SetAlpha then pcall(texture.SetAlpha, texture, 0) end

        -- Install persistence hooks (only once)
        if not state[hookedKey] and _G.hooksecurefunc then
            state[hookedKey] = true
            _G.hooksecurefunc(texture, "SetAlpha", function(self, alpha)
                local st = getState(self)
                if alpha and alpha > 0 and st and st[hiddenKey] then
                    if _G.C_Timer and _G.C_Timer.After then
                        _G.C_Timer.After(0, function()
                            local st2 = getState(self)
                            if st2 and st2[hiddenKey] and self.SetAlpha then
                                pcall(self.SetAlpha, self, 0)
                            end
                        end)
                    end
                end
            end)
            _G.hooksecurefunc(texture, "Show", function(self)
                local st = getState(self)
                if st and st[hiddenKey] and self.SetAlpha then
                    pcall(self.SetAlpha, self, 0)
                end
            end)
        end
    else
        state[hiddenKey] = false
        -- Restore visibility (let Blizzard control alpha)
        if texture.SetAlpha then pcall(texture.SetAlpha, texture, 1) end
    end
end

--------------------------------------------------------------------------------
-- Heal Prediction Visibility
--------------------------------------------------------------------------------
-- Hides or shows myHealPrediction and otherHealPrediction textures on party frames.
-- Frame: CompactPartyFrameMember[1-5].myHealPrediction / .otherHealPrediction
--------------------------------------------------------------------------------

local applyHealPredictionVisibility = function(frame, shouldHide)
    if not frame then return end
    applyTextureVisibility(frame.myHealPrediction, shouldHide, "healPred")
    applyTextureVisibility(frame.otherHealPrediction, shouldHide, "healPred")
end

PartyFrames.applyHealPredictionVisibility = applyHealPredictionVisibility

function PartyFrames.ApplyHealPredictionVisibility()
    local db = addon.db and addon.db.profile
    local partyCfg = db and db.groupFrames and db.groupFrames.party or nil

    -- Zero-Touch: if no party config exists, don't touch party frames at all
    if not partyCfg then return end

    local shouldHide = partyCfg.hideHealPrediction or false
    if not shouldHide then return end

    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            applyHealPredictionVisibility(frame, shouldHide)
        end
    end
end

addon.ApplyPartyHealPredictionVisibility = PartyFrames.ApplyHealPredictionVisibility

--------------------------------------------------------------------------------
-- Absorb Bars Visibility
--------------------------------------------------------------------------------
-- Hides or shows absorb-related textures on party frames.
-- Textures: totalAbsorb, totalAbsorbOverlay, myHealAbsorb,
--           myHealAbsorbLeftShadow, myHealAbsorbRightShadow, overHealAbsorbGlow
--------------------------------------------------------------------------------

local applyAbsorbBarsVisibility = function(frame, shouldHide)
    if not frame then return end
    applyTextureVisibility(frame.totalAbsorb, shouldHide, "absorbBar")
    applyTextureVisibility(frame.totalAbsorbOverlay, shouldHide, "absorbBar")
    applyTextureVisibility(frame.myHealAbsorb, shouldHide, "absorbBar")
    applyTextureVisibility(frame.myHealAbsorbLeftShadow, shouldHide, "absorbBar")
    applyTextureVisibility(frame.myHealAbsorbRightShadow, shouldHide, "absorbBar")
    applyTextureVisibility(frame.overHealAbsorbGlow, shouldHide, "absorbBar")
end

PartyFrames.applyAbsorbBarsVisibility = applyAbsorbBarsVisibility

function PartyFrames.ApplyAbsorbBarsVisibility()
    local db = addon.db and addon.db.profile
    local partyCfg = db and db.groupFrames and db.groupFrames.party or nil

    -- Zero-Touch: if no party config exists, don't touch party frames at all
    if not partyCfg then return end

    local shouldHide = partyCfg.hideAbsorbBars or false
    if not shouldHide then return end

    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            applyAbsorbBarsVisibility(frame, shouldHide)
        end
    end
end

addon.ApplyPartyAbsorbBarsVisibility = PartyFrames.ApplyAbsorbBarsVisibility

--------------------------------------------------------------------------------
-- Heal Prediction Clipping (MaskTexture)
--------------------------------------------------------------------------------
-- Clips all prediction/absorb textures to healthBar bounds using MaskTexture.
-- This prevents textures (especially otherHealPrediction) from extending past
-- the right edge of the health bar at 100% health.
--
-- Only activates when user has configured party frames (zero-touch compliant).
-- Mask is anchored to healthBar (stable frame) and persists across repositioning.
--------------------------------------------------------------------------------

local healPredictionTextureKeys = {
    "myHealPrediction",
    "otherHealPrediction",
    "totalAbsorb",
    "totalAbsorbOverlay",
    "myHealAbsorb",
    "myHealAbsorbLeftShadow",
    "myHealAbsorbRightShadow",
    "overHealAbsorbGlow",
}

local ensureHealPredictionClipping = function(frame)
    if not frame then return end
    local healthBar = frame.healthBar
    if not healthBar then return end

    local state = ensureState(frame)
    if not state then return end

    -- Create mask once per frame, anchored to healthBar
    if not state.healPredClipMask then
        local ok, mask = pcall(healthBar.CreateMaskTexture, healthBar)
        if not ok or not mask then return end
        pcall(mask.SetTexture, mask, "Interface\\BUTTONS\\WHITE8X8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        pcall(mask.SetAllPoints, mask, healthBar)
        state.healPredClipMask = mask
    end

    local mask = state.healPredClipMask
    if not mask then return end

    -- Apply mask to each prediction/absorb texture
    for _, key in ipairs(healPredictionTextureKeys) do
        local tex = frame[key]
        if tex and tex.AddMaskTexture then
            pcall(tex.AddMaskTexture, tex, mask)
        end
    end
end

PartyFrames.ensureHealPredictionClipping = ensureHealPredictionClipping

function PartyFrames.ApplyHealPredictionClipping()
    local db = addon.db and addon.db.profile
    local partyCfg = db and db.groupFrames and db.groupFrames.party or nil

    -- Zero-Touch: if no party config exists, don't touch party frames at all
    if not partyCfg then return end

    for i = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. i]
        if frame then
            ensureHealPredictionClipping(frame)
        end
    end
end

addon.ApplyPartyHealPredictionClipping = PartyFrames.ApplyHealPredictionClipping

return PartyFrames
