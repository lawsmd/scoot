--------------------------------------------------------------------------------
-- forever/minimap/display.lua
-- The minimap replica: CamelotMinimap holding Blizzard's Minimap widget on a
-- lease, MinimapCluster parked, the map's shape, size, border and header,
-- and /camelot map.
--
-- The Minimap widget is an engine singleton: Blizzard's XML declares the one
-- <Minimap> and nothing can create a second. So the replica is a holder of
-- Camelot's own that takes the widget by one SetParent, the write
-- addon.NativeFrame makes when it parks, and rebuilds the cluster's furniture
-- around it. Everything parented to the widget (its backdrop and ring, the
-- zoom buttons, HybridMinimap, every LibDBIcon button) rides along; the
-- cluster's own children (the header plate, zone text, tracking, mail, the
-- clock, on Forever the coordinates and the day-night dial) stay behind in
-- the parked cluster and are Camelot's twins here.
--
-- Edit Mode's handlers for the cluster (SetEditModeScale, SetHeaderUnderneath,
-- ApplySystemAnchor) move the cluster and its container and never the
-- widget's parent or points, so the lease holds through a layout apply.
-- Blizzard's Icon Scale slider still reaches the widget; Size and Header
-- Underneath act on the parked cluster, and the page says so.
--------------------------------------------------------------------------------

local addonName, addon = ...

local MR = addon.MinimapReplica
local Style = MR.Style

local Display = {}
MR.Display = Display

local OWNER = MR.OWNER

local built = false
local claimed = false
local appliedSquare = false
local savedMinimapShape      -- the global GetMinimapShape before the override, if any
local savedMinimapShapeSet = false
local overlays = {}          -- artBorder, border
local leaseLog = { count = 0 }
local blocked = {}           -- the last blocked actions naming the map or the cluster
local MAX_BLOCKED = 8

--------------------------------------------------------------------------------
-- The lease
--------------------------------------------------------------------------------
-- One SetParent, out of combat, then the widget centred on the holder. Run at
-- build and at the top of every apply, so a widget that leaves the holder
-- comes back on the next pass; never from a hook on the widget. Blizzard's
-- Lua never re-parents the widget, so no pass is expected to find it gone.

local function minimap()
    return _G.Minimap
end

function Display.Lease(reason)
    local map, holder = minimap(), Style.Frame()
    if not (map and holder) then return false end
    local ok, parent = pcall(map.GetParent, map)
    if ok and parent == holder then return true end
    if InCombatLockdown() then
        addon.Events.RunOutOfCombat(function() Display.Lease(reason .. " (regen)") end, OWNER .. ".lease")
        return false
    end
    local okParent, err = pcall(map.SetParent, map, holder)
    if okParent then
        pcall(map.ClearAllPoints, map)
        pcall(map.SetPoint, map, "CENTER", holder, "CENTER", 0, 0)
        -- The header and its text draw over the map (ApplyHeader levels them);
        -- the widget sits one above the holder, as a child does.
        pcall(map.SetFrameLevel, map, holder:GetFrameLevel() + 1)
    end
    leaseLog.count = leaseLog.count + 1
    leaseLog.last = { when = GetTime(), reason = reason, ok = okParent, err = okParent and nil or tostring(err) }
    return okParent
end

--------------------------------------------------------------------------------
-- The park
--------------------------------------------------------------------------------
-- MinimapCluster is a UIParent child and parks under the hidden holder. The
-- park's own SetParent hook re-parks the cluster alone, never its children,
-- so the leased widget is untouched. Never released: the Features switch
-- lands at reload, and a feature off at login never claims. The park is
-- skipped in combat and while Edit Mode is open, and paid by NativeFrame's
-- retry, so a reload in a fight shows the cluster's ring and header with no
-- map in them until regen.

function Display.Claim()
    if claimed or not MR.IsEnabled() then return end
    local target = _G.MinimapCluster
    if not (target and addon.NativeFrame) then return end
    if not addon.NativeFrame:IsSuppressed(target) then
        addon.NativeFrame:Suppress(target, OWNER, "park")
    end
    claimed = true
end

--------------------------------------------------------------------------------
-- Shape
--------------------------------------------------------------------------------
-- The X component's shape pass on the leased widget: the mask, the quest ring
-- alphas the engine draws at the map's edge (Blizzard's Lua never sets them,
-- so 1 is the restore value), the compass ring and Forever's underlay, the
-- GetMinimapShape global other addons read, and HybridMinimap's own mask.

local function setBlobRingAlpha(map, alpha)
    for _, method in ipairs({ "SetQuestBlobRingAlpha", "SetTaskBlobRingAlpha", "SetArchBlobRingAlpha" }) do
        if map[method] then pcall(map[method], map, alpha) end
    end
end

local function setCompassAlpha(alpha)
    if _G.MinimapCompassTexture then pcall(_G.MinimapCompassTexture.SetAlpha, _G.MinimapCompassTexture, alpha) end
    if _G.MinimapCompassTextureUnderlay then
        pcall(_G.MinimapCompassTextureUnderlay.SetAlpha, _G.MinimapCompassTextureUnderlay, alpha)
    end
end

local function setHybridMask(mask)
    local hybrid = _G.HybridMinimap
    if not hybrid then return end
    pcall(function()
        hybrid.MapCanvas:SetUseMaskTexture(false)
        if hybrid.CircleMask then hybrid.CircleMask:SetTexture(mask) end
        hybrid.MapCanvas:SetUseMaskTexture(true)
    end)
end

local function overrideMinimapShape(shape)
    if not savedMinimapShapeSet then
        savedMinimapShape = _G.GetMinimapShape
        savedMinimapShapeSet = true
    end
    if shape then
        _G.GetMinimapShape = function() return shape end
    else
        _G.GetMinimapShape = savedMinimapShape
    end
end

-- LibDBIcon places each button on the map's edge by the shape it reads.
local function refreshAddonButtons()
    local lib = LibStub and LibStub("LibDBIcon-1.0", true)
    if not (lib and lib.objects) then return end
    for name in pairs(lib.objects) do
        pcall(lib.Refresh, lib, name)
    end
end

function Display.ApplyShape()
    local map = minimap()
    if not map then return end
    local changed = false
    if Style.IsSquare() then
        map:SetMaskTexture(Style.SQUARE_MASK)
        setBlobRingAlpha(map, 0)
        setCompassAlpha(0)
        overrideMinimapShape("SQUARE")
        setHybridMask(Style.SQUARE_MASK)
        appliedSquare = true
        changed = true
    elseif appliedSquare then
        -- Only a map that was square goes back: the round mask is whatever
        -- the client drew, and Forever's skin re-applies its own on every
        -- rotateMinimap change.
        appliedSquare = false
        map:SetMaskTexture(Style.RoundMask())
        setBlobRingAlpha(map, 1)
        setCompassAlpha(1)
        overrideMinimapShape(nil)
        setHybridMask(Style.RoundMask())
        changed = true
    end
    if changed then
        C_Timer.After(0.1, refreshAddonButtons)
    end
end

--------------------------------------------------------------------------------
-- Size
--------------------------------------------------------------------------------
-- Map Size is the holder's scale. The positionable's offsets are in the
-- holder's own scale, so a scale change re-lands the position through the
-- store, which keeps the anchor point where it was (editmode.lua).

function Display.ApplySize()
    local holder = Style.Frame()
    if not holder then return end
    local scale = Style.Scale()
    local current = holder:GetScale()
    if math.abs(current - scale) < 0.0001 then return end
    holder:SetScale(scale)
    if MR.EditMode then MR.EditMode.OnScaleChanged() end
end

--------------------------------------------------------------------------------
-- Border
--------------------------------------------------------------------------------
-- A square map carries the art border unless the player asked for the solid
-- custom border or for none. Both are children of the holder, so a fade or a
-- scale on the holder carries them. The art border keeps the X component's
-- placement, BACKGROUND at 50: under the map, as Blizzard's ring is, and
-- under HybridMinimap's canvas, whose strata is fixed at BACKGROUND 100.

-- The band's inner edge is tucked this far under the map, so the map's masked
-- edge and the band's soft inner edge never leave a hairline between them.
-- The file's inner edge fades over about 2 px (opaque at 7.6 px from the
-- texture edge, gone at 10.1 at the 10 px band), so a 1 px tuck put the map
-- edge on the half-transparent part, and the first look showed a hairline
-- on the side whose edge landed on the wrong half of a physical pixel. At 3
-- the map edge lies on the opaque band at every phase.
local ART_BORDER_TUCK = 3

-- The file's outer edge fades too: alpha 0 at the edge, opaque from texel 7
-- of the 512 (measured off square-border.png). Camelot's default position
-- hangs that fade off the screen, so the opaque metal meets the screen edge;
-- one texel more covers a physical pixel's rounding.
local ART_BORDER_FILE_SIZE = 512
local ART_BORDER_OUTER_FADE = 8

--- How far in from the screen edge the map's own rect stands, in the
--- holder's units, when the art border's opaque edge lies on the screen edge.
--- The border is the holder's child, so the answer holds at every Map Size.
function Display.ArtBorderFlushInset()
    local outside = (tonumber(Style.SQUARE_BORDER.band) or 10) - ART_BORDER_TUCK
    local span = Style.MAP_SIZE_PX + outside * 2
    return outside - ART_BORDER_OUTER_FADE * span / ART_BORDER_FILE_SIZE
end

local function ensureArtBorder(holder)
    local container = overlays.artBorder
    if not container then
        container = CreateFrame("Frame", addon.Brand .. "MinimapSquareBorder", holder)
        container:EnableMouse(false)
        container:SetFrameStrata("BACKGROUND")
        container:SetFrameLevel(50)
        container.texture = container:CreateTexture(nil, "OVERLAY")
        container.texture:SetAllPoints(container)
        overlays.artBorder = container
    end
    local art = Style.SQUARE_BORDER
    local band = (tonumber(art.band) or 10) - ART_BORDER_TUCK
    container:ClearAllPoints()
    container:SetPoint("TOPLEFT", holder, "TOPLEFT", -band, band)
    container:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", band, -band)
    container.texture:SetTexture(art.texture)
    container:Show()
end

function Display.ApplyBorder()
    local holder, map = Style.Frame(), minimap()
    if not (holder and map) then return end

    local squareShown = Style.IsSquare() and Style.Get("borderHidden") ~= true
    local showCustom = squareShown and Style.Get("borderEnabled") == true
    local showArt = squareShown and not showCustom

    if overlays.artBorder and not showArt then overlays.artBorder:Hide() end
    if showArt then ensureArtBorder(holder) end

    if not showCustom then
        if overlays.border then overlays.border:Hide() end
        return
    end

    local thickness = Style.BorderThickness()
    local r, g, b, a = 0, 0, 0, 1
    if Style.Get("borderTintEnabled") == true then
        r, g, b, a = Style.Color("borderColor", { 0, 0, 0, 1 })
    end
    -- The engine owns the four edges. Its container is keyed by the frame
    -- the edges surround, created under UIParent; it is the holder's child
    -- from the first pass on.
    local _, container = addon.Borders.ApplySquare(map, {
        size = thickness,
        color = { r, g, b, a },
        layer = "BACKGROUND",
        containerStrata = "BACKGROUND",
        containerLevel = 1,
        expand = thickness,
        skipDimensionCheck = true,
    })
    if container and container:GetParent() ~= holder then
        container:SetParent(holder)
        container:SetFrameStrata("BACKGROUND")
        container:SetFrameLevel(1)
    end
    overlays.border = container
end

--------------------------------------------------------------------------------
-- Header
--------------------------------------------------------------------------------
-- The plate sits where BorderTop sits on the cluster: 5 right of the map's
-- centre and 40 above its top on retail, lower on a client whose ring is
-- taller, since the cluster sizes the map's container to the ring
-- (Style.HeaderOffset). Dock Hide hides the plate; the text on it follows
-- (text.lua).

function Display.ApplyHeader()
    local holder = Style.Frame()
    if not holder then return end
    local header = holder.Header
    local x, y = Style.HeaderOffset()
    header:ClearAllPoints()
    header:SetPoint("TOP", holder, "TOP", x, y)
    -- Over the map and its ring, which sit one level above the holder.
    local base = holder:GetFrameLevel()
    header:SetFrameLevel(base + 2)
    header.Plate:SetFrameLevel(base + 3)
    holder.ZoneTextButton:SetFrameLevel(base + 4)
    holder.Clock:SetFrameLevel(base + 4)
    header:SetShown(Style.Get("dockHide") ~= true)
end

--------------------------------------------------------------------------------
-- The default position
--------------------------------------------------------------------------------
-- Where Blizzard's map stood before the lease, as a TOPRIGHT record on
-- UIParent in UIParent's scale, read once at the first build. When the widget
-- has no rect yet, the cluster's XML geometry: the cluster TOPRIGHT at (0, 0)
-- and 256 wide, its container TOP at (10, -30) and as tall as the ring, the
-- map centred in it.

local captured

local function screenRect(frame)
    local ok, right, top, scale = pcall(function()
        return frame:GetRight(), frame:GetTop(), frame:GetEffectiveScale()
    end)
    if not ok or type(right) ~= "number" or type(top) ~= "number" or type(scale) ~= "number" then return nil end
    return right * scale, top * scale
end

function Display.CaptureDefault()
    if captured then return captured end
    local map = minimap()
    local mapRight, mapTop
    if map then mapRight, mapTop = screenRect(map) end
    local uiRight, uiTop = screenRect(UIParent)
    local uiScale = UIParent:GetEffectiveScale()
    if mapRight and uiRight and uiScale and uiScale > 0 then
        captured = {
            point = "TOPRIGHT",
            x = (mapRight - uiRight) / uiScale,
            y = (mapTop - uiTop) / uiScale,
            source = "the map's rect before the lease",
        }
    else
        local _, ringH = Style.RingSize()
        captured = {
            point = "TOPRIGHT",
            x = -(128 - 10) + Style.MAP_SIZE_PX / 2,
            y = -(30 + ringH / 2 - Style.MAP_SIZE_PX / 2),
            source = "the cluster's XML geometry",
        }
    end
    return captured
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

-- The bus hands a handler the event name first, then the payload.
local function onBlocked(event, addonNameBlocked, action)
    if type(action) ~= "string" then return end
    if not (action:find("Minimap", 1, true) or action:find("MinimapCluster", 1, true)) then return end
    table.insert(blocked, 1, string.format("%s %s %s at %.1f", event, tostring(addonNameBlocked), action, GetTime()))
    if #blocked > MAX_BLOCKED then table.remove(blocked) end
end

local function wireEvents()
    addon.Events.On(OWNER, "PLAYER_ENTERING_WORLD", function()
        if not built then return end
        Display.Lease("world")
        Display.Claim()
    end)
    -- Forever's minimap skin re-applies its own circle mask and swaps the
    -- compass ring whenever Rotate Minimap changes; put the square back. The
    -- coordinates' two switches are CVars where the client has Blizzard's
    -- readout, and Blizzard's own checkbox may flip them.
    addon.Events.On(OWNER, "CVAR_UPDATE", function(_, cvar)
        if not built then return end
        if cvar == "rotateMinimap" then
            if Style.IsSquare() then Display.ApplyShape() end
        elseif MR.Text and MR.Text.IsCoordsCVar(cvar) then
            MR.Text.ApplyCoordinates()
        end
    end)
    -- OnAddonLoaded runs its callback at once when the addon is already
    -- loaded; the shape pass is an idempotent re-apply.
    addon.Events.OnAddonLoaded("Blizzard_HybridMinimap", function()
        if built then Display.ApplyShape() end
    end)
    addon.Events.On(OWNER, "ADDON_ACTION_BLOCKED", onBlocked)
    addon.Events.On(OWNER, "ADDON_ACTION_FORBIDDEN", onBlocked)
end

function Display.Build()
    if built or not MR.IsEnabled() then return end
    local holder = Style.Frame()
    if not (holder and minimap()) then return end

    -- Kept off addon.Strata.ApplyHUD: the cluster is LOW, and LibDBIcon fixes
    -- every addon button at MEDIUM level 8, so a MEDIUM holder at a higher
    -- level would put the map over its own buttons.
    holder:SetFrameStrata("LOW")
    holder:SetFrameLevel(2)
    addon.RegisterPetBattleFrame(holder)

    Display.CaptureDefault()
    if MR.Text then MR.Text.Build(holder) end
    wireEvents()
    built = true

    -- The lease before the park, so the widget never sits under a hidden
    -- parent; the park before the positionable, so the cluster's own
    -- selection box is gone when Edit Mode next opens.
    Display.Lease("build")
    Display.Claim()
    holder:Show()
    Style.Apply()
    if MR.EditMode then MR.EditMode.Register(holder) end
    if MR.Dynamic then MR.Dynamic.Register(holder) end
end

function Display.IsBuilt()
    return built
end

function Display.Overlays()
    return overlays
end

addon.Events.OnWorldEntered(function()
    Display.Build()
end)

--------------------------------------------------------------------------------
-- /camelot map
--------------------------------------------------------------------------------
-- The minimap button already answers /camelot minimap.

local function frameLine(push, label, frame)
    if not frame then
        push("  %s: absent", label)
        return
    end
    local ok, text = pcall(function()
        local parent = frame:GetParent()
        local point, rel, relPoint, x, y = frame:GetPoint(1)
        return string.format("parent %s, shown %s, visible %s, alpha %.2f, scale %.2f, size %.0f x %.0f, strata %s level %d, point %s to %s %s (%.1f, %.1f)",
            parent and parent:GetName() or tostring(parent), tostring(frame:IsShown()), tostring(frame:IsVisible()),
            frame:GetAlpha(), frame:GetScale(), frame:GetWidth(), frame:GetHeight(),
            tostring(frame:GetFrameStrata()), frame:GetFrameLevel(),
            tostring(point), rel and rel.GetName and rel:GetName() or tostring(rel), tostring(relPoint), x or 0, y or 0)
    end)
    push("  %s: %s", label, ok and text or ("unreadable: " .. tostring(text)))
end

local function protectedLine(frame)
    if not frame then return "absent" end
    local ok, isProtected, explicitly = pcall(frame.IsProtected, frame)
    if not ok then return "unreadable" end
    return string.format("%s (explicit %s)", tostring(isProtected), tostring(explicitly))
end

local function existsLine(push, label, frame)
    push("  %s: %s", label, frame and "exists" or "nil")
end

function Display.Dump()
    local lines, push = addon.DebugLines()
    local holder, map, cluster = Style.Frame(), minimap(), _G.MinimapCluster
    push("Camelot minimap: enabled %s, built %s, lockdown %s, editing %s",
        tostring(MR.IsEnabled()), tostring(built), tostring(InCombatLockdown()),
        tostring(addon.EditMode and addon.EditMode.IsEditing and addon.EditMode.IsEditing()))
    frameLine(push, "holder", holder)
    frameLine(push, "Minimap", map)
    frameLine(push, "MinimapCluster", cluster)
    push("  Minimap protected: %s; MinimapCluster protected: %s", protectedLine(map), protectedLine(cluster))
    push("  cluster parked: %s", tostring(cluster and addon.NativeFrame and addon.NativeFrame:IsSuppressed(cluster)))
    push("  leases: %d; last %s", leaseLog.count, leaseLog.last and string.format("%s at %.1f, ok %s%s",
        leaseLog.last.reason, leaseLog.last.when, tostring(leaseLog.last.ok),
        leaseLog.last.err and (", " .. leaseLog.last.err) or "") or "none")
    local d = captured
    push("  default position: %s", d and string.format("%s (%.1f, %.1f) from %s", d.point, d.x, d.y, d.source) or "not captured")
    local ringW, ringH = Style.RingSize()
    local hx, hy = Style.HeaderOffset()
    push("  ring atlas %s: %d x %d; header offset (%d, %.1f); round mask %s",
        Style.RING_ATLAS, ringW, ringH, hx, hy, Style.RoundMask())
    push("  settings: shape %s, size %d%%, border enabled %s hidden %s, dock hide %s",
        tostring(Style.Get("mapShape")), Style.MapSize(), tostring(Style.Get("borderEnabled")),
        tostring(Style.Get("borderHidden")), tostring(Style.Get("dockHide")))
    push("  rotateMinimap %s", tostring(GetCVar and GetCVar("rotateMinimap")))
    push("  header pieces the client has:")
    existsLine(push, "GameTimeFrame", _G.GameTimeFrame)
    existsLine(push, "AddonCompartmentFrame", _G.AddonCompartmentFrame)
    existsLine(push, "InstanceDifficulty", cluster and cluster.InstanceDifficulty)
    existsLine(push, "TimeManagerClockButton", _G.TimeManagerClockButton)
    existsLine(push, "Tracking.Button", cluster and cluster.Tracking and cluster.Tracking.Button)
    existsLine(push, "IndicatorFrame.MailFrame", cluster and cluster.IndicatorFrame and cluster.IndicatorFrame.MailFrame)
    existsLine(push, "IndicatorFrame.CraftingOrderFrame", cluster and cluster.IndicatorFrame and cluster.IndicatorFrame.CraftingOrderFrame)
    existsLine(push, "MinimapContainer.PlayerCoords", cluster and cluster.MinimapContainer and cluster.MinimapContainer.PlayerCoords)
    existsLine(push, "DielFrame", cluster and cluster.DielFrame)
    existsLine(push, "HybridMinimap", _G.HybridMinimap)
    existsLine(push, "ExpansionLandingPageMinimapButton", _G.ExpansionLandingPageMinimapButton)
    if MR.Text then MR.Text.Describe(push) end
    if MR.Dynamic then push("  dynamic layouts: %s", MR.Dynamic.Describe()) end
    push("  blocked actions naming the map (%d):", #blocked)
    for _, line in ipairs(blocked) do push("    %s", line) end
    addon.DebugShowWindow("Camelot minimap", lines)
end

addon:RegisterSlashCommand({
    name = "map",
    help = "show the minimap replica: the holder, the leased widget, the parked cluster, the lease log and the blocked actions",
    handler = function() Display.Dump() end,
})
