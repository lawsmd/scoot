--------------------------------------------------------------------------------
-- forever/personalresourcedisplay/combopoints.lua
-- Combo points on the Personal Resource Display, for a Rogue and for a Druid
-- in Cat Form: the class bar retail's PRD hangs in its class container and
-- Forever's leaves out. A Camelot addition, on for every spec until one is
-- switched off (the Resource page, Style.ResourceOn), in one of two looks.
--
-- The CamelotAuras look, the default (Style.ResourceAurasStyle): a Class
-- Resource tracker's segmented bar in Camelot's look, drawn by the tracker's
-- own painter (scootauras/classresource.lua, CreateSegment and
-- LayoutSegments) at addon.AurasHost.barLook, as wide and tall as the power
-- bar and joined to its top, or its bottom by a setting. Where the two meet
-- they share one edge: the bar draws one frame around both, in the joined
-- bar's background color, with addon.Media.ApplyBarSeam between them, and
-- the joined bar's own frame stands aside (style.lua). Joined on
-- top, the frame makes room over the power bar (mixins.lua,
-- SetClassBarHeight); joined under, the bar hangs off the frame's bottom as
-- the retail row does. With the power bar hidden it joins the health bar's
-- bottom.
--
-- The retail look's art and geometry, from RogueComboPointBar.xml and
-- DruidComboPointBar.xml: 20 by 20 points 4 apart, each a shadow, an empty
-- socket, a lit socket and an icon from the uf-roguecp and uf-druidcp
-- atlases, which the Forever client ships; the gain animation transcribed
-- from unchargedEmptyToUnchargedFull and activateAnim. The vertical place is
-- CLASS_FRAME_INFO_MAP's yOffset under the power bar, centered in the class
-- container's 15.
--
-- The feed is secret-safe as the unit frames' row is
-- (forever/unitframes/combopoints.lua), whose count and events it shares:
-- each point's lit socket and icon sit in a frame that clips its children,
-- whose right edge is the fill of a StatusBar ranged (i - 1, i) and fed the
-- raw count. Where the count reads plain, a point gained plays the
-- animation and the empty socket under it fades out.
--
-- Hung off the frame's bottom edge outside its height, as the cast bar is,
-- so the bars never move when it shows; a cast bar set Below hangs under it
-- (castbar.lua, _ApplyHostedPosition). Built with the display whatever the
-- settings say, so its Dynamic Layouts adapter has a frame from the start.
--------------------------------------------------------------------------------

local addonName, addon = ...

local PRD = addon.PersonalResourceDisplay
local Style = PRD.Style
local UF = addon.UnitFrames

local Combo = {}
PRD.Combo = Combo

-- Without the unit frames' count and art helpers the display draws no
-- combo points.
if not (UF and UF.ComboPoints and UF.ComboPoints.Track and UF.Art) then
    PRD.Combo = nil
    return
end

local ComboPoints = UF.ComboPoints
local Art = UF.Art
local Media = addon.Media
local ClassResource = addon.ScootAuras and addon.ScootAuras.ClassResource

local POINT_SIZE = 20
local MAX_POINTS = 5
-- The class container's height, which the bar centers in.
local CONTAINER_HEIGHT = 15
-- The clip around a point: the druid's lit socket is 22 square.
local CLIP_SIZE = 26
local GAUGE_TEXTURE = "Interface\\Buttons\\WHITE8X8"

-- Per class: the container's yOffset, the textures with their atlas and
-- offset, the slash flipbook, and the gain animation as { texture, from,
-- to, delay, duration } rows. The rogue's art is the default, for Edit Mode
-- on another class.
local ART = {
    ROGUE = {
        yOffset = -10,
        shadow = { atlas = "uf-roguecp-bg-shadow", y = -4 },
        inactive = "uf-roguecp-bg-dis",
        active = "uf-roguecp-bg",
        icon = "uf-roguecp-icon-red",
        glow = "uf-roguecp-bg",
        slash = { atlas = "uf-roguecp-slash-red", width = 43, height = 43, x = 0, y = 0,
                  rows = 3, columns = 6, frames = 17, duration = 0.57 },
        gain = {
            { "slash", 0, 1, 0, 0 },
            { "icon", 0, 0.5, 0, 0.1 },
            { "icon", 0.5, 1, 0.27, 0.27 },
            { "active", 0, 0, 0, 0.2 },
            { "active", 0, 1, 0.2, 0.17 },
            { "inactive", 1, 1, 0, 0.37 },
            { "inactive", 1, 0, 0.37, 0.1 },
            { "glow", 0, 1, 0, 0.17 },
            { "glow", 1, 0, 0.17, 0.4 },
        },
    },
    DRUID = {
        yOffset = -8,
        shadow = { atlas = "UF-DruidCP-BG-Shadow", y = -2 },
        inactive = "UF-DruidCP-BG-Dis",
        active = "UF-DruidCP-BG-Active",
        icon = "UF-DruidCP-Icon",
        glow = "UF-DruidCP-BG-Glow",
        slash = { atlas = "UF-DruidCP-Slash", width = 26, height = 41, x = 1, y = 3,
                  rows = 3, columns = 8, frames = 20, duration = 1 },
        gain = {
            { "slash", 0, 1, 0, 0 },
            { "icon", 0, 0.5, 0, 0.1 },
            { "icon", 0.5, 1, 0.47, 0.2 },
            { "active", 0, 0, 0, 0.27 },
            { "active", 0, 1, 0.27, 0.01 },
            { "inactive", 1, 1, 0, 0.27 },
            { "inactive", 1, 0, 0.27, 0.01 },
            { "glow", 0, 0, 0, 0.17 },
            { "glow", 0, 1, 0.17, 0.13 },
            { "glow", 1, 0, 0.3, 0.4 },
        },
    },
}

local row
local art = ART.ROGUE

-- The CamelotAuras look, when the tracker's painter and Camelot's look are
-- loaded; without them the retail row draws.
local function barLook()
    local host = addon.AurasHost
    return ClassResource and ClassResource.LayoutSegments and host and host.barLook or nil
end

local function useBar()
    return Style.ResourceAurasStyle() and barLook() ~= nil
end

local function gap(frame)
    return frame.GetBarPadding and frame:GetBarPadding() or 4
end

local function plainCount(value)
    if type(value) ~= "number" or issecretvalue(value) then return nil end
    return value
end

local function plain(fn, ...)
    local ok, value = pcall(fn, ...)
    if not ok or issecretvalue(value) then return nil end
    return value
end

local function texture(parent, layer, sublevel, atlas, x, y)
    local tex = parent:CreateTexture(nil, layer, nil, sublevel)
    Art.SetAtlas(tex, atlas, true)
    tex:SetPoint("CENTER", parent, "CENTER", x or 0, y or 0)
    return tex
end

-- The gain: Blizzard's rows on one group, the slash's flipbook beside them.
local function buildGain(point)
    local group = point:CreateAnimationGroup()
    group:SetToFinalAlpha(true)
    for _, step in ipairs(art.gain) do
        local anim = group:CreateAnimation("Alpha")
        anim:SetTarget(point[step[1]])
        anim:SetFromAlpha(step[2])
        anim:SetToAlpha(step[3])
        anim:SetStartDelay(step[4])
        anim:SetDuration(step[5])
        anim:SetOrder(1)
    end
    local ok, flip = pcall(group.CreateAnimation, group, "FlipBook")
    if ok and flip then
        local s = art.slash
        flip:SetTarget(point.slash)
        flip:SetFlipBookRows(s.rows)
        flip:SetFlipBookColumns(s.columns)
        flip:SetFlipBookFrames(s.frames)
        flip:SetFlipBookFrameWidth(0)
        flip:SetFlipBookFrameHeight(0)
        flip:SetDuration(s.duration)
        flip:SetOrder(1)
    end
    group:SetScript("OnFinished", function() point.slash:SetAlpha(0) end)
    return group
end

local function buildPoint(parent, i)
    local point = CreateFrame("Frame", nil, parent)
    point:SetSize(POINT_SIZE, POINT_SIZE)

    point.shadow = texture(point, "BACKGROUND", 1, art.shadow.atlas, 0, art.shadow.y)
    point.inactive = texture(point, "BACKGROUND", 2, art.inactive)

    -- The lit socket and the icon, inside the clip whose right edge is the
    -- gauge's fill: the whole point at a count of i, nothing below it.
    local gauge = CreateFrame("StatusBar", nil, point)
    gauge:SetSize(CLIP_SIZE, CLIP_SIZE)
    gauge:SetPoint("CENTER")
    gauge:SetStatusBarTexture(GAUGE_TEXTURE)
    gauge:SetStatusBarColor(0, 0, 0, 0)
    gauge:SetMinMaxValues(i - 1, i)
    gauge:SetValue(i - 1)
    local clip = CreateFrame("Frame", nil, point)
    clip:SetClipsChildren(true)
    clip:SetPoint("TOPLEFT", gauge, "TOPLEFT")
    clip:SetPoint("BOTTOMLEFT", gauge, "BOTTOMLEFT")
    clip:SetPoint("RIGHT", gauge:GetStatusBarTexture(), "RIGHT")
    point.active = texture(clip, "BACKGROUND", 3, art.active)
    point.icon = texture(clip, "ARTWORK", 1, art.icon)
    point.active:SetPoint("CENTER", point, "CENTER")
    point.icon:SetPoint("CENTER", point, "CENTER")

    -- The glow and the slash over the clip, as Blizzard layers them over
    -- the lit socket and the icon.
    local fx = CreateFrame("Frame", nil, point)
    fx:SetAllPoints()
    fx:SetFrameLevel(clip:GetFrameLevel() + 1)
    point.glow = texture(fx, "BACKGROUND", 1, art.glow)
    point.glow:SetAlpha(0)
    local s = art.slash
    point.slash = fx:CreateTexture(nil, "OVERLAY")
    Art.SetAtlas(point.slash, s.atlas, false)
    point.slash:SetSize(s.width, s.height)
    point.slash:SetPoint("CENTER", fx, "CENTER", s.x, s.y)
    point.slash:SetAlpha(0)

    point.gauge = gauge
    point.gainAnim = buildGain(point)
    return point
end

-- A point at rest: lit and drawn by the clip, or empty. full nil is a count
-- that will not read, which leaves the empty socket under the lit one.
local function settle(point, full)
    point.gainAnim:Stop()
    point.active:SetAlpha(1)
    point.icon:SetAlpha(1)
    point.glow:SetAlpha(0)
    point.slash:SetAlpha(0)
    point.inactive:SetAlpha(full and 0 or 1)
end

-- The CamelotAuras bar: a background, the seam and the tracker's segments,
-- each segment's gate ranged (i - 1, i) and fed the raw count as the retail
-- points' gauges are. The seam has a frame of its own, over the fills
-- (placeBar).
local function buildBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetAllPoints()
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.seamHolder = CreateFrame("Frame", nil, bar)
    bar.seamHolder:SetAllPoints()
    bar.seam = bar.seamHolder:CreateTexture(nil, "ARTWORK")
    bar.segments = {}
    for i = 1, MAX_POINTS do
        local segment = ClassResource.CreateSegment(bar, bar)
        segment.bar:SetMinMaxValues(i - 1, i)
        segment.bar:SetValue(i - 1)
        bar.segments[i] = segment
    end
    bar:Hide()
    return bar
end

-- The bar look: as wide and tall as the power bar, the class color with
-- the tracker's crimson tail on the last two points.
local function layoutBar(self, max)
    local look = barLook()
    local width, height = Style.BarWidthPixels(), Style.Height("power")
    self:SetSize(width, height)
    for _, point in ipairs(self.points) do point:Hide() end
    local r, g, b = ClassResource.ResourceColorRGB()
    local segments = self.bar.segments
    ClassResource.LayoutSegments(segments, max, self.bar, {
        width = width, height = height,
        tickThickness = look.tickThickness, tickColor = look.tickColor,
        foreground = look.barForegroundTexture, background = look.barBackgroundTexture,
    }, r, g, b, 1, true)
    for i = max + 1, #segments do
        segments[i].bar:Hide()
        segments[i].tick:Hide()
    end
    self.bar:Show()
end

-- The points in a line, centered, as many as the max, at the spacing
-- setting; or the bar.
local function layout(self, max)
    local isBar = self.bar ~= nil and useBar()
    local spacing = Style.ResourceSpacing()
    local width, height = Style.BarWidthPixels(), Style.Height("power")
    if self.max == max and self.spacing == spacing and self.isBar == isBar
        and self.barWidth == width and self.barHeight == height then return end
    self.max, self.spacing, self.isBar, self.barWidth, self.barHeight = max, spacing, isBar, width, height
    if isBar then
        layoutBar(self, max)
        return
    end
    if self.bar then self.bar:Hide() end
    self:SetSize(max * POINT_SIZE + (max - 1) * spacing, POINT_SIZE)
    for i, point in ipairs(self.points) do
        point:ClearAllPoints()
        point:SetPoint("TOPLEFT", self, "TOPLEFT", (i - 1) * (POINT_SIZE + spacing), 0)
        point:SetShown(i <= max)
    end
end

local function feed(self)
    local count = ComboPoints.ReadCount()
    layout(self, ComboPoints.ReadMax())
    if self.isBar then
        for _, segment in ipairs(self.bar.segments) do segment.bar:SetValue(count) end
        return
    end
    for _, point in ipairs(self.points) do point.gauge:SetValue(count) end

    local known = plainCount(count)
    if not known then
        for _, point in ipairs(self.points) do settle(point, nil) end
        self.last = nil
        return
    end
    local last = self.last or known
    for i, point in ipairs(self.points) do
        if i <= known and i > last then
            settle(point, false)
            point.gainAnim:Play()
        elseif not point.gainAnim:IsPlaying() then
            settle(point, i <= known)
        end
    end
    self.last = known
end

local function clear(self)
    if self.bar then
        for _, segment in ipairs(self.bar.segments) do segment.bar:SetValue(0) end
    end
    for _, point in ipairs(self.points) do
        point.gauge:SetValue(0)
        settle(point, false)
    end
    self.last = 0
end

local function classHasPoints(class)
    return class == "ROGUE" or class == "DRUID"
end

-- A Rogue always; a Druid while its displayed power is energy, which is Cat
-- Form. A power type that will not read leaves the druid's row up.
local function formHasPoints(class)
    if class ~= "DRUID" then return true end
    local powerType = plain(UnitPowerType, "player")
    local energy = Enum and Enum.PowerType and Enum.PowerType.Energy
    return powerType == nil or powerType == energy
end

--- The row, once the display has built it.
function Combo.Row()
    return row
end

--- Whether the row shows: the player's spec switched on, and the form, except
--- in Edit Mode, where the spec alone shows it so it can be placed and seen.
function Combo.IsShown()
    if not PRD.IsEnabled() then return false end
    local _, class = UnitClass("player")
    if not (classHasPoints(class) and Style.ResourceOn(Style.CurrentResourceSpec())) then return false end
    local editing = addon.EditMode and addon.EditMode.IsEditing and addon.EditMode.IsEditing()
    return editing or formHasPoints(class)
end

-- The row's offset under the frame's bottom edge: the container's top at
-- the padding less the yOffset, then the points centered on its height,
-- which they overhang.
local function offset(frame)
    return gap(frame) - art.yOffset + (CONTAINER_HEIGHT - POINT_SIZE) / 2
end

--- Where the bar look joins while it shows: the bar it joins, "power" or
--- "health", and its side of that bar, "top" or "bottom". Nil for the retail
--- row, a hidden row, or both bars hidden. Settings alone, so style.lua can
--- ask before the row is laid out.
function Combo.Joint()
    if not (row and row.bar and useBar() and Combo.IsShown()) then return nil end
    if Style.Get("power", "hide") ~= true then
        return "power", Style.ResourceAttachBottom() and "bottom" or "top"
    end
    if Style.Get("health", "hide") ~= true then return "health", "bottom" end
    return nil
end

-- Whether the joint draws as one shared edge: both backgrounds the framed
-- atlas. Otherwise the bar keeps its whole frame at the same gap.
local function joined(target)
    local look = barLook()
    return target ~= nil and Style.BackgroundFramed(target)
        and Media.ResolveBarTextureAtlas(look and look.barBackgroundTexture) ~= nil
end

-- The bar look's gap to the bar it joins: none when they share an edge, else
-- the frame's bar padding, as between the health and power bars.
local function barGap(frame, target)
    if joined(target) then return 0 end
    return gap(frame)
end

--- Whether the combo point bar draws bar `key`'s frame around both bars, so
--- that bar's own background stands aside.
function Combo.Joins(key)
    local target = Combo.Joint()
    return target == key and joined(target)
end

--- How far the row reaches below the frame's bottom edge while it shows. 0
--- while hidden, and for the bar joined on top, which the frame holds.
function Combo.Extent()
    if not (row and Combo.IsShown()) then return 0 end
    if row.bar and useBar() then
        local target, side = Combo.Joint()
        if target and side == "bottom" then return barGap(Style.Frame(), target) + Style.Height("power") end
        return 0
    end
    return offset(Style.Frame()) + POINT_SIZE
end

--- From Display.Build.
function Combo.Build(frame)
    if row then return end
    local _, class = UnitClass("player")
    art = ART[class] or ART.ROGUE
    row = CreateFrame("Frame", nil, frame)
    row:SetHeight(POINT_SIZE)
    row.points = {}
    for i = 1, MAX_POINTS do row.points[i] = buildPoint(row, i) end
    if barLook() then row.bar = buildBar(row) end
    row.last = 0
    row.Feed = feed
    row.Clear = clear
    layout(row, MAX_POINTS)
    -- A count gained while a parent hid the row was never painted.
    row:SetScript("OnShow", feed)
    row:Hide()
    ComboPoints.Track(row)
end

-- The bar look's place: on or under the bar it joins, touching it inside one
-- frame with the seam between, or at the frame's top with both bars hidden.
-- The frame's room over the power bar first, so the anchors below read the
-- moved bar.
local function placeBar(frame)
    local target, side = Combo.Joint()
    local height = Style.Height("power")
    local isJoined = joined(target)
    local gapH = target and barGap(frame, target) or 0
    frame:SetClassBarHeight((target == "power" and side == "top") and (height + gapH) or 0)
    Style.ApplyBackgrounds()
    local bar, look = row.bar, barLook()
    -- Level with the bars' containers, so the frame around both, which
    -- crosses the joined bar's fill, draws under it; the seam over every fill.
    local level = Style.Container(frame, target or "power"):GetFrameLevel()
    row:SetFrameLevel(level)
    bar:SetFrameLevel(level)
    bar.seamHolder:SetFrameLevel(math.max(level + 2, bar.segments[1].clip:GetFrameLevel() + 1))
    if not target then
        row:SetPoint("TOP", frame, "TOP", 0, 0)
        Media.ApplyBarBackground(bar.bg, look.barBackgroundTexture, row)
        bar.bg:SetVertexColor(1, 1, 1, 1)
        bar.seam:Hide()
        return
    end
    local rect = Style.Container(frame, target)
    local upper, lower = rect, row
    if side == "top" then
        row:SetPoint("BOTTOM", rect, "TOP", 0, gapH)
        upper, lower = row, rect
    else
        row:SetPoint("TOP", rect, "BOTTOM", 0, -gapH)
    end
    if isJoined then
        Media.ApplyBarBackground(bar.bg, look.barBackgroundTexture, upper, { to = lower })
        bar.bg:SetVertexColor(Style.BackgroundColor(target))
        Media.ApplyBarSeam(bar.seam, look.barBackgroundTexture, upper)
    else
        Media.ApplyBarBackground(bar.bg, look.barBackgroundTexture, row)
        bar.bg:SetVertexColor(1, 1, 1, 1)
        bar.seam:Hide()
    end
end

--- From Style.Apply, a shapeshift, a spec change and Edit Mode's enter and
--- exit: the anchor at the current spacing, or the bar look's joint, the
--- shown state, the paint, then the cast bar's place under it.
function Combo.Apply()
    if not row then return end
    local frame = Style.Frame()
    row:ClearAllPoints()
    if row.bar and useBar() then
        placeBar(frame)
    else
        frame:SetClassBarHeight(0)
        Style.ApplyBackgrounds()
        row:SetPoint("TOP", frame, "BOTTOM", 0, -offset(frame))
    end
    local shown = Combo.IsShown()
    row:SetShown(shown)
    if shown then
        row:Feed()
    else
        row:Clear()
    end
    local castBar = PRD.CastBar and PRD.CastBar.Bar()
    if castBar and addon.CastBarZ and addon.CastBarZ._ApplyHostedPosition then
        addon.CastBarZ._ApplyHostedPosition(castBar)
    end
end

--- The selection box's reach, grown over the row while it shows: the bar
--- look under the power bar with its background's overhang below it.
function Combo.Reach(base)
    local extent = Combo.Extent()
    if extent == 0 then return base end
    if row.bar and useBar() then extent = extent + base.bottom end
    return { left = base.left, right = base.right, top = base.top,
             bottom = math.max(base.bottom, extent) }
end

--- A line for /camelot prd.
function Combo.Describe(push)
    local _, class = UnitClass("player")
    local spec = Style.CurrentResourceSpec()
    local target, side = Combo.Joint()
    push("  combo points: class %s, spec %s %s, form %s, built %s, shown %s; %s",
        tostring(class), tostring(spec), Style.ResourceOn(spec) and "on" or "off",
        tostring(formHasPoints(class)), tostring(row ~= nil), tostring(row and row:IsShown() or false),
        ComboPoints.DescribeCount())
    push("  combo look: %s, joins %s %s, shared edge %s", useBar() and "CamelotAuras bar" or "retail row",
        tostring(target), tostring(side), tostring(joined(target)))
end

-- A spec change switches the row with the spec's setting.
pcall(addon.Events.On, PRD.OWNER .. "Combo", "PLAYER_SPECIALIZATION_CHANGED", function()
    if PRD.Display and PRD.Display.RefreshComboPoints then PRD.Display.RefreshComboPoints() end
end)
