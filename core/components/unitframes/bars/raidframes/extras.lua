--------------------------------------------------------------------------------
-- bars/raidframes/extras.lua
-- Raid frame extras: over-absorb glow, texture visibility helpers, heal
-- prediction visibility, absorb bars visibility, heal prediction clipping,
-- and role icons.
--
-- Loaded after raidframes/core.lua and raidframes/text.lua. Imports shared
-- state from addon.BarsRaidFrames.
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Get modules
local Utils = addon.BarsUtils
local Combat = addon.BarsCombat

-- Get module namespace (created in core.lua)
local RaidFrames = addon.BarsRaidFrames

-- Import shared state from core.lua
local RaidFrameState = addon.BarsRaidFrames._RaidFrameState
local getState = addon.BarsRaidFrames._getState
local ensureState = addon.BarsRaidFrames._ensureState
local isEditModeActive = addon.BarsRaidFrames._isEditModeActive

--------------------------------------------------------------------------------
-- Over Absorb Glow Visibility
--------------------------------------------------------------------------------
-- Hides or shows the OverAbsorbGlow texture on raid frames.
-- This glow appears when absorb shields exceed the health bar width.
-- Frame paths:
--   - CompactRaidGroup[1-8]Member[1-5].overAbsorbGlow (group layout)
--   - CompactRaidFrame[1-40].overAbsorbGlow (combined layout)
--
-- Uses alpha hiding with persistent hooks (same pattern as party frames).
--------------------------------------------------------------------------------

local function applyOverAbsorbGlowVisibility(frame, shouldHide)
    if not frame then return end
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
        if glow.SetAlpha then pcall(glow.SetAlpha, glow, 1) end
    end
end

function RaidFrames.ApplyOverAbsorbGlowVisibility()
    local db = addon.db and addon.db.profile
    local raidCfg = db and db.groupFrames and db.groupFrames.raid or nil

    -- Zero-Touch: if no raid config exists, don't touch raid frames at all
    if not raidCfg then return end

    local shouldHide = raidCfg.hideOverAbsorbGlow or false
    if not shouldHide then return end

    -- Pattern 1: Group-based naming (CompactRaidGroup1Member1, etc.)
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame then
                applyOverAbsorbGlowVisibility(frame, shouldHide)
            end
        end
    end

    -- Pattern 2: Combined naming (CompactRaidFrame1, etc.)
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            applyOverAbsorbGlowVisibility(frame, shouldHide)
        end
    end
end

addon.ApplyRaidOverAbsorbGlowVisibility = RaidFrames.ApplyOverAbsorbGlowVisibility

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
-- Hides or shows myHealPrediction and otherHealPrediction textures on raid frames.
-- Frame paths:
--   - CompactRaidGroup[1-8]Member[1-5].myHealPrediction / .otherHealPrediction
--   - CompactRaidFrame[1-40].myHealPrediction / .otherHealPrediction
--------------------------------------------------------------------------------

local applyHealPredictionVisibility
applyHealPredictionVisibility = function(frame, shouldHide)
    if not frame then return end
    applyTextureVisibility(frame.myHealPrediction, shouldHide, "healPred")
    applyTextureVisibility(frame.otherHealPrediction, shouldHide, "healPred")
end

RaidFrames.applyHealPredictionVisibility = applyHealPredictionVisibility

function RaidFrames.ApplyHealPredictionVisibility()
    local db = addon.db and addon.db.profile
    local raidCfg = db and db.groupFrames and db.groupFrames.raid or nil

    -- Zero-Touch: if no raid config exists, don't touch raid frames at all
    if not raidCfg then return end

    local shouldHide = raidCfg.hideHealPrediction or false
    if not shouldHide then return end

    -- Pattern 1: Group-based naming (CompactRaidGroup1Member1, etc.)
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame then
                applyHealPredictionVisibility(frame, shouldHide)
            end
        end
    end

    -- Pattern 2: Combined naming (CompactRaidFrame1, etc.)
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            applyHealPredictionVisibility(frame, shouldHide)
        end
    end
end

addon.ApplyRaidHealPredictionVisibility = RaidFrames.ApplyHealPredictionVisibility

--------------------------------------------------------------------------------
-- Absorb Bars Visibility
--------------------------------------------------------------------------------
-- Hides or shows absorb-related textures on raid frames.
-- Textures: totalAbsorb, totalAbsorbOverlay, myHealAbsorb,
--           myHealAbsorbLeftShadow, myHealAbsorbRightShadow, overHealAbsorbGlow
--------------------------------------------------------------------------------

local applyAbsorbBarsVisibility
applyAbsorbBarsVisibility = function(frame, shouldHide)
    if not frame then return end
    applyTextureVisibility(frame.totalAbsorb, shouldHide, "absorbBar")
    applyTextureVisibility(frame.totalAbsorbOverlay, shouldHide, "absorbBar")
    applyTextureVisibility(frame.myHealAbsorb, shouldHide, "absorbBar")
    applyTextureVisibility(frame.myHealAbsorbLeftShadow, shouldHide, "absorbBar")
    applyTextureVisibility(frame.myHealAbsorbRightShadow, shouldHide, "absorbBar")
    applyTextureVisibility(frame.overHealAbsorbGlow, shouldHide, "absorbBar")
end

RaidFrames.applyAbsorbBarsVisibility = applyAbsorbBarsVisibility

function RaidFrames.ApplyAbsorbBarsVisibility()
    local db = addon.db and addon.db.profile
    local raidCfg = db and db.groupFrames and db.groupFrames.raid or nil

    -- Zero-Touch: if no raid config exists, don't touch raid frames at all
    if not raidCfg then return end

    local shouldHide = raidCfg.hideAbsorbBars or false
    if not shouldHide then return end

    -- Pattern 1: Group-based naming
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame then
                applyAbsorbBarsVisibility(frame, shouldHide)
            end
        end
    end

    -- Pattern 2: Combined naming
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            applyAbsorbBarsVisibility(frame, shouldHide)
        end
    end
end

addon.ApplyRaidAbsorbBarsVisibility = RaidFrames.ApplyAbsorbBarsVisibility

--------------------------------------------------------------------------------
-- Heal Prediction Clipping (MaskTexture)
--------------------------------------------------------------------------------
-- Clips all prediction/absorb textures to healthBar bounds using MaskTexture.
-- This prevents textures from extending past the health bar edges.
--
-- Only activates when user has configured raid frames (zero-touch compliant).
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

local ensureHealPredictionClipping
ensureHealPredictionClipping = function(frame)
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

RaidFrames.ensureHealPredictionClipping = ensureHealPredictionClipping

function RaidFrames.ApplyHealPredictionClipping()
    local db = addon.db and addon.db.profile
    local raidCfg = db and db.groupFrames and db.groupFrames.raid or nil

    -- Zero-Touch: if no raid config exists, don't touch raid frames at all
    if not raidCfg then return end

    -- Pattern 1: Group-based naming
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame then
                ensureHealPredictionClipping(frame)
            end
        end
    end

    -- Pattern 2: Combined naming
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then
            ensureHealPredictionClipping(frame)
        end
    end
end

addon.ApplyRaidHealPredictionClipping = RaidFrames.ApplyHealPredictionClipping

--------------------------------------------------------------------------------
-- Apply Custom Role Icons for Raid Frames
--------------------------------------------------------------------------------
-- Re-triggers Blizzard's CompactUnitFrame_UpdateRoleIcon on each raid frame.
-- Blizzard sets the default atlas, then our post-hook swaps to the custom set.

function addon.ApplyRaidRoleIcons()
    local directApply = addon._applyCustomRoleIcon
    -- Combined layout: CompactRaidFrame1..40
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame and frame.roleIcon then
            if _G.CompactUnitFrame_UpdateRoleIcon then
                local ok = pcall(CompactUnitFrame_UpdateRoleIcon, frame)
                if not ok and directApply then
                    pcall(directApply, frame)
                end
            end
        end
    end

    -- Group layout: CompactRaidGroup1Member1..CompactRaidGroup8Member5
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
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
end

--------------------------------------------------------------------------------
-- Apply Group Lead Icons for Raid Frames
--------------------------------------------------------------------------------

function addon.ApplyRaidGroupLeadIcons()
    local directApply = addon._applyGroupLeadIcon
    if not directApply then return end

    -- Combined layout: CompactRaidFrame1..40
    for i = 1, 40 do
        local frame = _G["CompactRaidFrame" .. i]
        if frame then pcall(directApply, frame) end
    end

    -- Group layout: CompactRaidGroup1Member1..CompactRaidGroup8Member5
    for group = 1, 8 do
        for member = 1, 5 do
            local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
            if frame then pcall(directApply, frame) end
        end
    end
end

return RaidFrames
