--------------------------------------------------------------------------------
-- bars/resolvers.lua
-- Frame resolver functions for unit frame bar styling
-- Uses deterministic paths verified via /framestack
--------------------------------------------------------------------------------

local addonName, addon = ...

-- Get utilities
local Utils = addon.BarsUtils

-- Create module namespace
addon.BarsResolvers = addon.BarsResolvers or {}
local Resolvers = addon.BarsResolvers

--------------------------------------------------------------------------------
-- Unit Frame Resolution
--------------------------------------------------------------------------------

-- Get the main unit frame for a given unit type.
-- The body moved to core/frames.lua as addon.GetUnitFrame (refactor #22);
-- the alias stays because bars.lua upvalues Resolvers.getUnitFrameFor.
Resolvers.getUnitFrameFor = addon.GetUnitFrame

--------------------------------------------------------------------------------
-- Status Bar Resolution Helpers
--------------------------------------------------------------------------------

-- Find a StatusBar by name hints (fallback search)
local function findStatusBarByHints(root, hintsTbl, excludesTbl)
    if not root then return nil end
    local hints = hintsTbl or {}
    local excludes = excludesTbl or {}
    local found
    local function matchesName(obj)
        local nm = (obj and obj.GetName and obj:GetName()) or (obj and obj.GetDebugName and obj:GetDebugName()) or ""
        if type(nm) ~= "string" then return false end
        local lnm = string.lower(nm)
        for _, ex in ipairs(excludes) do
            if ex and string.find(lnm, string.lower(ex), 1, true) then
                return false
            end
        end
        for _, h in ipairs(hints) do
            if h and string.find(lnm, string.lower(h), 1, true) then
                return true
            end
        end
        return false
    end
    local function scan(obj)
        if not obj or found then return end
        if obj.GetObjectType and obj:GetObjectType() == "StatusBar" then
            if matchesName(obj) then
                found = obj; return
            end
        end
        if obj.GetChildren then
            local m = (obj.GetNumChildren and obj:GetNumChildren()) or 0
            for i = 1, m do
                local c = select(i, obj:GetChildren())
                scan(c)
                if found then return end
            end
        end
    end
    scan(root)
    return found
end

-- Safe nested table access
local function getNested(root, ...)
    local cur = root
    for i = 1, select('#', ...) do
        local key = select(i, ...)
        if not cur or type(cur) ~= "table" then return nil end
        cur = cur[key]
    end
    return cur
end

--------------------------------------------------------------------------------
-- Health Bar Resolution
--------------------------------------------------------------------------------

function Resolvers.resolveHealthBar(frame, unit)
    -- Deterministic paths verified via /framestack; fallback to conservative search only if missing
    if unit == "Pet" then return _G.PetFrameHealthBar end
    if unit == "TargetOfTarget" then
        local tot = _G.TargetFrameToT
        return tot and tot.HealthBar or nil
    end
    if unit == "FocusTarget" then
        local fot = _G.FocusFrameToT
        return fot and fot.HealthBar or nil
    end
    if unit == "Player" then
        local root = _G.PlayerFrame
        local hb = getNested(root, "PlayerFrameContent", "PlayerFrameContentMain", "HealthBarsContainer", "HealthBar")
        if hb then return hb end
    elseif unit == "Target" then
        local root = _G.TargetFrame
        local hb = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar")
        if hb then return hb end
    elseif unit == "Focus" then
        local root = _G.FocusFrame
        local hb = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar")
        if hb then return hb end
    elseif unit == "Boss" then
        -- Boss frames: ALWAYS use the deterministic path verified via /framestack.
        -- The `healthbar` property may point to a StatusBar with wrong dimensions (spanning
        -- the entire frame content area rather than just the visible health bar region).
        local explicit = getNested(frame, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar")
        if explicit and explicit.GetObjectType and explicit:GetObjectType() == "StatusBar" then
            return explicit
        end

        -- Fallback to direct property only if deterministic path fails.
        local hb = frame and frame.healthbar
        if hb and hb.GetObjectType and hb:GetObjectType() == "StatusBar" then
            return hb
        end
    end
    -- Fallbacks
    if frame and frame.HealthBarsContainer and frame.HealthBarsContainer.HealthBar then return frame.HealthBarsContainer.HealthBar end
    return findStatusBarByHints(frame, {"HealthBarsContainer.HealthBar", ".HealthBar", "HealthBar"}, {"Prediction", "Absorb", "Mana"})
end

--------------------------------------------------------------------------------
-- Health Container Resolution
--------------------------------------------------------------------------------

function Resolvers.resolveHealthContainer(frame, unit)
    if unit == "Pet" then return _G.PetFrame and _G.PetFrame.HealthBarContainer end
    if unit == "Player" then
        local root = _G.PlayerFrame
        local c = getNested(root, "PlayerFrameContent", "PlayerFrameContentMain", "HealthBarsContainer")
        if c then return c end
    elseif unit == "Target" then
        local root = _G.TargetFrame
        local c = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer")
        if c then return c end
    elseif unit == "Focus" then
        local root = _G.FocusFrame
        local c = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer")
        if c then return c end
    end
    return frame and frame.HealthBarsContainer or nil
end

--------------------------------------------------------------------------------
-- Power Bar Resolution
--------------------------------------------------------------------------------

function Resolvers.resolvePowerBar(frame, unit)
    if unit == "Pet" then return _G.PetFrameManaBar end
    if unit == "TargetOfTarget" then
        local tot = _G.TargetFrameToT
        return tot and tot.ManaBar or nil
    end
    if unit == "FocusTarget" then
        local fot = _G.FocusFrameToT
        return fot and fot.ManaBar or nil
    end
    if unit == "Player" then
        local root = _G.PlayerFrame
        local mb = getNested(root, "PlayerFrameContent", "PlayerFrameContentMain", "ManaBarArea", "ManaBar")
        if mb then return mb end
    elseif unit == "Target" then
        local root = _G.TargetFrame
        local mb = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "ManaBar")
        if mb then return mb end
    elseif unit == "Focus" then
        local root = _G.FocusFrame
        local mb = getNested(root, "TargetFrameContent", "TargetFrameContentMain", "ManaBar")
        if mb then return mb end
    elseif unit == "Boss" then
        -- Boss frames: ALWAYS use the deterministic path verified via /framestack.
        -- The `manabar` property may point to a StatusBar with wrong dimensions.
        local explicit = getNested(frame, "TargetFrameContent", "TargetFrameContentMain", "ManaBar")
        if explicit and explicit.GetObjectType and explicit:GetObjectType() == "StatusBar" then
            return explicit
        end

        -- Fallback to direct property only if deterministic path fails.
        local mb = frame and frame.manabar
        if mb and mb.GetObjectType and mb:GetObjectType() == "StatusBar" then
            return mb
        end
    end
    if frame and frame.ManaBar then return frame.ManaBar end
    return findStatusBarByHints(frame, {"ManaBar", ".ManaBar", "PowerBar"}, {"Prediction"})
end

--------------------------------------------------------------------------------
-- Alternate Power Bar Resolution
--------------------------------------------------------------------------------

-- Resolve the global Alternate Power Bar for the Player frame
function Resolvers.resolveAlternatePowerBar()
    local bar = _G.AlternatePowerBar
    if bar and bar.GetObjectType and bar:GetObjectType() == "StatusBar" then
        return bar
    end
end

--------------------------------------------------------------------------------
-- Mask Resolution
--------------------------------------------------------------------------------

function Resolvers.resolveHealthMask(unit)
    if unit == "Player" then
        local root = _G.PlayerFrame
        return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain
            and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer
            and root.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBarMask
    elseif unit == "Target" then
        local root = _G.TargetFrame
        return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
            and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
            and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBarMask
    elseif unit == "Focus" then
        local root = _G.FocusFrame
        return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
            and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
            and root.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBarMask
    elseif unit == "Pet" then
        return _G.PetFrameHealthBarMask
    elseif unit == "TargetOfTarget" then
        local tot = _G.TargetFrameToT
        return tot and tot.HealthBar and tot.HealthBar.HealthBarMask or nil
    elseif unit == "FocusTarget" then
        local fot = _G.FocusFrameToT
        return fot and fot.HealthBar and fot.HealthBar.HealthBarMask or nil
    end
end

function Resolvers.resolvePowerMask(unit)
    if unit == "Player" then
        local root = _G.PlayerFrame
        return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain
            and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea
            and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar
            and root.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar.ManaBarMask
    elseif unit == "Target" then
        local root = _G.TargetFrame
        return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
            and root.TargetFrameContent.TargetFrameContentMain.ManaBar
            and root.TargetFrameContent.TargetFrameContentMain.ManaBar.ManaBarMask
    elseif unit == "Focus" then
        local root = _G.FocusFrame
        return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain
            and root.TargetFrameContent.TargetFrameContentMain.ManaBar
            and root.TargetFrameContent.TargetFrameContentMain.ManaBar.ManaBarMask
    elseif unit == "Pet" then
        return _G.PetFrameManaBarMask
    elseif unit == "TargetOfTarget" then
        local tot = _G.TargetFrameToT
        return tot and tot.ManaBar and tot.ManaBar.ManaBarMask or nil
    elseif unit == "FocusTarget" then
        local fot = _G.FocusFrameToT
        return fot and fot.ManaBar and fot.ManaBar.ManaBarMask or nil
    end
end

--------------------------------------------------------------------------------
-- Content Main Resolution
--------------------------------------------------------------------------------

-- Parent container that holds both Health and Power areas (content main)
function Resolvers.resolveUFContentMain(unit)
    if unit == "Player" then
        local root = _G.PlayerFrame
        return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentMain or nil
    elseif unit == "Target" then
        local root = _G.TargetFrame
        return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain or nil
    elseif unit == "Focus" then
        local root = _G.FocusFrame
        return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentMain or nil
    elseif unit == "Pet" then
        return _G.PetFrame
    elseif unit == "TargetOfTarget" then
        return _G.TargetFrameToT
    elseif unit == "FocusTarget" then
        return _G.FocusFrameToT
    end
end

--------------------------------------------------------------------------------
-- Frame Texture Resolution
--------------------------------------------------------------------------------

-- Resolve the stock unit frame frame art (the large atlas that includes the health bar border)
function Resolvers.resolveUnitFrameFrameTexture(unit)
    if unit == "Player" then
        local root = _G.PlayerFrame
        return root and root.PlayerFrameContainer and root.PlayerFrameContainer.FrameTexture or nil
    elseif unit == "Target" then
        local root = _G.TargetFrame
        return root and root.TargetFrameContainer and root.TargetFrameContainer.FrameTexture or nil
    elseif unit == "Focus" then
        local root = _G.FocusFrame
        return root and root.TargetFrameContainer and root.TargetFrameContainer.FrameTexture or nil
    elseif unit == "Boss" then
        local root = _G.Boss1TargetFrame
        return root and root.TargetFrameContainer and root.TargetFrameContainer.FrameTexture or nil
    elseif unit == "Pet" then
        return _G.PetFrameTexture
    elseif unit == "TargetOfTarget" then
        local tot = _G.TargetFrameToT
        return tot and tot.FrameTexture or nil
    elseif unit == "FocusTarget" then
        local fot = _G.FocusFrameToT
        return fot and fot.FrameTexture or nil
    end
end

--------------------------------------------------------------------------------
-- Boss Frame Mask Resolution
--------------------------------------------------------------------------------

function Resolvers.resolveBossHealthMask(bossFrame)
    local hb = bossFrame and bossFrame.healthbar
    if hb then
        local parent = hb:GetParent()
        if parent and parent.HealthBarMask then return parent.HealthBarMask end
    end
end

function Resolvers.resolveBossPowerMask(bossFrame)
    local mb = bossFrame and bossFrame.manabar
    if mb and mb.ManaBarMask then return mb.ManaBarMask end
end

--------------------------------------------------------------------------------
-- Boss Health Bar Container Resolution
--------------------------------------------------------------------------------

-- Resolve the HealthBarsContainer for Boss frames.
-- The HealthBar StatusBar has oversized dimensions spanning both health and power bars,
-- but the HealthBarsContainer parent has the correct bounds for just the health bar area.
-- ManaBar is a SIBLING of HealthBarsContainer (not a child), so
-- HealthBarsContainer contains ONLY the health bar region.
function Resolvers.resolveBossHealthBarsContainer(bossFrame)
    -- Try explicit path first (most reliable)
    local container = getNested(bossFrame, "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer")
    if container then return container end

    -- Fallback: use healthbar property and get its parent
    local hb = bossFrame and bossFrame.healthbar
    if hb then
        local parent = hb:GetParent()
        -- Verify it's the HealthBarsContainer by checking for HealthBarMask child
        if parent and parent.HealthBarMask then return parent end
    end
end

--------------------------------------------------------------------------------
-- Boss Power Bar (ManaBar) Resolution
--------------------------------------------------------------------------------

-- Resolve the ManaBar for Boss frames for border anchoring.
-- Unlike HealthBar, ManaBar is NOT inside a container - it's directly under TargetFrameContentMain.
-- The ManaBar StatusBar should have correct bounds (it's a sibling of HealthBarsContainer).
-- However, for consistency with the Health Bar pattern, the same anchor frame technique is used.
function Resolvers.resolveBossManaBar(bossFrame)
    -- Try explicit path first (most reliable)
    local mb = getNested(bossFrame, "TargetFrameContent", "TargetFrameContentMain", "ManaBar")
    if mb and mb.GetObjectType and mb:GetObjectType() == "StatusBar" then
        return mb
    end

    -- Fallback: use manabar property
    local manabar = bossFrame and bossFrame.manabar
    if manabar and manabar.GetObjectType and manabar:GetObjectType() == "StatusBar" then
        return manabar
    end
end

return Resolvers
