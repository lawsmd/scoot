--------------------------------------------------------------------------------
-- forever/unitframes/combopoints.lua
-- Combo points on the target frame, in either style: vanilla's ComboFrame,
-- which this client draws over its own target frame, rebuilt on the frame
-- Camelot draws, with Blizzard's ComboFrame parked beside TargetFrame
-- (suppression.lua). Both styles hang the row at the spot vanilla and the
-- client's override give it, TOPRIGHT -26, -13 of a 232 by 100 frame.
--
-- The art is vanilla's Interface\ComboFrame\ComboPoint, three slices of one
-- file at ComboFrame.xml's coords: the socket, the highlight that fills it,
-- and an additive shine.
--
-- The feed is secret-safe by construction. Each point's highlight is
-- anchored to the fill of a StatusBar ranged (i - 1, i), and every bar is
-- fed the raw count, so the i-th highlight has its width when the count
-- reaches i and none before, with no compare. The whole row sits in a frame
-- that clips its children, whose right edge is the fill of one more bar
-- ranged (0, 1): no points, no row, as vanilla hides the frame at 0. Where
-- the count reads plain, vanilla's fades run as well: the row fades in, and
-- each point gained fades its highlight in and flashes its shine.
--
-- The count is GetComboPoints("player", "target"), vanilla's call, and
-- UnitPower in combo points where that is missing; the game rule
-- SingleTargetComboPoints makes points per target, so a target change
-- refeeds. The row is a function of the player and the target, and the
-- target frame's own hide takes it with the frame.
--
-- The Personal Resource Display draws its own row in retail's art
-- (forever/personalresourcedisplay/combopoints.lua) on this file's count and
-- events: ComboPoints.ReadCount, ReadMax and Track.
--------------------------------------------------------------------------------

local addonName, addon = ...

local UF = addon.UnitFrames

local ComboPoints = {}
UF.ComboPoints = ComboPoints

local OWNER = "camelotComboPoints"
local FILE = "Interface\\ComboFrame\\ComboPoint"

-- ComboFrame.xml: each point's TOPRIGHT against the row's TOPRIGHT.
local OFFSETS = { { 0, 0 }, { 7, -8 }, { 12, -18 }, { 14, -29 }, { 13, -40 } }
local MAX_POINTS = #OFFSETS

-- ComboFrame.lua's timings.
local FADE_IN = 0.3
local HIGHLIGHT_FADE_IN = 0.4
local SHINE_FADE_IN = 0.3
local SHINE_FADE_OUT = 0.4

-- The clip box around the arc's art, from the row's TOPRIGHT: the sockets
-- run 12 left of their anchors and 16 down, and the shine 4 up and 2 right.
local BOX = { left = -14, top = 6, width = 32, height = 64 }

local function plainCount(value)
    if type(value) ~= "number" or issecretvalue(value) then return nil end
    return value
end

local function readCount()
    if type(_G.GetComboPoints) == "function" then
        local ok, count = pcall(_G.GetComboPoints, "player", "target")
        if ok then return count end
    end
    local enum = Enum and Enum.PowerType and Enum.PowerType.ComboPoints
    if enum then
        local ok, count = pcall(UnitPower, "player", enum)
        if ok then return count end
    end
    return 0
end

local function readMax()
    local enum = Enum and Enum.PowerType and Enum.PowerType.ComboPoints
    if not enum then return MAX_POINTS end
    local ok, max = pcall(UnitPowerMax, "player", enum)
    max = ok and plainCount(max) or nil
    if not max or max < 1 then return MAX_POINTS end
    return math.min(max, MAX_POINTS)
end

-- A StatusBar used for its fill's edge alone: nothing draws on it.
local function gauge(parent, low, high)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(FILE)
    bar:SetStatusBarColor(0, 0, 0, 0)
    bar:SetMinMaxValues(low, high)
    bar:SetValue(low)
    return bar
end

local function fadeGroup(region, from, to, duration)
    local group = region:CreateAnimationGroup()
    local anim = group:CreateAnimation("Alpha")
    anim:SetFromAlpha(from)
    anim:SetToAlpha(to)
    anim:SetDuration(duration)
    group:SetToFinalAlpha(true)
    return group, anim
end

-- One point: the socket, the highlight over the fill of its gauge, the
-- shine. Slices and offsets as ComboPointTemplate cuts them.
local function buildPoint(box, row, i)
    local point = CreateFrame("Frame", nil, box)
    point:SetSize(12, 12)
    point:SetPoint("TOPRIGHT", row, "TOPRIGHT", OFFSETS[i][1], OFFSETS[i][2])

    local socket = point:CreateTexture(nil, "BACKGROUND")
    socket:SetTexture(FILE)
    socket:SetSize(12, 16)
    socket:SetPoint("TOPLEFT")
    socket:SetTexCoord(0, 0.375, 0, 1)

    -- The highlight's own rect, 8 by 16 at 2 in; its right edge follows the
    -- gauge's fill, so it has its width or none.
    local g = gauge(point, i - 1, i)
    g:SetSize(8, 16)
    g:SetPoint("TOPLEFT", 2, 0)
    local highlight = point:CreateTexture(nil, "ARTWORK")
    highlight:SetTexture(FILE)
    highlight:SetTexCoord(0.375, 0.5625, 0, 1)
    highlight:SetPoint("TOPLEFT", g, "TOPLEFT")
    highlight:SetPoint("BOTTOMRIGHT", g:GetStatusBarTexture(), "BOTTOMRIGHT")

    local shine = point:CreateTexture(nil, "OVERLAY")
    shine:SetTexture(FILE)
    shine:SetBlendMode("ADD")
    shine:SetSize(14, 16)
    shine:SetPoint("TOPLEFT", 0, 4)
    shine:SetTexCoord(0.5625, 1, 0, 1)
    shine:SetAlpha(0)

    point.gauge = g
    point.highlight = highlight
    point.shine = shine
    point.highlightIn = fadeGroup(highlight, 0, 1, HIGHLIGHT_FADE_IN)
    local shineIn = fadeGroup(shine, 0, 1, SHINE_FADE_IN)
    local shineOut = fadeGroup(shine, 1, 0, SHINE_FADE_OUT)
    point.highlightIn:SetScript("OnFinished", function() shineIn:Play() end)
    shineIn:SetScript("OnFinished", function() shineOut:Play() end)
    point.shineIn, point.shineOut = shineIn, shineOut
    return point
end

local function stopFades(point)
    point.highlightIn:Stop()
    point.shineIn:Stop()
    point.shineOut:Stop()
    point.highlight:SetAlpha(1)
    point.shine:SetAlpha(0)
end

--- A row of points on parent, placed where anchor says: { point, relTo,
--- relPoint, x, y }. Returns the row; row:Feed() reads and paints, and the
--- row feeds itself whenever it becomes visible.
function ComboPoints.CreateRow(parent, anchor)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(256, 32)
    row:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])

    local any = gauge(row, 0, 1)
    any:SetPoint("TOPLEFT", row, "TOPRIGHT", BOX.left, BOX.top)
    any:SetSize(BOX.width, BOX.height)

    local box = CreateFrame("Frame", nil, row)
    box:SetClipsChildren(true)
    box:SetPoint("TOPLEFT", any, "TOPLEFT")
    box:SetPoint("BOTTOMLEFT", any, "BOTTOMLEFT")
    box:SetPoint("RIGHT", any:GetStatusBarTexture(), "RIGHT")

    row.any = any
    row.box = box
    row.points = {}
    for i = 1, MAX_POINTS do row.points[i] = buildPoint(box, row, i) end
    row.fadeIn = fadeGroup(box, 0, 1, FADE_IN)
    row.last = 0

    function row:Feed()
        local count = readCount()
        local max = readMax()
        for i, point in ipairs(self.points) do
            point:SetShown(i <= max)
            point.gauge:SetValue(count)
        end
        self.any:SetValue(count)

        local known = plainCount(count)
        if not known then
            -- The pips stand as fed; no fades without a plain count.
            for _, point in ipairs(self.points) do stopFades(point) end
            self.last = nil
            return
        end
        local last = self.last or known
        if known > 0 and last == 0 then self.fadeIn:Play() end
        for i, point in ipairs(self.points) do
            if i <= known and i > last then
                point.highlightIn:Play()
            elseif i > known then
                stopFades(point)
            end
        end
        self.last = known
    end

    function row:Clear()
        self.any:SetValue(0)
        for _, point in ipairs(self.points) do
            point.gauge:SetValue(0)
            stopFades(point)
        end
        self.last = 0
    end

    -- A count gained while a parent hid the row was never painted.
    row:SetScript("OnShow", function(self) self:Feed() end)

    return row
end

--------------------------------------------------------------------------------
-- The target frame's row
--------------------------------------------------------------------------------

-- Keyed by owner: a target frame instance, or the row itself for a row
-- another file built (ComboPoints.Track).
local rows = {}

local function feedAll()
    for _, row in pairs(rows) do
        if row:IsVisible() then row:Feed() end
    end
end

local wired = false
local function wire()
    if wired then return end
    wired = true
    addon.Events.On(OWNER, "PLAYER_TARGET_CHANGED", feedAll)
    addon.Events.On(OWNER, "PLAYER_ENTERING_WORLD", feedAll)
    pcall(addon.Events.On, OWNER, "COMBO_TARGET_CHANGED", feedAll)
    -- Kept off addon.Events: RegisterUnitEvent filters to the player in C.
    local f = CreateFrame("Frame")
    f:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    f:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    f:SetScript("OnEvent", feedAll)
end

--- The player's combo points on the target, possibly secret.
ComboPoints.ReadCount = readCount

--- The most points the row draws, a plain number.
ComboPoints.ReadMax = readMax

--- Put a row another file built on the shared feed: the player's power
--- events and the target changes refeed it while it is visible. The row
--- has a Feed method.
function ComboPoints.Track(row)
    rows[row] = row
    wire()
end

--- "count N, max M" for a row's debug line; the count reads "secret" when
--- it is one.
function ComboPoints.DescribeCount()
    local count = readCount()
    return string.format("count %s, max %d",
        issecretvalue(count) and "secret" or tostring(count), readMax())
end

--- Build or show the row a frame's settings ask for, or hide it. Frame.Build
--- and the settings pass; a frame whose key has no row is left alone.
function ComboPoints.Apply(inst)
    if not UF.Settings.COMBO_POINTS[inst.key] then return end
    local row = rows[inst]
    local want = UF.ShowComboPoints(inst.key) and not inst.previewStandIn
    if not want then
        if row then
            row:Clear()
            row:Hide()
        end
        return
    end
    if not row then
        row = ComboPoints.CreateRow(inst.artFrame, { "TOPRIGHT", inst.frame, "TOPRIGHT", -26, -13 })
        rows[inst] = row
        wire()
    end
    row:Show()
    row:Feed()
end

--- A line for /camelot state.
function ComboPoints.Describe(inst)
    if not UF.Settings.COMBO_POINTS[inst.key] then return nil end
    local row = rows[inst]
    if not row then return "not built" end
    return string.format("%s, %s", row:IsShown() and "shown" or "hidden", ComboPoints.DescribeCount())
end
