--------------------------------------------------------------------------------
-- dial.lua - The day-night dial on Forever's minimap
--
-- Forever's Blizzard_Minimap adds MinimapCluster.DielFrame (Camelot/Diel.lua,
-- FileDataID 8199123): a 42x42 frame at CENTER of the cluster, (63, 72), whose
-- BACKGROUND texture is the day or night art (swapped on DIEL_CYCLE_CHANGED)
-- and whose OVERLAY texture is the ring, UI-HUD-Minimap-Frame-Cycle. Blizzard
-- replaces the cluster's SetEditModeScale with a version that keeps the dial
-- at scale 1 or more and re-anchors it, so every apply here runs again behind
-- that call. Retail has no such frame, and this file does nothing there.
--
-- Hide, hide the ring, scale, and a position of the addon's own: dragged with
-- the mouse inside the Minimap, or set from the tab. The dial is Blizzard's
-- frame, so this file calls its methods and stores nothing on it; the drag
-- handle is a frame of the addon's laid over the dial, and what Blizzard
-- anchored and scaled is remembered here for the way back.
--------------------------------------------------------------------------------

local addonName, addon = ...

local MM = addon.Minimap

local getMinimapDB = MM._getMinimapDB

local BRAND = addon.Brand or "Scoot"

local handle = nil        -- the addon's drag frame over the dial
local hooked = false
local original = nil      -- Blizzard's anchor, read before the first change
local baseScale = 1       -- what Blizzard last set: max(1, the Edit Mode scale)
local dragging = false

local ApplyDialStyle

local function dialFrame()
    local cluster = _G.MinimapCluster
    local frame = cluster and cluster.DielFrame
    if frame and frame.Background then return frame end
    return nil
end

-- True on a client whose minimap carries the dial; the renderer shows the tab on it.
function MM.HasDial()
    return dialFrame() ~= nil
end

-- The ring is the dial's one OVERLAY texture; Blizzard keeps no key for it.
local function ringTexture(frame)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:IsObjectType("Texture") and region:GetDrawLayer() == "OVERLAY" then
            return region
        end
    end
    return nil
end

local function rememberOriginal(frame)
    if original then return end
    local ok, point, relativeTo, relativePoint, x, y = pcall(frame.GetPoint, frame, 1)
    if not ok or not point then
        point, relativeTo, relativePoint, x, y = "CENTER", nil, "CENTER", 63, 72
    end
    original = {
        point = point,
        relativeTo = relativeTo or frame:GetParent(),
        relativePoint = relativePoint or point,
        x = x or 0,
        y = y or 0,
    }
    local okScale, scale = pcall(frame.GetScale, frame)
    baseScale = (okScale and type(scale) == "number" and scale > 0) and scale or 1
end

local function restoreAnchor(frame)
    if not original then return end
    frame:ClearAllPoints()
    frame:SetPoint(original.point, original.relativeTo, original.relativePoint, original.x, original.y)
end

-- Blizzard's SetEditModeScale re-scales and re-anchors the dial on every
-- layout apply and Map Size change; the addon's values go back on behind it.
local function ensureHook()
    if hooked then return end
    local cluster = _G.MinimapCluster
    if not (cluster and type(cluster.SetEditModeScale) == "function") then return end
    hooked = true
    hooksecurefunc(cluster, "SetEditModeScale", function(_, scale)
        local frame = dialFrame()
        if not frame then return end
        original = nil
        rememberOriginal(frame)
        baseScale = math.max(1, tonumber(scale) or 1)
        local db = getMinimapDB()
        if db then ApplyDialStyle(db) end
    end)
end

--------------------------------------------------------------------------------
-- The drag handle
--------------------------------------------------------------------------------

-- The handle's centre as an offset from the Minimap's centre, in the dial's
-- own scale (what SetPoint takes), clamped so the dial's centre stays on the map.
local function offsetsFrom(frame, minimap)
    if not handle then return nil end
    local ok1, hx, hy = pcall(handle.GetCenter, handle)
    local ok2, mx, my = pcall(minimap.GetCenter, minimap)
    if not (ok1 and ok2 and hx and hy and mx and my) then return nil end
    local hs = handle:GetEffectiveScale()
    local ms = minimap:GetEffectiveScale()
    local fs = frame:GetEffectiveScale()
    if not (hs and ms and fs and fs > 0) then return nil end

    local x = (hx * hs - mx * ms) / fs
    local y = (hy * hs - my * ms) / fs
    local halfW = (minimap:GetWidth() or 0) * ms / fs / 2
    local halfH = (minimap:GetHeight() or 0) * ms / fs / 2
    x = math.max(-halfW, math.min(halfW, x))
    y = math.max(-halfH, math.min(halfH, y))
    return math.floor(x + 0.5), math.floor(y + 0.5)
end

local function ensureHandle()
    if handle then return handle end

    handle = CreateFrame("Frame", BRAND .. "MinimapDialHandle", UIParent)
    handle:EnableMouse(true)
    handle:SetMovable(true)
    handle:RegisterForDrag("LeftButton")
    -- No mouse wheel: the Minimap under the dial keeps its zoom.

    handle:SetScript("OnDragStart", function(self)
        local frame = dialFrame()
        if not frame then return end
        dragging = true
        self:StartMoving()
        -- The dial follows the handle for the length of the drag.
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", self, "CENTER", 0, 0)
    end)

    handle:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        dragging = false
        local db = getMinimapDB()
        local frame = dialFrame()
        local minimap = _G.Minimap
        if db and frame and minimap then
            local x, y = offsetsFrom(frame, minimap)
            if x then
                db.dialMoved = true
                db.dialOffsetX = x
                db.dialOffsetY = y
            end
        end
        if db then ApplyDialStyle(db) end
    end)

    addon.RegisterPetBattleFrame(handle)
    return handle
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

ApplyDialStyle = function(db)
    local frame = dialFrame()
    if not frame then return end
    rememberOriginal(frame)
    ensureHook()

    -- Component off: Blizzard's dial as it came.
    if not db then
        frame:Show()
        local ring = ringTexture(frame)
        if ring then ring:SetAlpha(1) end
        frame:SetScale(baseScale)
        restoreAnchor(frame)
        if handle then handle:Hide() end
        return
    end

    if db.dialHide then
        frame:Hide()
        if handle then handle:Hide() end
        return
    end
    frame:Show()

    local ring = ringTexture(frame)
    if ring then ring:SetAlpha(db.dialBorderHide and 0 or 1) end

    frame:SetScale(baseScale * (tonumber(db.dialScale) or 1))

    if not dragging then
        local minimap = _G.Minimap
        if db.dialMoved and minimap then
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", minimap, "CENTER", tonumber(db.dialOffsetX) or 0, tonumber(db.dialOffsetY) or 0)
        else
            restoreAnchor(frame)
        end
    end

    -- Draggable whenever the component is on: the handle covers the dial.
    local h = ensureHandle()
    if not dragging then
        local okStrata, strata = pcall(frame.GetFrameStrata, frame)
        local okLevel, level = pcall(frame.GetFrameLevel, frame)
        h:SetFrameStrata(okStrata and type(strata) == "string" and strata or "MEDIUM")
        h:SetFrameLevel(((okLevel and type(level) == "number") and level or 5) + 1)
        h:ClearAllPoints()
        h:SetAllPoints(frame)
    end
    h:Show()
end

-- Promote to namespace for the core orchestrator
MM._ApplyDialStyle = ApplyDialStyle
