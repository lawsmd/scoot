--------------------------------------------------------------------------------
-- forever/minimap/text.lua
-- The text on and around the map: the zone name on the header plate or at one
-- of nine points, the player's coordinates, the clock, and the FPS and
-- latency readout. Every string is Camelot's own on the holder, so a fade or
-- a scale on the holder carries it, and every style the X component offered
-- on its overlays is offered here, Deep Shadow included.
--
-- The zone text and the clock are the cluster's two header pieces in
-- Blizzard's image (frames.xml): the zone button opens the world map and
-- shows the zone tooltip, the clock opens the stopwatch. "dock" keeps each at
-- Blizzard's anchor on the plate; the nine points pin it to the map's side.
--------------------------------------------------------------------------------

local addonName, addon = ...

local MR = addon.MinimapReplica
local Style = MR.Style

local Text = {}
MR.Text = Text

-- A map-wide text at one of the nine points: pinned to the side the point
-- names, inset from the edge; a top position drops below the border band,
-- which covers the first pixels of the map.
local MAP_TEXT_INSET_X = 6
local MAP_TEXT_TOP_DROP = 6
local MAP_TEXT_HEIGHT = 20

local COORDS_INTERVAL = 0.2
local CLOCK_INTERVAL = 1
local SYSTEM_DATA_INTERVAL = 2

local FORMAT_TENTHS = "%.1f, %.1f"
local FORMAT_INTEGER = "%d, %d"

local frames = {}      -- coords, systemData: the two frames built in Lua
local tickers = {}     -- coords, clock, systemData

--------------------------------------------------------------------------------
-- Placement
--------------------------------------------------------------------------------

-- The string is left at its text's own size (a width of 0 lets it size to
-- the text), so the anchor alone places it. The zone text's XML gives its
-- string the dock's fixed 130 px width, and a fixed-width string sits where
-- its justification puts it, which the first look showed as the zone text
-- staying left at Top and Top-Right; the dock branch puts the width back.
local function placeMapText(frame, fs, holder, position, offsetX, offsetY)
    local inset, justify = 0, "CENTER"
    if position:find("LEFT") then
        inset, justify = MAP_TEXT_INSET_X, "LEFT"
    elseif position:find("RIGHT") then
        inset, justify = -MAP_TEXT_INSET_X, "RIGHT"
    end
    local drop = position:find("TOP") and -MAP_TEXT_TOP_DROP or 0
    frame:ClearAllPoints()
    frame:SetPoint(position, holder, position, offsetX, offsetY + drop)
    frame:SetSize(holder:GetWidth() - 10, MAP_TEXT_HEIGHT)
    fs:ClearAllPoints()
    fs:SetSize(0, 0)
    fs:SetPoint(justify, frame, justify, inset, 0)
    fs:SetJustifyH(justify)
end
Text.PlaceMapText = placeMapText

local function applyFont(fs, fontKey, sizeKey, styleKey, fallbackSize, fallbackStyle)
    local face = addon.ResolveFontFace(Style.Get(fontKey))
    local size = tonumber(Style.Get(sizeKey)) or fallbackSize
    local style = Style.Get(styleKey) or fallbackStyle
    addon.ApplyFontStyle(fs, face, size, style)
end

local function applyColor(fs, modeKey, colorKey)
    local r, g, b, a = addon.ResolveColorRGBA(Style.Get(modeKey), Style.Get(colorKey))
    fs:SetTextColor(r, g, b, a)
end

local function stopTicker(key)
    if tickers[key] then
        tickers[key]:Cancel()
        tickers[key] = nil
    end
end

local function startTicker(key, interval, fn)
    stopTicker(key)
    fn()
    tickers[key] = C_Timer.NewTicker(interval, fn)
end

--------------------------------------------------------------------------------
-- Zone text
--------------------------------------------------------------------------------

local function zonePVPInfo()
    -- C_PvP.GetZonePVPInfo is the live call and the bare global is Blizzard's
    -- compatibility alias, which a client loads only with the deprecated
    -- script addon. Either returns nothing in a zone with no PVP rule of its
    -- own, so the call cannot stand in an or-chain that ends in the global.
    local get = (C_PvP and C_PvP.GetZonePVPInfo) or _G.GetZonePVPInfo
    if not get then return nil end
    local ok, pvpType, isSubZonePvP, factionName = pcall(get)
    if not ok then return nil end
    return pvpType, isSubZonePvP, factionName
end

local function zoneTextColor(fs)
    local r, g, b, a
    if Style.Get("zoneTextColorMode") == "custom" then
        r, g, b, a = Style.Color("zoneTextCustomColor", { 1, 0.82, 0, 1 })
    else
        local pvpType = zonePVPInfo() or "normal"
        local color = Style.PVP_COLORS[pvpType] or Style.PVP_COLORS.normal
        r, g, b, a = color[1], color[2], color[3], color[4]
    end
    fs:SetTextColor(r, g, b, a)
end

--- The zone name and its color, on every zone event.
function Text.UpdateZoneText()
    local holder = Style.Frame()
    if not holder then return end
    local fs = holder.ZoneTextButton.Text
    local ok, text = pcall(GetMinimapZoneText)
    fs:SetText(ok and text or "")
    zoneTextColor(fs)
end

-- MinimapZoneTextButtonMixin:OnEnter, with Minimap_SetTooltip's lines, which
-- that function draws only for Blizzard's own button.
local function zoneTooltip(self)
    if C_GameRules and C_GameRules.IsGameRuleActive and Enum.GameRule and Enum.GameRule.WorldMapDisabled then
        local ok, disabled = pcall(C_GameRules.IsGameRuleActive, Enum.GameRule.WorldMapDisabled)
        if ok and disabled then return end
    end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    local zoneName, subzoneName = _G.GetZoneText(), _G.GetSubZoneText()
    if subzoneName == zoneName then subzoneName = "" end
    GameTooltip:AddLine(zoneName, 1, 1, 1)
    local pvpType, _, factionName = zonePVPInfo()
    if pvpType == "sanctuary" then
        GameTooltip:AddLine(subzoneName, 0.41, 0.8, 0.94)
        GameTooltip:AddLine(_G.SANCTUARY_TERRITORY, 0.41, 0.8, 0.94)
    elseif pvpType == "arena" then
        GameTooltip:AddLine(subzoneName, 1, 0.1, 0.1)
        GameTooltip:AddLine(_G.FREE_FOR_ALL_TERRITORY, 1, 0.1, 0.1)
    elseif pvpType == "friendly" then
        if factionName and factionName ~= "" then
            GameTooltip:AddLine(subzoneName, 0.1, 1, 0.1)
            GameTooltip:AddLine(format(_G.FACTION_CONTROLLED_TERRITORY, factionName), 0.1, 1, 0.1)
        end
    elseif pvpType == "hostile" then
        if factionName and factionName ~= "" then
            GameTooltip:AddLine(subzoneName, 1, 0.1, 0.1)
            GameTooltip:AddLine(format(_G.FACTION_CONTROLLED_TERRITORY, factionName), 1, 0.1, 0.1)
        end
    elseif pvpType == "contested" then
        GameTooltip:AddLine(subzoneName, 1, 0.7, 0)
        GameTooltip:AddLine(_G.CONTESTED_TERRITORY, 1, 0.7, 0)
    elseif pvpType == "combat" then
        GameTooltip:AddLine(subzoneName, 1, 0.1, 0.1)
        GameTooltip:AddLine(_G.COMBAT_ZONE, 1, 0.1, 0.1)
    else
        GameTooltip:AddLine(subzoneName, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
    end
    if _G.MicroButtonTooltipText and _G.WORLDMAP_BUTTON then
        GameTooltip:AddLine(_G.MicroButtonTooltipText(_G.WORLDMAP_BUTTON, "TOGGLEWORLDMAP"))
    end
    GameTooltip:Show()
end

function Text.ApplyZoneText()
    local holder = Style.Frame()
    if not holder then return end
    local button, fs = holder.ZoneTextButton, holder.ZoneTextButton.Text

    if Style.Get("zoneTextHide") == true then
        button:Hide()
        return
    end

    applyFont(fs, "zoneTextFont", "zoneTextFontSize", "zoneTextFontStyle", 12, "OUTLINE")

    local position = Style.Get("zoneTextPosition") or "dock"
    if position == "dock" then
        -- Blizzard's anchor on the plate; the plate's own text size.
        button:ClearAllPoints()
        button:SetPoint("LEFT", holder.Header, "LEFT", 4, 0)
        button:SetSize(135, 12)
        fs:ClearAllPoints()
        fs:SetSize(130, 12)
        fs:SetPoint("CENTER", button, "CENTER", 0, 1)
        fs:SetJustifyH("LEFT")
        button:SetShown(Style.Get("dockHide") ~= true)
    else
        placeMapText(button, fs, holder, position,
            tonumber(Style.Get("zoneTextOffsetX")) or 0, tonumber(Style.Get("zoneTextOffsetY")) or 0)
        button:Show()
    end
    Text.UpdateZoneText()
end

--------------------------------------------------------------------------------
-- Coordinates
--------------------------------------------------------------------------------
-- Blizzard draws a readout from 12.1.5 on (MinimapContainer.PlayerCoords),
-- parked with the cluster here; the replica's own string stands at its spot
-- under the map by default. The two switches are Blizzard's CVars where the
-- client has them, so the Show Coordinates toggle is Blizzard's own option
-- there, and profile keys elsewhere.

local CVARS = {
    show = "minimapShowPlayerCoords",
    tenths = "coordsByTenths",
}

--- The CVar's value as a boolean, or nil on a client that does not define it.
function Text.CoordsCVar(name)
    local cvar = CVARS[name]
    if not cvar or not (C_CVar and C_CVar.GetCVar) then return nil end
    local ok, value = pcall(C_CVar.GetCVar, cvar)
    if not ok or value == nil then return nil end
    return value == "1"
end

function Text.SetCoordsCVar(name, on)
    local cvar = CVARS[name]
    if not cvar or not (C_CVar and C_CVar.SetCVar) then return end
    -- Kept off core/profiles/cvars.lua: a passthrough to Blizzard's own checkbox, stored nowhere in the profile.
    pcall(C_CVar.SetCVar, cvar, on and "1" or "0")
end

function Text.IsCoordsCVar(cvar)
    return cvar == CVARS.show or cvar == CVARS.tenths
end

local function coordsShown()
    local v = Text.CoordsCVar("show")
    if v == nil then v = Style.Get("coordsEnabled") end
    return v == true
end

local function coordsByTenths()
    local v = Text.CoordsCVar("tenths")
    if v == nil then v = Style.Get("coordsTenths") end
    return v == true
end

local function updateCoordinates()
    local frame = frames.coords
    if not (frame and frame:IsShown()) then return end
    local fs = frame.Text
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    local pos
    if ok and mapID then
        local ok2, p = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
        if ok2 then pos = p end
    end
    local x, y
    if pos then x, y = pos:GetXY() end
    if not x or not y or (x == 0 and y == 0) then
        fs:SetText("")
        return
    end
    if frame.tenths then
        fs:SetFormattedText(FORMAT_TENTHS, x * 100, y * 100)
    else
        fs:SetFormattedText(FORMAT_INTEGER, math.floor(x * 100 + 0.5), math.floor(y * 100 + 0.5))
    end
end

function Text.ApplyCoordinates()
    local holder = Style.Frame()
    local frame = frames.coords
    if not (holder and frame) then return end
    stopTicker("coords")

    if not coordsShown() then
        frame:Hide()
        return
    end

    local fs = frame.Text
    applyFont(fs, "coordsFont", "coordsFontSize", "coordsFontStyle", 10, "SHADOW")
    applyColor(fs, "coordsColorMode", "coordsCustomColor")

    local position = Style.Get("coordsPosition") or "default"
    if position == "default" then
        local d = Style.COORDS_DEFAULT
        placeMapText(frame, fs, holder, d.point, d.x, d.y)
    else
        placeMapText(frame, fs, holder, position,
            tonumber(Style.Get("coordsOffsetX")) or 0, tonumber(Style.Get("coordsOffsetY")) or 0)
    end
    frame.tenths = coordsByTenths()
    frame:Show()
    startTicker("coords", COORDS_INTERVAL, updateCoordinates)
end

--------------------------------------------------------------------------------
-- Clock
--------------------------------------------------------------------------------

local function clockText()
    local hour, minute
    if Style.Get("clockTimeSource") == "server" then
        hour, minute = GetGameTime()
    else
        hour, minute = tonumber(date("%H")), tonumber(date("%M"))
    end
    hour, minute = hour or 0, minute or 0
    if Style.Get("clockUse24Hour") == true then
        return string.format("%02d:%02d", hour, minute)
    end
    local suffix = hour >= 12 and "PM" or "AM"
    hour = hour % 12
    if hour == 0 then hour = 12 end
    return string.format("%d:%02d %s", hour, minute, suffix)
end

local function updateClock()
    local holder = Style.Frame()
    if not holder then return end
    holder.Clock.Ticker:SetText(clockText())
end

-- TimeManagerClockButton_OnEnter draws the tooltip from its own OnUpdate;
-- GameTime_UpdateTooltip is the function that fills it, where the client
-- loads Blizzard_TimeManager.
local function clockTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if _G.GameTime_UpdateTooltip then
        pcall(_G.GameTime_UpdateTooltip)
    else
        GameTooltip:SetText(clockText())
    end
    GameTooltip:Show()
end

local function clockClick()
    if _G.TimeManager_Toggle then
        pcall(_G.TimeManager_Toggle)
    end
end

function Text.ApplyClock()
    local holder = Style.Frame()
    if not holder then return end
    local button, fs = holder.Clock, holder.Clock.Ticker
    stopTicker("clock")

    if Style.Get("clockHide") == true then
        button:Hide()
        return
    end

    applyFont(fs, "clockFont", "clockFontSize", "clockFontStyle", 12, "OUTLINE")
    applyColor(fs, "clockColorMode", "clockCustomColor")

    local position = Style.Get("clockPosition") or "dock"
    if position == "dock" then
        button:ClearAllPoints()
        button:SetPoint("TOPRIGHT", holder.Header, "TOPRIGHT", -4, 0)
        button:SetSize(40, 16)
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", button, "CENTER", 3, 1)
        fs:SetJustifyH("CENTER")
        button:SetShown(Style.Get("dockHide") ~= true)
    else
        placeMapText(button, fs, holder, position,
            tonumber(Style.Get("clockOffsetX")) or 0, tonumber(Style.Get("clockOffsetY")) or 0)
        button:Show()
    end
    startTicker("clock", CLOCK_INTERVAL, updateClock)
end

--------------------------------------------------------------------------------
-- System data
--------------------------------------------------------------------------------

local function updateSystemData()
    local frame = frames.systemData
    if not (frame and frame:IsShown()) then return end
    local parts = {}
    if Style.Get("systemDataShowFPS") == true then
        parts[#parts + 1] = string.format("%d FPS", math.floor(GetFramerate()))
    end
    if Style.Get("systemDataShowLatency") == true then
        local _, _, latencyHome, latencyWorld = GetNetStats()
        local latency = Style.Get("systemDataLatencySource") == "world" and latencyWorld or latencyHome
        parts[#parts + 1] = string.format("%d MS", latency or 0)
    end
    frame.Text:SetText(table.concat(parts, " | "))
end

function Text.ApplySystemData()
    local holder = Style.Frame()
    local frame = frames.systemData
    if not (holder and frame) then return end
    stopTicker("systemData")

    if Style.Get("systemDataShowFPS") ~= true and Style.Get("systemDataShowLatency") ~= true then
        frame:Hide()
        return
    end

    local fs = frame.Text
    applyFont(fs, "systemDataFont", "systemDataFontSize", "systemDataFontStyle", 11, "OUTLINE")
    applyColor(fs, "systemDataColorMode", "systemDataCustomColor")

    placeMapText(frame, fs, holder, Style.Get("systemDataAnchor") or "BOTTOM",
        tonumber(Style.Get("systemDataOffsetX")) or 0, tonumber(Style.Get("systemDataOffsetY")) or -18)
    frame:Show()
    startTicker("systemData", SYSTEM_DATA_INTERVAL, updateSystemData)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function textFrame(holder)
    local frame = CreateFrame("Frame", nil, holder)
    frame:SetHeight(MAP_TEXT_HEIGHT)
    frame:EnableMouse(false)
    frame:SetFrameLevel(holder:GetFrameLevel() + 4)
    frame.Text = frame:CreateFontString(nil, "OVERLAY")
    frame.Text:SetPoint("CENTER")
    frame.Text:SetJustifyH("CENTER")
    frame:Hide()
    return frame
end

--- The two Lua-built frames and the scripts on the XML's two buttons. Once,
--- from display.lua's Build.
function Text.Build(holder)
    if frames.coords then return end
    frames.coords = textFrame(holder)
    frames.systemData = textFrame(holder)

    local zone = holder.ZoneTextButton
    zone:SetScript("OnClick", function()
        if _G.ToggleWorldMap then pcall(_G.ToggleWorldMap) end
    end)
    zone:SetScript("OnEnter", zoneTooltip)
    zone:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local clock = holder.Clock
    clock:SetScript("OnClick", clockClick)
    clock:SetScript("OnEnter", clockTooltip)
    clock:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local owner = MR.OWNER .. ".zone"
    addon.Events.On(owner, "ZONE_CHANGED", Text.UpdateZoneText)
    addon.Events.On(owner, "ZONE_CHANGED_INDOORS", Text.UpdateZoneText)
    addon.Events.On(owner, "ZONE_CHANGED_NEW_AREA", Text.UpdateZoneText)
end

--- Lines for /camelot map.
function Text.Describe(push)
    local holder = Style.Frame()
    if not holder then return end
    push("  zone text: position %s, hide %s, shown %s; clock: position %s, hide %s, shown %s",
        tostring(Style.Get("zoneTextPosition")), tostring(Style.Get("zoneTextHide")), tostring(holder.ZoneTextButton:IsShown()),
        tostring(Style.Get("clockPosition")), tostring(Style.Get("clockHide")), tostring(holder.Clock:IsShown()))
    push("  coordinates: cvar show %s tenths %s, position %s, shown %s; system data shown %s",
        tostring(Text.CoordsCVar("show")), tostring(Text.CoordsCVar("tenths")), tostring(Style.Get("coordsPosition")),
        tostring(frames.coords and frames.coords:IsShown()), tostring(frames.systemData and frames.systemData:IsShown()))
end
