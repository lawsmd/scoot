--------------------------------------------------------------------------------
-- coordinates.lua - The player's map coordinates under or around the Minimap
--
-- Blizzard draws a readout of its own from 12.1.5 on, and Forever inherits
-- it: MinimapCluster.MinimapContainer.PlayerCoords, a 90x10 frame anchored
-- BOTTOM of the Minimap at (0, -18) whose CoordText is refilled every 0.1 s while the
-- minimapShowPlayerCoords CVar is on, to tenths while coordsByTenths is on
-- (Blizzard_Minimap/Mainline/Minimap.lua, MinimapPlayerCoordsMixin; both
-- CVars are checkboxes in Options > Interface). Retail 12.1.0 has neither the
-- frame nor the CVars.
--
-- The position "default" keeps Blizzard's readout where it is and styles its
-- FontString, as the zone text and clock do in their dock position; any other
-- position hides Blizzard's frame and draws the addon's overlay, fed by a
-- ticker. On a client without the frame, "default" draws that overlay at
-- Blizzard's spot. The two switches, on and tenths, are Blizzard's CVars where
-- the client has them and profile keys where it does not, so a Forever player
-- sees Blizzard's own setting in the toggle and nothing is hidden behind a
-- profile default.
--------------------------------------------------------------------------------

local addonName, addon = ...

local MM = addon.Minimap

local getMinimapDB = MM._getMinimapDB
local ensureOverlayTable = MM._ensureOverlayTable
local Enforce = addon.Enforce

local UPDATE_INTERVAL = 0.2

-- Where Blizzard puts its readout, for the overlay on a client that has none.
local DEFAULT_POINT, DEFAULT_OFFSET_X, DEFAULT_OFFSET_Y = "BOTTOM", 0, -18

local FORMAT_TENTHS = "%.1f, %.1f"
local FORMAT_INTEGER = "%d, %d"

local coordsTimer = nil
local blizzardCoordsHidden = false
local blizzardTextFreed = false

--------------------------------------------------------------------------------
-- Blizzard's readout and its CVars
--------------------------------------------------------------------------------

local function blizzardCoords()
    local cluster = _G.MinimapCluster
    local container = cluster and cluster.MinimapContainer
    local frame = container and container.PlayerCoords
    if frame and frame.CoordText then
        return frame, frame.CoordText
    end
    return nil
end

local CVARS = {
    show = "minimapShowPlayerCoords",
    tenths = "coordsByTenths",
}

-- The CVar's value as a boolean, or nil on a client that does not define it.
function MM.CoordsCVar(name)
    local cvar = CVARS[name]
    if not cvar or not (C_CVar and C_CVar.GetCVar) then return nil end
    local ok, value = pcall(C_CVar.GetCVar, cvar)
    if not ok or value == nil then return nil end
    return value == "1"
end

function MM.SetCoordsCVar(name, on)
    local cvar = CVARS[name]
    if not cvar or not (C_CVar and C_CVar.SetCVar) then return end
    -- Kept off core/profiles/cvars.lua: a passthrough to Blizzard's own checkbox, stored nowhere in the profile.
    pcall(C_CVar.SetCVar, cvar, on and "1" or "0")
end

-- The two switches, wherever they live for this client.
local function coordsShown(db)
    local v = MM.CoordsCVar("show")
    if v == nil then v = db.coordsEnabled end
    return not not v
end

local function coordsByTenths(db)
    local v = MM.CoordsCVar("tenths")
    if v == nil then v = db.coordsTenths end
    return not not v
end

local COORDS_HIDE_OPTS = {
    methods = { "Show" },
    apply = function(frame)
        local hide = frame.HideBase or frame.Hide
        if hide then hide(frame) end
    end,
    when = function()
        local db = getMinimapDB()
        if not db then return false end
        return not not (db.coordsPosition and db.coordsPosition ~= "default")
    end,
}

local function HideBlizzardCoords(frame)
    frame:Hide()
    blizzardCoordsHidden = true
    Enforce.Install(frame, "minimapPlayerCoords", COORDS_HIDE_OPTS)
end

local function ShowBlizzardCoords(frame)
    if not blizzardCoordsHidden then return end
    blizzardCoordsHidden = false
    frame:Show()
end

--------------------------------------------------------------------------------
-- The overlay
--------------------------------------------------------------------------------

local function CreateCoordsOverlay()
    local overlays = ensureOverlayTable()
    if not overlays then return nil end
    if overlays.coords then return overlays.coords end

    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetHeight(20)
    frame:EnableMouse(false)

    local fontString = frame:CreateFontString(nil, "OVERLAY")
    fontString:SetPoint("CENTER", frame, "CENTER", 0, 0)
    fontString:SetJustifyH("CENTER")
    frame.fontString = fontString

    overlays.coords = frame
    addon.RegisterPetBattleFrame(frame)
    return frame
end

local function UpdateCoordinates()
    local overlays = ensureOverlayTable()
    local frame = overlays and overlays.coords
    if not frame or not frame:IsShown() then return end
    local fontString = frame.fontString

    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    local pos
    if ok and mapID then
        local ok2, p = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
        if ok2 then pos = p end
    end
    local x, y
    if pos then x, y = pos:GetXY() end
    if not x or not y or (x == 0 and y == 0) then
        fontString:SetText("")
        return
    end

    if frame.tenths then
        fontString:SetFormattedText(FORMAT_TENTHS, x * 100, y * 100)
    else
        fontString:SetFormattedText(FORMAT_INTEGER, math.floor(x * 100 + 0.5), math.floor(y * 100 + 0.5))
    end
end

local function stopTicker()
    if coordsTimer then
        coordsTimer:Cancel()
        coordsTimer = nil
    end
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

local function ApplyCoordinatesStyle(db)
    local overlays = ensureOverlayTable()
    if not overlays then return end

    local minimap = _G.Minimap
    if not minimap then return end

    stopTicker()

    if not db then
        if overlays.coords then overlays.coords:Hide() end
        return
    end

    local blizzFrame, blizzText = blizzardCoords()
    local position = db.coordsPosition or "default"
    local shown = coordsShown(db)

    local fontFace = addon.ResolveFontFace(db.coordsFont)
    local fontSize = tonumber(db.coordsFontSize) or 10
    local fontStyle = db.coordsFontStyle or "SHADOW"
    local r, g, b, a = addon.ResolveColorRGBA(db.coordsColorMode, db.coordsCustomColor)

    -- Blizzard's readout, in place. It blanks itself while its CVar is off,
    -- so the switch needs no hiding here.
    if position == "default" and blizzFrame and blizzText then
        if overlays.coords then overlays.coords:Hide() end
        ShowBlizzardCoords(blizzFrame)

        -- Blizzard's FontString fills its 90 px frame and wraps a wide
        -- string; centered on the frame with no width of its own, it
        -- takes the width of its text at any size.
        if not blizzardTextFreed then
            blizzardTextFreed = true
            blizzText:ClearAllPoints()
            blizzText:SetPoint("CENTER", blizzFrame, "CENTER", 0, 0)
        end
        -- Deep Shadow draws a companion string on the parent frame, which
        -- here would be Blizzard's; the base style stands in.
        addon.ApplyFontStyle(blizzText, fontFace, fontSize, addon.FontStyles.Unpaired(fontStyle))
        pcall(blizzText.SetTextColor, blizzText, r, g, b, a)
        return
    end

    if blizzFrame then
        HideBlizzardCoords(blizzFrame)
    end

    if not shown then
        if overlays.coords then overlays.coords:Hide() end
        return
    end

    local frame = overlays.coords or CreateCoordsOverlay()
    if not frame then return end
    local fontString = frame.fontString

    addon.ApplyFontStyle(fontString, fontFace, fontSize, fontStyle)
    fontString:SetTextColor(r, g, b, a)

    if position == "default" then
        MM._PlaceMapText(frame, minimap, DEFAULT_POINT, DEFAULT_OFFSET_X, DEFAULT_OFFSET_Y)
    else
        local offsetX = tonumber(db.coordsOffsetX) or 0
        local offsetY = tonumber(db.coordsOffsetY) or 0
        MM._PlaceMapText(frame, minimap, position, offsetX, offsetY)
    end
    frame:SetWidth(minimap:GetWidth())
    frame.tenths = coordsByTenths(db)

    frame:Show()
    UpdateCoordinates()
    coordsTimer = C_Timer.NewTicker(UPDATE_INTERVAL, UpdateCoordinates)
end

-- Promote to namespace for the core orchestrator and its CVar handler
MM._ApplyCoordinatesStyle = ApplyCoordinatesStyle
MM._CoordsCVarNames = CVARS
