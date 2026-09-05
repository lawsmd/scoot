--------------------------------------------------------------------------------
-- frames.lua
-- Shared frame resolution: root unit frames, Edit Mode frames, and the
-- Blizzard sub-frame children (bars, containers, masks, frame art, center
-- texts, name and level FontStrings, contextual elements, portrait parts,
-- cast bars, aura containers).
-- Input vocabulary: PascalCase unit keys ("Player", "Target", "Focus", "Pet",
-- "Boss", "TargetOfTarget", "FocusTarget"; the strict path also accepts
-- "Party" and "Raid"). Callers with other vocabularies (lowercase debug keys,
-- ui/v2 componentIds) translate at their own edge.
-- Sub-frame resolvers use deterministic paths verified via /framestack and
-- read _G roots directly, never the Edit Mode registry, so results are the
-- same before and after PLAYER_ENTERING_WORLD. Signatures: (frame, unit)
-- takes a pre-resolved root (nil is accepted for the fixed-path units),
-- (unit) resolves the root internally, (bossFrame) serves the per-index
-- boss family.
--------------------------------------------------------------------------------

local addonName, addon = ...

addon.Frames = addon.Frames or {}
local Frames = addon.Frames

Frames.NUM_BOSS_FRAMES = 5
addon.NUM_BOSS_FRAMES = Frames.NUM_BOSS_FRAMES

-- Order is load-bearing: bars/snapshot.lua serializes baseline snapshots in this order.
Frames.UNITS = { "Player", "Target", "Focus", "Boss", "Pet", "TargetOfTarget", "FocusTarget" }
Frames.CORE_UNITS = { "Player", "Target", "Focus", "Pet" }
Frames.UNIT_KEY_BY_COMPONENT = {
    ufPlayer = "Player",
    ufTarget = "Target",
    ufFocus = "Focus",
    ufPet = "Pet",
    ufToT = "TargetOfTarget",
    ufBoss = "Boss",
    ufFocusTarget = "FocusTarget",
}

local EM_INDEX_KEY = {
    Player = "Player",
    Target = "Target",
    Focus = "Focus",
    Pet = "Pet",
    Boss = "Boss",
    Party = "Party",
    Raid = "Raid",
}

local GLOBAL_FALLBACK = {
    Player = "PlayerFrame",
    Target = "TargetFrame",
    Focus = "FocusFrame",
    Pet = "PetFrame",
    Boss = "Boss1TargetFrame",
}

-- Strict: the Edit Mode registered system frame or nil, never a _G fallback.
-- Use whenever the result feeds EditMode.GetSetting/WriteSetting or position
-- sync; a raw global there could write settings to the wrong object.
function addon.GetEditModeUnitFrame(unit)
    local mgr = _G.EditModeManagerFrame
    local EM = _G.Enum and _G.Enum.EditModeUnitFrameSystemIndices
    local EMSys = _G.Enum and _G.Enum.EditModeSystem
    if not (mgr and EM and EMSys and mgr.GetRegisteredSystemFrame) then return nil end
    local key = EM_INDEX_KEY[unit]
    local idx = key and EM[key]
    if not idx then return nil end
    return mgr:GetRegisteredSystemFrame(EMSys.UnitFrame, idx)
end

-- Styling: best-effort live frame. ToT/FocusTarget are not Edit Mode systems;
-- every other unit prefers the registry, then the _G frame (the registry
-- returns the same objects on retail, so the fallback can only supply a frame
-- where the registry gave nil, never a different frame).
function addon.GetUnitFrame(unit)
    if unit == "TargetOfTarget" then return _G.TargetFrameToT end
    if unit == "FocusTarget" then return _G.FocusFrameToT end
    local f = addon.GetEditModeUnitFrame(unit)
    if f then return f end
    local name = GLOBAL_FALLBACK[unit]
    if name then return _G[name] end
end

-- Accepts a number or a numeric string (several sites parse the index out of
-- a baseline key like "Boss3"); concat coerces both.
function addon.GetBossFrame(i)
    if not i then return nil end
    return _G["Boss" .. i .. "TargetFrame"]
end

-- fn(bossFrame, i); nil frames are skipped, matching the "if bossFrame then"
-- guard every hand-rolled loop carried.
function addon.ForEachBossFrame(fn)
    for i = 1, Frames.NUM_BOSS_FRAMES do
        local f = _G["Boss" .. i .. "TargetFrame"]
        if f then fn(f, i) end
    end
end

--------------------------------------------------------------------------------
-- Sub-frame resolution helpers
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
function Frames.getNested(root, ...)
    local cur = root
    for i = 1, select('#', ...) do
        local key = select(i, ...)
        if not cur or type(cur) ~= "table" then return nil end
        cur = cur[key]
    end
    return cur
end
local getNested = Frames.getNested

--------------------------------------------------------------------------------
-- Health Bar Resolution
--------------------------------------------------------------------------------

function Frames.resolveHealthBar(frame, unit)
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

function Frames.resolveHealthContainer(frame, unit)
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

function Frames.resolvePowerBar(frame, unit)
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
function Frames.resolveAlternatePowerBar()
    local bar = _G.AlternatePowerBar
    if bar and bar.GetObjectType and bar:GetObjectType() == "StatusBar" then
        return bar
    end
end

--------------------------------------------------------------------------------
-- Mask Resolution
--------------------------------------------------------------------------------

function Frames.resolveHealthMask(unit)
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

function Frames.resolvePowerMask(unit)
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
function Frames.resolveUFContentMain(unit)
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
function Frames.resolveUnitFrameFrameTexture(unit)
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

function Frames.resolveBossHealthMask(bossFrame)
    local hb = bossFrame and bossFrame.healthbar
    if hb then
        local parent = hb:GetParent()
        if parent and parent.HealthBarMask then return parent.HealthBarMask end
    end
end

function Frames.resolveBossPowerMask(bossFrame)
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
function Frames.resolveBossHealthBarsContainer(bossFrame)
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
function Frames.resolveBossManaBar(bossFrame)
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

--------------------------------------------------------------------------------
-- Contextual Resolution
--------------------------------------------------------------------------------

-- Sibling of the content-main container that holds the situational children
-- (threat meter, icons, prestige art, the engine-managed aura container).
function Frames.resolveContextual(unit)
    if unit == "Player" then
        local root = _G.PlayerFrame
        return root and root.PlayerFrameContent and root.PlayerFrameContent.PlayerFrameContentContextual or nil
    elseif unit == "Target" then
        local root = _G.TargetFrame
        return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentContextual or nil
    elseif unit == "Focus" then
        local root = _G.FocusFrame
        return root and root.TargetFrameContent and root.TargetFrameContent.TargetFrameContentContextual or nil
    end
end

function Frames.resolveBossContextual(bossFrame)
    return bossFrame
        and bossFrame.TargetFrameContent
        and bossFrame.TargetFrameContent.TargetFrameContentContextual
        or nil
end

--------------------------------------------------------------------------------
-- ReputationColor Resolution
--------------------------------------------------------------------------------

-- The ReputationColor strip of the Target or Focus frame, resolved live because
-- Blizzard can recreate it during rapid target changes.
function Frames.resolveReputationColor(unit)
    if unit ~= "Target" and unit ~= "Focus" then return nil end
    local main = Frames.resolveUFContentMain(unit)
    return main and main.ReputationColor or nil
end

function Frames.resolveBossReputationColor(bossFrame)
    local main = Frames.resolveBossContentMain(bossFrame)
    return main and main.ReputationColor or nil
end

--------------------------------------------------------------------------------
-- Name and Level FontString Resolution
--------------------------------------------------------------------------------

function Frames.resolveNameFS(unit)
    if unit == "Player" then return _G.PlayerName end
    if unit == "Pet" then return _G.PetName end
    if unit == "TargetOfTarget" then
        local tot = _G.TargetFrameToT
        return tot and tot.Name or nil
    end
    if unit == "FocusTarget" then
        local fot = _G.FocusFrameToT
        return fot and fot.Name or nil
    end
    if unit == "Target" or unit == "Focus" then
        local main = Frames.resolveUFContentMain(unit)
        return main and main.Name or nil
    end
end

-- Pet has no level FontString.
function Frames.resolveLevelFS(unit)
    if unit == "Player" then return _G.PlayerLevelText end
    if unit == "Target" or unit == "Focus" then
        local main = Frames.resolveUFContentMain(unit)
        return main and main.LevelText or nil
    end
end

--------------------------------------------------------------------------------
-- Boss Content and Text Resolution
--------------------------------------------------------------------------------

function Frames.resolveBossContentMain(bossFrame)
    return bossFrame
        and bossFrame.TargetFrameContent
        and bossFrame.TargetFrameContent.TargetFrameContentMain
        or nil
end

-- The name property is preferred; the path serves frames the property has not
-- been assigned on yet.
function Frames.resolveBossNameFS(bossFrame)
    if not bossFrame then return nil end
    local main = Frames.resolveBossContentMain(bossFrame)
    return bossFrame.name or (main and main.Name) or nil
end

function Frames.resolveBossLevelFS(bossFrame)
    local main = Frames.resolveBossContentMain(bossFrame)
    return main and main.LevelText or nil
end

--------------------------------------------------------------------------------
-- Center Text Resolution
--------------------------------------------------------------------------------

-- Center FontStrings (the Character Pane shows these instead of Left/Right).
function Frames.resolveHealthCenterText(unit)
    if unit == "Pet" then return _G.PetFrameHealthBarText end
    if unit == "Player" or unit == "Target" or unit == "Focus" then
        local c = Frames.resolveHealthContainer(nil, unit)
        return c and c.HealthBarText or nil
    end
end

function Frames.resolvePowerCenterText(unit)
    if unit == "Pet" then return _G.PetFrameManaBarText end
    if unit == "Player" or unit == "Target" or unit == "Focus" then
        local mb = Frames.resolvePowerBar(nil, unit)
        return mb and mb.ManaBarText or nil
    end
end

--------------------------------------------------------------------------------
-- Cast Bar Frame Resolution
--------------------------------------------------------------------------------

function Frames.resolveCastBarFrame(unit)
    if unit == "Player" then
        return _G.PlayerCastingBarFrame
    end
    if unit == "Target" then
        return _G.TargetFrameSpellBar
    elseif unit == "Focus" then
        return _G.FocusFrameSpellBar
    end
end

--------------------------------------------------------------------------------
-- Aura Container Resolution
--------------------------------------------------------------------------------

-- The engine-managed aura container (the capital-A Auras child of the
-- contextual frame); the lowercase buffs and debuffs children are a different
-- shape and stay leaf reads at their call sites.
function Frames.resolveAuraContainer(unit)
    local contextual = Frames.resolveContextual(unit)
    return contextual and contextual.Auras or nil
end

--------------------------------------------------------------------------------
-- Portrait Part Resolution
--------------------------------------------------------------------------------

-- Resolve portrait frame for a given unit
function Frames.resolvePortraitFrame(unit)
    if unit == "Player" then
        local root = _G.PlayerFrame
        return root and root.PlayerFrameContainer and root.PlayerFrameContainer.PlayerPortrait or nil
    elseif unit == "Target" then
        local root = _G.TargetFrame
        return root and root.TargetFrameContainer and root.TargetFrameContainer.Portrait or nil
    elseif unit == "Focus" then
        local root = _G.FocusFrame
        return root and root.TargetFrameContainer and root.TargetFrameContainer.Portrait or nil
    elseif unit == "Pet" then
        return _G.PetPortrait
    elseif unit == "TargetOfTarget" then
        local tot = _G.TargetFrameToT
        return tot and tot.Portrait or nil
    elseif unit == "FocusTarget" then
        local fot = _G.FocusFrameToT
        return fot and fot.Portrait or nil
    end
end

-- Resolve portrait mask frame for a given unit
function Frames.resolvePortraitMaskFrame(unit)
    if unit == "Player" then
        local root = _G.PlayerFrame
        return root and root.PlayerFrameContainer and root.PlayerFrameContainer.PlayerPortraitMask or nil
    elseif unit == "Target" then
        local root = _G.TargetFrame
        return root and root.TargetFrameContainer and root.TargetFrameContainer.PortraitMask or nil
    elseif unit == "Focus" then
        local root = _G.FocusFrame
        return root and root.TargetFrameContainer and root.TargetFrameContainer.PortraitMask or nil
    elseif unit == "Pet" then
        local root = _G.PetFrame
        return root and root.PortraitMask or nil
    elseif unit == "TargetOfTarget" then
        local tot = _G.TargetFrameToT
        return tot and tot.PortraitMask or nil
    elseif unit == "FocusTarget" then
        local fot = _G.FocusFrameToT
        return fot and fot.PortraitMask or nil
    end
end

-- Resolve portrait corner icon frame for a given unit (Player-only)
function Frames.resolvePortraitCornerIconFrame(unit)
    if unit == "Player" then
        local contextual = Frames.resolveContextual(unit)
        return contextual and contextual.PlayerPortraitCornerIcon or nil
    end
end

-- Resolve portrait rest loop frame for a given unit (Player-only)
function Frames.resolvePortraitRestLoopFrame(unit)
    if unit == "Player" then
        local contextual = Frames.resolveContextual(unit)
        return contextual and contextual.PlayerRestLoop or nil
    end
end

-- Resolve portrait status texture frame for a given unit (Player-only)
function Frames.resolvePortraitStatusTextureFrame(unit)
    if unit == "Player" then
        local main = Frames.resolveUFContentMain(unit)
        return main and main.StatusTexture or nil
    end
end

-- Resolve damage text (HitText) frame for a given unit (Player and Pet)
function Frames.resolveDamageTextFrame(unit)
    if unit == "Player" then
        local main = Frames.resolveUFContentMain(unit)
        return main and main.HitIndicator and main.HitIndicator.HitText or nil
    elseif unit == "Pet" then
        -- PetHitIndicator is directly available as a global and as PetFrame.feedbackText
        return _G.PetHitIndicator or (_G.PetFrame and _G.PetFrame.feedbackText)
    end
end

-- Resolve boss portrait frame texture for a given unit (Target/Focus only).
-- This texture appears when targeting a boss and hides along with the portrait.
function Frames.resolveBossPortraitFrameTexture(unit)
    if unit == "Target" then
        local root = _G.TargetFrame
        return root and root.TargetFrameContainer and root.TargetFrameContainer.BossPortraitFrameTexture or nil
    elseif unit == "Focus" then
        local root = _G.FocusFrame
        return root and root.TargetFrameContainer and root.TargetFrameContainer.BossPortraitFrameTexture or nil
    end
end

-- Resolve pet attack mode texture (Pet only)
function Frames.resolvePetAttackModeTexture(unit)
    if unit == "Pet" then
        return _G.PetAttackModeTexture
    end
end

-- Resolve pet frame flash (Pet only)
function Frames.resolvePetFrameFlash(unit)
    if unit == "Pet" then
        return _G.PetFrameFlash
    end
end
