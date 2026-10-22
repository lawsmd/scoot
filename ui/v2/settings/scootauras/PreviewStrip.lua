-- PreviewStrip.lua - The editor preview as a strip of the group's members
--
-- The ScootAura editor's preview quadrant shows the open tracker's group laid
-- out as the live group is (groups.lua): in memberOrder along the group's
-- grow axis, a horizontal row sharing a bottom edge or a vertical column
-- sharing a left edge, the group's spacing between members. The selected
-- member sits centered on the plate at full opacity; each ring of neighbours
-- is dimmer by a fixed step, and a member fades as the plate's edge clips
-- it, so a large group does not run off the plate. A click on a neighbour
-- selects it (the editor opens that tracker, and this strip and the title
-- carousel both glide to it); the wheel steps one member. A standalone
-- tracker or a draft is a strip of one.
--
-- Layout is continuous in index space, as in TitleCarousel.lua: `offset` is a
-- float, the selected member sits at an integer, and position and alpha
-- interpolate from the fractional distance, so a switch glides instead of
-- stepping. Each member is a pooled cell holding one preview row the caller
-- builds (Controls:CreatePreview); the cell is sized to the member's host
-- box, the rect its live host frame has, and the countdown epoch is the
-- strip's, shared by every member and reset only when the strip rebuilds.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.ScootAuraPreviewStrip = {}
local Strip = addon.UI.ScootAuraPreviewStrip

local VIEW_INSET = 4         -- px inside the plate, clear of its rounded corners
local EDGE_FADE = 80         -- px of a member still in view over which it fades out (its own length when shorter)
local HOVER_LIFT = 0.15      -- alpha added to a hovered neighbour
local DISABLED_ALPHA = 0.6   -- multiplier on a member switched off
local EASE = 12              -- offset += (target - offset) * min(1, dt * EASE)
local SETTLE_EPS = 0.002
local WHEEL_DEBOUNCE = 0.12  -- seconds; fast notches coalesce into one selection
local EMPTY_SIZE = 32        -- a cell whose preview could not be built
local HIT_LEVEL = 20         -- the click button's level over the preview's own frames

-- Alpha by ring: the selected member, then each neighbour out, flat past four.
local ALPHA_KNOTS = { [0] = 1, [1] = 0.5, [2] = 0.3, [3] = 0.2, [4] = 0.15 }

-- Grow direction as groups.lua lays the live group out: RIGHT and LEFT are
-- rows sharing a bottom edge, DOWN and UP columns sharing a left edge. `dir`
-- is the sign along the screen axis from member i to member i + 1.
local GROW = {
    RIGHT = { horizontal = true,  dir =  1 },
    LEFT  = { horizontal = true,  dir = -1 },
    DOWN  = { horizontal = false, dir = -1 },
    UP    = { horizontal = false, dir =  1 },
}

local function Knot(knots, last, d)
    if d >= last then return knots[last] end
    local i = math.floor(d)
    return knots[i] + (knots[i + 1] - knots[i]) * (d - i)
end

local function Clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function Round(v) return math.floor(v + 0.5) end

local Proto = {}
Proto.__index = Proto

-- Forward declarations (mutually referenced locals)
local Layout, EnsureTicking, StepBy

--------------------------------------------------------------------------------
-- Cells (pooled)
--------------------------------------------------------------------------------

local function ApplyAlpha(cell)
    local a = cell.alpha or 0
    if cell.hover and (cell.ad or 0) > 0.5 then a = math.min(1, a + HOVER_LIFT) end
    cell:SetAlpha(a)
end

local function CreateCell(c)
    local cell = CreateFrame("Frame", nil, c.viewport)
    -- The click target. The preview's own frames take no mouse, so this is
    -- the one thing under the pointer; it forwards the wheel as well.
    local hit = CreateFrame("Button", nil, cell)
    hit:SetAllPoints(cell)
    hit:SetFrameLevel(cell:GetFrameLevel() + HIT_LEVEL)
    hit:EnableMouseWheel(true)
    hit:SetScript("OnClick", function()
        if cell.id ~= nil and cell.id ~= c.selectedId and c.opts.onSelect then
            c.opts.onSelect(cell.id)
        end
    end)
    hit:SetScript("OnMouseWheel", function(_, delta) StepBy(c, delta > 0 and -1 or 1) end)
    hit:SetScript("OnEnter", function()
        cell.hover = true
        ApplyAlpha(cell)
        if cell.name and cell.id ~= c.selectedId then
            GameTooltip:SetOwner(hit, "ANCHOR_TOP")
            GameTooltip:SetText(cell.name, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    hit:SetScript("OnLeave", function()
        cell.hover = false
        ApplyAlpha(cell)
        GameTooltip:Hide()
    end)
    cell.hit = hit
    return cell
end

local function ReleaseRow(cell)
    local row = cell.row
    if not row then return end
    if row.Cleanup then row:Cleanup() end
    row:Hide()
    row:SetParent(nil)
    cell.row = nil
end

local function ResetCell(cell)
    ReleaseRow(cell)
    cell:Hide()
    cell.id, cell.name, cell.enabled, cell.index = nil, nil, nil, nil
    cell.w, cell.h, cell.alpha, cell.ad, cell.level = nil, nil, nil, nil, nil
    cell.hover = false
end

-- Builds (or rebuilds) one member's preview into its cell and sizes the cell
-- to the member's host box: the rect the live host frame has for the same
-- content (row._hostBox, from the control), so the pitch and the shared edge
-- come out as the live group lays them. The rest of the row (the control's
-- padding, outside text, border art) overhangs the cell as it overhangs the
-- live host; the legend the control hangs at its right edge would land on a
-- neighbour, so it hides.
local function BuildCell(c, cell, m)
    ReleaseRow(cell)
    cell.id, cell.name, cell.enabled = m.id, m.name, m.enabled ~= false
    local row = c.build and c.build(cell, m.id, c.epoch) or nil
    local w, h, dx, dy = EMPTY_SIZE, EMPTY_SIZE, 0, 0
    if row then
        row:EnableMouse(false)
        if row._legendFS then row._legendFS:Hide() end
        local box = row._hostBox
        if box then
            w, h, dx, dy = box.w, box.h, box.x or 0, box.y or 0
        else
            w, h = row:GetWidth(), row:GetHeight()
        end
        row:ClearAllPoints()
        -- The box's center on the cell's center.
        row:SetPoint("CENTER", cell, "CENTER", -dx, -dy)
        row:SetWidth(math.max(1, w or 1))
        row:Show()
    end
    cell.row = row
    cell.w, cell.h = math.max(1, w or 1), math.max(1, h or 1)
    cell:SetSize(cell.w, cell.h)
end

local function ReleaseAll(c)
    for _, cell in ipairs(c.cells) do c.pool:Release(cell) end
    wipe(c.cells)
    c.count = 0
end

local function Signature(key, members)
    local parts = { tostring(key) }
    for i, m in ipairs(members) do
        parts[i + 1] = tostring(m.id) .. ":" .. (m.enabled ~= false and 1 or 0) .. ":" .. tostring(m.spellId or "")
    end
    return table.concat(parts, "|")
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

Layout = function(c)
    local n = c.count
    if n == 0 then return end
    local vp = c.viewport
    local viewW, viewH = vp:GetWidth() or 0, vp:GetHeight() or 0
    -- OnSizeChanged lays out once the rect resolves.
    if viewW <= 0 or viewH <= 0 then return end
    local g = GROW[c.grow] or GROW.RIGHT
    local horizontal, dir = g.horizontal, g.dir
    local spacing = math.max(0, tonumber(c.spacing) or 0)
    local half = (horizontal and viewW or viewH) / 2
    local cells = c.cells
    local function Main(cell) return horizontal and cell.w or cell.h end
    local function Cross(cell) return horizontal and cell.h or cell.w end

    local k = Clamp(math.floor(c.offset), 1, math.max(1, n - 1))
    local f = c.offset - k
    local ck, ck1 = cells[k], cells[k + 1]
    local pitch = ck1 and (Main(ck) / 2 + spacing + Main(ck1) / 2) or 0
    local anchor = f * pitch
    -- The cross extent at the offset: the selected member's at rest, blended
    -- across the pair mid-glide, so the shared edge slides with it.
    local crossRef = Cross(ck) + (ck1 and (Cross(ck1) - Cross(ck)) or 0) * f

    local function Place(i, cx)
        local cell = cells[i]
        local m = Main(cell)
        local x = (cx - anchor) * dir
        local visible = Clamp(half - math.abs(x) + m / 2, 0, m)
        if visible <= 0 then
            cell:Hide()
            return false
        end
        -- A shared bottom edge on a row, a shared left edge on a column.
        local crossOff = (Cross(cell) - crossRef) / 2
        if horizontal then
            cell:SetPoint("CENTER", vp, "CENTER", x, crossOff)
        else
            cell:SetPoint("CENTER", vp, "CENTER", crossOff, x)
        end
        local ad = math.abs(i - c.offset)
        local a = Knot(ALPHA_KNOTS, 4, ad) * Clamp(visible / math.min(m, EDGE_FADE), 0, 1)
        if not cell.enabled then a = a * DISABLED_ALPHA end
        cell.alpha, cell.ad = a, ad
        ApplyAlpha(cell)
        local level = c.baseLevel + ((ad < 0.5) and 1 or 0)
        if cell.level ~= level then
            cell:SetFrameLevel(level)
            cell.level = level
        end
        cell:Show()
        return true
    end

    Place(k, 0)
    -- Centers strictly increase outward, so the first member past the edge
    -- ends the walk and hides the rest.
    local cx, prevMain = 0, Main(ck)
    for i = k + 1, n do
        local m = Main(cells[i])
        cx = cx + prevMain / 2 + spacing + m / 2
        if not Place(i, cx) then
            for j = i + 1, n do cells[j]:Hide() end
            break
        end
        prevMain = m
    end
    cx, prevMain = 0, Main(ck)
    for i = k - 1, 1, -1 do
        local m = Main(cells[i])
        cx = cx - (prevMain / 2 + spacing + m / 2)
        if not Place(i, cx) then
            for j = i - 1, 1, -1 do cells[j]:Hide() end
            break
        end
        prevMain = m
    end
end

--------------------------------------------------------------------------------
-- Motion
--------------------------------------------------------------------------------

local function Settle(c)
    c.viewport:SetScript("OnUpdate", nil)
    c.ticking = false
end

EnsureTicking = function(c)
    if c.ticking then return end
    c.ticking = true
    c.viewport:SetScript("OnUpdate", c.onUpdate)
end

local function OnUpdate(c, dt)
    if c.target then
        c.offset = c.offset + (c.target - c.offset) * math.min(1, dt * EASE)
        if math.abs(c.target - c.offset) < SETTLE_EPS then
            c.offset = c.target
            c.target = nil
        end
        Layout(c)
    end
    if not c.target then Settle(c) end
end

--- Steps one member in `dir` (-1 toward the first, 1 toward the last); fast
--- steps coalesce into one editor switch. The strip starts gliding at once
--- and the editor follows a beat later.
StepBy = function(c, dir)
    if c.count < 2 then return end
    local base = c.target or Clamp(Round(c.offset), 1, c.count)
    local idx = Clamp(base + dir, 1, c.count)
    if idx == base then return end
    c.target = idx
    EnsureTicking(c)
    c.wheelToken = (c.wheelToken or 0) + 1
    local token = c.wheelToken
    C_Timer.After(WHEEL_DEBOUNCE, function()
        local cell = c.cells[idx]
        if token == c.wheelToken and cell and cell.id ~= nil and cell.id ~= c.selectedId and c.opts.onSelect then
            c.opts.onSelect(cell.id)
        end
    end)
end

--------------------------------------------------------------------------------
-- Public surface
--------------------------------------------------------------------------------

--- Points the strip at a set of members. desc:
---   key         identity of the set (a group id, or a tracker key); part of the signature
---   members     { { id, name, enabled, spellId } ... } in display order
---   selectedId  the member the editor has open
---   spacing     gap between members, px
---   grow        RIGHT / LEFT / DOWN / UP
---   build       fn(cell, id, epoch) -> the preview row for member id, or nil
--- A changed set (membership, enabled flags, spells) rebuilds every member on
--- a fresh epoch and snaps to the selection. The same set with a new selection
--- glides to it and rebuilds nothing. The same set and selection is a value
--- edit: the selected member alone rebuilds.
function Proto:SetContext(desc)
    local members = desc.members or {}
    local selIdx = 1
    for i, m in ipairs(members) do
        if m.id == desc.selectedId then selIdx = i; break end
    end
    self.spacing, self.grow, self.build = desc.spacing, desc.grow, desc.build
    local sig = Signature(desc.key, members)
    if sig ~= self.sig then
        ReleaseAll(self)
        self.sig = sig
        self.epoch = {}
        self.selectedId = desc.selectedId
        for i, m in ipairs(members) do
            local cell = self.pool:Acquire(self)
            cell.index = i
            self.cells[i] = cell
            BuildCell(self, cell, m)
        end
        self.count = #members
        self.offset, self.target = selIdx, nil
        Layout(self)
        return
    end
    if desc.selectedId ~= self.selectedId then
        self.selectedId = desc.selectedId
        if self.target ~= selIdx then
            self.target = selIdx
            EnsureTicking(self)
        end
        return
    end
    local cell = self.cells[selIdx]
    if cell then BuildCell(self, cell, members[selIdx]) end
    Layout(self)
end

--- Drops everything so the next SetContext rebuilds and snaps.
function Proto:Reset()
    ReleaseAll(self)
    self.sig, self.epoch, self.build = nil, nil, nil
    self.selectedId, self.target, self.offset = nil, nil, 1
    self.wheelToken = (self.wheelToken or 0) + 1
    if self.ticking then Settle(self) end
end

function Proto:IsSettled()
    return self.target == nil
end

--- parent: the quadrant the plate sits on; plate: the frame holding the
--- plate's rect, which the viewport fills, inset. opts.onSelect(trackerId).
function Strip.Create(parent, plate, opts)
    local c = setmetatable({ opts = opts or {}, cells = {}, count = 0, offset = 1 }, Proto)
    c.pool = addon.Pool.New(CreateCell, ResetCell)

    local vp = CreateFrame("Frame", nil, parent)
    vp:SetPoint("TOPLEFT", plate, "TOPLEFT", VIEW_INSET, -VIEW_INSET)
    vp:SetPoint("BOTTOMRIGHT", plate, "BOTTOMRIGHT", -VIEW_INSET, VIEW_INSET)
    vp:SetClipsChildren(true)
    vp:SetFrameLevel(parent:GetFrameLevel() + 1)
    -- The wheel alone: bare plate takes no click, and the window's drag
    -- surface stays the title bar.
    vp:EnableMouseWheel(true)
    vp:SetScript("OnMouseWheel", function(_, delta) StepBy(c, delta > 0 and -1 or 1) end)
    vp:SetScript("OnSizeChanged", function() Layout(c) end)
    vp:SetScript("OnHide", function()
        if c.ticking then Settle(c) end
    end)
    vp:SetScript("OnShow", function()
        if c.target then EnsureTicking(c) end
    end)
    c.viewport = vp
    c.baseLevel = vp:GetFrameLevel() + 1
    c.onUpdate = function(_, dt) OnUpdate(c, dt) end
    return c
end

return Strip
