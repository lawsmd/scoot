-- TitleCarousel.lua - The editor title as a spinnable strip of group members
--
-- When the tracker open in the ScootAura editor belongs to a group, the
-- centered title name becomes the handle of a carousel listing the group's
-- members in memberOrder. The selected name sits centered at full size in the
-- accent color; the neighbors shrink ring by ring, tint to gray, and fade
-- toward the viewport edges, so the accent marks the selection. A click
-- on a name selects it, dragging spins the strip, the wheel steps it. A pair of
-- end chevrons brackets the visible strip (riding its ends when the whole
-- group fits, parked at the viewport edges when it does not) so the bar reads
-- as something that moves; they dim at the ends and click to step.
--
-- Layout is continuous in index space: `offset` is a float, the selected
-- member sits at an integer, and every size, gap, alpha, and tint interpolates
-- from the fractional distance to `offset`, so a drag morphs the strip
-- instead of stepping it. Widths derive from one base measurement per name
-- (16pt) scaled by size, never from per-frame GetStringWidth.
--
-- Mouse: item buttons and the viewport both feed BeginPress; from then on the
-- viewport's OnUpdate polls the cursor and the button state, so a drag keeps
-- tracking wherever the cursor goes and release needs no OnMouseUp. Items have
-- no OnClick: a press that did not move past the threshold is the click.
local addonName, addon = ...

addon.UI = addon.UI or {}
addon.UI.ScootAuraTitleCarousel = {}
local Carousel = addon.UI.ScootAuraTitleCarousel

local BASE_SIZE = 16
local GAP = 20               -- edge-to-edge between names (36 text-to-text at the center pair)
-- Space held clear right of the selected name for the editor's title icons,
-- measured from its glyph edge (opts.selectedRoom overrides). The name's own
-- side padding covers the first PAD_X of it.
local SELECTED_ROOM = 42
-- Padding beside each name, scaled by its ring's font size (floored). Nothing
-- draws it; it widens the click target and spaces the names apart.
local PAD_X = 10
local PAD_MIN = 5
local DIM_COLOR = { 0.6, 0.6, 0.6 }   -- unselected names; opts.dimColor overrides
local EDGE_FADE = 80         -- px inward from the viewport edge over which alpha ramps 0 -> 1
local DRAG_THRESHOLD = 4     -- px; below it a press is a click
local FLING = 0.15           -- seconds of release velocity projected into the snap target
local EASE = 12              -- offset += (target - offset) * min(1, dt * EASE)
local SETTLE_EPS = 0.002
local OVERSHOOT = 0.3        -- index units allowed past the ends while dragging
local WHEEL_DEBOUNCE = 0.12  -- seconds; fast notches coalesce into one selection
local MIN_WIDTH = 600
local CHEVRON_W = 16         -- hit width of each end chevron
local CHEVRON_SIZE = 11      -- glyph point size
local CHEVRON_GAP = 12       -- from the strip's end to the chevron's near edge
local CHEVRON_INSET = 6      -- from the viewport edge when parked there
local CHEVRON_ALPHA = 0.55   -- with more names in that direction
local CHEVRON_END_ALPHA = 0.18

-- Font scale by ring: adjacent 40% smaller, then 15% smaller per ring, flat past 3.
local SIZE_KNOTS = { [0] = 1, [1] = 0.6, [2] = 0.51, [3] = 0.4335 }
local ALPHA_KNOTS = { [0] = 1, [1] = 0.8, [2] = 0.6, [3] = 0.45, [4] = 0.35 }

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
local Layout, Rebuild, SetSelected, BeginPress, EndPress, OnUpdate, OnWheel, StepBy
local EnsureTicking, Settle, NotifyMotion

--------------------------------------------------------------------------------
-- Members
--------------------------------------------------------------------------------

--- Existing members of a group in memberOrder, as { id, name, enabled }.
--- Returns nil when the group is missing or has fewer than two members.
function Carousel.Members(gid)
    local SAU = addon.ScootAuras
    local group = SAU and SAU.GetGroup(gid)
    if not group then return nil end
    local out = {}
    for _, id in ipairs(group.memberOrder or {}) do
        local tracker = SAU.GetTracker(id)
        if tracker then
            out[#out + 1] = { id = id, name = SAU.DisplayName(tracker), enabled = tracker.enabled ~= false }
        end
    end
    if #out < 2 then return nil end
    return out
end

local function Signature(gid, members)
    local parts = { tostring(gid) }
    for i, m in ipairs(members) do
        parts[i + 1] = m.id .. ":" .. (m.enabled and 1 or 0) .. ":" .. m.name
    end
    return table.concat(parts, "|")
end

--------------------------------------------------------------------------------
-- Items (pooled buttons)
--------------------------------------------------------------------------------

local function ApplyHoverAlpha(it)
    local a = it.alpha or 0
    if it.hover and (it.ad or 0) > 0.5 then a = math.min(1, a + 0.2) end
    it.btn:SetAlpha(a)
end

local function CreateItem(c)
    local btn = CreateFrame("Button", nil, c.viewport)
    btn:SetHeight(c.viewport:GetHeight())   -- full-height hit area
    btn:EnableMouse(true)
    local fs = btn:CreateFontString(nil, "OVERLAY")
    fs:SetFont(c.opts.font, BASE_SIZE, "")   -- SetText errors on a font-less string
    fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(false)
    fs:SetTextColor(c.dim[1], c.dim[2], c.dim[3], 1)   -- ApplyItem tints from here
    local it = { btn = btn, fs = fs, curSize = BASE_SIZE }
    btn:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then BeginPress(c, it.index) end
    end)
    btn:SetScript("OnEnter", function() it.hover = true; ApplyHoverAlpha(it) end)
    btn:SetScript("OnLeave", function() it.hover = false; ApplyHoverAlpha(it) end)
    return it
end

local function ResetItem(it)
    it.btn:Hide()
    it.btn:EnableMouse(true)
    it.btn:SetHitRectInsets(0, 0, 0, 0)
    it.hover, it.curSize, it.curTint = false, nil, nil
    it.id, it.index, it.alpha, it.ad = nil, nil, nil, nil
end

local function ReleaseAll(c)
    for _, it in ipairs(c.items) do
        c.pool:Release(it)
    end
    wipe(c.items)
end

local function MeasureBase(c, name)
    c.measureFS:SetText(name)
    local w = c.measureFS:GetStringWidth()
    if not (w and w > 0) then
        -- Font file not loaded yet (first launch): estimate at 0.6em per
        -- character (JetBrains Mono advance) and re-measure next frame.
        w = #name * 0.6 * BASE_SIZE
        c.needsRemeasure = true
    end
    return w
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local function PadX(size)
    return math.max(PAD_MIN, PAD_X * size / BASE_SIZE)
end

--- Font size, padded width, title-icon room, and ring distance of item i.
local function Metrics(c, i)
    local d = i - c.offset
    local ad = math.abs(d)
    local size = BASE_SIZE * Knot(SIZE_KNOTS, 3, ad)
    local w = c.items[i].baseW * (size / BASE_SIZE) + 2 * PadX(size)
    local room = c.selRoom * Clamp(1 - ad, 0, 1)
    return size, w, room, ad
end

-- One name's color at ring position t: 0 is the dim neighbor color, 1 is the
-- accent on the selected name. Shared by the layout pass and by SetAccent, so a
-- drag and an accent change paint a name the same way.
local function TintItem(c, it, t)
    local sel, dim = c.opts.color, c.dim
    it.fs:SetTextColor(dim[1] + (sel[1] - dim[1]) * t,
                       dim[2] + (sel[2] - dim[2]) * t,
                       dim[3] + (sel[3] - dim[3]) * t, 1)
    it.curTint = t
end

local function ApplyItem(c, it, size, w, x, ad, half)
    local q = math.floor(size * 2 + 0.5) / 2
    if it.curSize ~= q then
        it.fs:SetFont(c.opts.font, q, "")
        it.curSize = q
    end
    -- Accent at the center, gray by one ring out, quantized so a drag repaints
    -- the color at most 32 times per name. The squared falloff keeps the accent
    -- on the selected name instead of bleeding into its neighbors.
    local t = Clamp(1 - ad, 0, 1)
    t = math.floor(t * t * 32 + 0.5) / 32
    if it.curTint ~= t then
        TintItem(c, it, t)
    end

    w = math.max(w, 8)
    it.btn:SetWidth(w)
    it.btn:SetPoint("CENTER", c.viewport, "CENTER", x, 0)

    local a = Knot(ALPHA_KNOTS, 4, ad)
    a = a * Clamp((half - (math.abs(x) + w / 2)) / EDGE_FADE, 0, 1)
    if not it.enabled then a = a * 0.6 end
    it.alpha, it.ad = a, ad
    ApplyHoverAlpha(it)

    -- Hit rect clamped to the viewport; nearly invisible names pass their
    -- presses through to the viewport so a drag still starts there.
    local l, r = x - w / 2, x + w / 2
    it.btn:SetHitRectInsets(math.max(0, -half - l), math.max(0, r - half), 0, 0)
    it.btn:EnableMouse(a > 0.05)
    it.btn:Show()
end

-- Chevron alpha follows how much strip remains in that direction, so an end
-- reads as an end while the strip is still gliding toward it.
local function ApplyChevronAlpha(c)
    if c.count < 2 then return end
    local function Apply(btn, more)
        local a = CHEVRON_END_ALPHA + (CHEVRON_ALPHA - CHEVRON_END_ALPHA) * more
        if btn.hover then a = math.max(a, 0.95 * more) end
        btn:SetAlpha(a)
    end
    Apply(c.prevBtn, Clamp(c.offset - 1, 0, 1))
    Apply(c.nextBtn, Clamp(c.count - c.offset, 0, 1))
end

-- Each chevron sits just past the strip's end when that end is inside the
-- viewport and parks at the viewport edge otherwise. Both positions are
-- continuous in `offset`, so the chevrons slide with a drag instead of jumping.
local function PlaceChevrons(c, half, leftEnd, rightEnd)
    local xl = -half + CHEVRON_INSET + CHEVRON_W / 2
    if leftEnd then xl = math.max(xl, leftEnd - CHEVRON_GAP - CHEVRON_W / 2) end
    local xr = half - CHEVRON_INSET - CHEVRON_W / 2
    if rightEnd then xr = math.min(xr, rightEnd + CHEVRON_GAP + CHEVRON_W / 2) end
    c.prevBtn:SetPoint("CENTER", c.viewport, "CENTER", xl, 0)
    c.nextBtn:SetPoint("CENTER", c.viewport, "CENTER", xr, 0)
    ApplyChevronAlpha(c)
end

Layout = function(c)
    local n = c.count
    if n < 2 then return end
    local half = c.viewW / 2
    local k = Clamp(math.floor(c.offset), 1, n - 1)
    local f = c.offset - k
    local sk, wk, rk, adk = Metrics(c, k)
    local _, wk1 = Metrics(c, k + 1)
    local pitch = wk / 2 + rk + GAP + wk1 / 2
    local anchor = f * pitch
    c.pitch = pitch

    local lo, hi = k, k
    local function Place(i, size, w, ad, cx)
        local x = cx - anchor
        if x + w / 2 < -half or x - w / 2 > half then return false end
        ApplyItem(c, c.items[i], size, w, x, ad, half)
        return true
    end
    if not Place(k, sk, wk, adk, 0) then c.items[k].btn:Hide() end

    -- Rightward: centers strictly increase, so the first miss ends the walk.
    local cx, prevW, prevRoom = 0, wk, rk
    local hiX, hiW, hiRoom = -anchor, wk, rk
    for i = k + 1, n do
        local s, w, room, ad = Metrics(c, i)
        cx = cx + prevW / 2 + prevRoom + GAP + w / 2
        if not Place(i, s, w, ad, cx) then break end
        hi, prevW, prevRoom = i, w, room
        hiX, hiW, hiRoom = cx - anchor, w, room
    end
    -- Leftward: item i's icon room sits between it and its right neighbor.
    cx, prevW = 0, wk
    local loX, loW = -anchor, wk
    for i = k - 1, 1, -1 do
        local s, w, room, ad = Metrics(c, i)
        cx = cx - (prevW / 2 + GAP + room + w / 2)
        if not Place(i, s, w, ad, cx) then break end
        lo, prevW = i, w
        loX, loW = cx - anchor, w
    end

    if c.shownLo then
        for i = c.shownLo, lo - 1 do c.items[i].btn:Hide() end
        for i = hi + 1, c.shownHi do c.items[i].btn:Hide() end
    end
    c.shownLo, c.shownHi = lo, hi

    -- Strip ends exist only when the first / last name is on screen.
    PlaceChevrons(c, half,
        lo == 1 and (loX - loW / 2) or nil,
        hi == n and (hiX + hiW / 2 + hiRoom) or nil)
end

--------------------------------------------------------------------------------
-- Selection and rebuild
--------------------------------------------------------------------------------

SetSelected = function(c, idx, notify)
    local it = c.items[idx]
    if not it or it.id == c.selectedId then return end
    -- The anchor is the text, not the padded hit box: the editor's title icons
    -- sit against the glyphs.
    c.selectedIndex, c.selectedId, c.selectedAnchor = idx, it.id, it.fs
    if notify and c.opts.onSelect then c.opts.onSelect(it.id) end
end

Rebuild = function(c, gid, members, selIdx, sig)
    ReleaseAll(c)
    c.gid, c.sig, c.count = gid, sig, #members
    c.needsRemeasure = false
    for i, m in ipairs(members) do
        local it = c.pool:Acquire(c)
        it.index, it.id, it.name, it.enabled = i, m.id, m.name, m.enabled
        it.fs:SetText(m.name)
        it.baseW = MeasureBase(c, m.name)
        c.items[i] = it
    end
    c.shownLo, c.shownHi = nil, nil
    c.press, c.target = nil, nil
    c.offset = selIdx
    -- Clear before SetSelected: the early return on a matching id would
    -- otherwise leave selectedAnchor pointing at a recycled item.
    c.selectedId, c.selectedIndex, c.selectedAnchor = nil, nil, nil
    SetSelected(c, selIdx, false)
    Layout(c)
    NotifyMotion(c, false)
    if c.needsRemeasure then
        C_Timer.After(0, function()
            if c.sig ~= sig then return end
            c.needsRemeasure = false
            for _, it in ipairs(c.items) do it.baseW = MeasureBase(c, it.name) end
            Layout(c)
        end)
    end
end

--------------------------------------------------------------------------------
-- Motion
--------------------------------------------------------------------------------

NotifyMotion = function(c, moving)
    if c.moving == moving then return end
    c.moving = moving
    if c.opts.onMotion then c.opts.onMotion(moving) end
end

EnsureTicking = function(c)
    if c.ticking then return end
    c.ticking = true
    c.viewport:SetScript("OnUpdate", c.onUpdate)
end

Settle = function(c)
    c.viewport:SetScript("OnUpdate", nil)
    c.ticking = false
    NotifyMotion(c, false)
end

local function CursorX(c)
    local x = GetCursorPosition()
    return x / c.viewport:GetEffectiveScale()
end

BeginPress = function(c, itemIndex)
    if c.press or not c.viewport:IsShown() then return end
    local x = CursorX(c)
    c.press = { startX = x, lastX = x, item = itemIndex, moved = false, vel = 0 }
    c.target = nil
    NotifyMotion(c, true)
    EnsureTicking(c)
end

EndPress = function(c)
    local p = c.press
    c.press = nil
    local n = c.count
    if p.moved then
        c.target = Clamp(Round(c.offset + p.vel * FLING), 1, n)
    elseif p.item then
        c.target = p.item
    else
        c.target = Clamp(Round(c.offset), 1, n)
    end
    SetSelected(c, c.target, true)
end

OnUpdate = function(c, dt)
    if c.press then
        local p = c.press
        local x = CursorX(c)
        if not p.moved and math.abs(x - p.startX) >= DRAG_THRESHOLD then p.moved = true end
        if p.moved then
            local before = c.offset
            c.offset = Clamp(c.offset - (x - p.lastX) / math.max(c.pitch or 1, 1),
                1 - OVERSHOOT, c.count + OVERSHOOT)
            local inst = (c.offset - before) / math.max(dt, 0.001)
            p.vel = p.vel * 0.7 + inst * 0.3
            Layout(c)
        end
        p.lastX = x
        if not IsMouseButtonDown("LeftButton") then EndPress(c) end
        return
    end
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

--- Steps one name in `dir` (-1 previous, 1 next); rapid steps coalesce into
--- one editor switch. Shared by the wheel and the end chevrons.
StepBy = function(c, dir)
    if c.press or c.count < 2 then return end
    local base = c.target or Clamp(Round(c.offset), 1, c.count)
    local idx = Clamp(base + dir, 1, c.count)
    if idx == base and not c.target then return end
    c.target = idx
    NotifyMotion(c, true)
    EnsureTicking(c)
    c.wheelToken = (c.wheelToken or 0) + 1
    local token = c.wheelToken
    C_Timer.After(WHEEL_DEBOUNCE, function()
        if token == c.wheelToken and c.gid and c.items[idx] then
            SetSelected(c, idx, true)
        end
    end)
end

OnWheel = function(c, delta)
    StepBy(c, delta > 0 and -1 or 1)
end

--------------------------------------------------------------------------------
-- Public surface
--------------------------------------------------------------------------------

--- Points the carousel at a group and its selected member. Returns false when
--- the group is not carousel-eligible (missing, fewer than two members, or the
--- selected tracker absent from memberOrder); the caller then shows the plain
--- title. Safe to call re-entrantly from inside onSelect: an unchanged group
--- and selection is a no-op, and nothing here hides the viewport or drops a
--- running animation.
function Proto:SetContext(gid, selectedId)
    local members = Carousel.Members(gid)
    if not members then return false end
    local selIdx
    for i, m in ipairs(members) do
        if m.id == selectedId then selIdx = i; break end
    end
    if not selIdx then return false end
    local sig = Signature(gid, members)
    if sig ~= self.sig then
        Rebuild(self, gid, members, selIdx, sig)
        return true
    end
    if selectedId ~= self.selectedId then
        SetSelected(self, selIdx, false)
        if self.target ~= selIdx and not self.press then
            self.target = selIdx
            NotifyMotion(self, true)
            EnsureTicking(self)
        end
    end
    return true
end

--- The accent moved. opts.color is the table the layout pass reads, so it is
--- written in place; the names on screen retint at the ring they already sit on
--- and the chevrons go solid in the new color.
function Proto:SetAccent(r, g, b)
    local sel = self.opts.color
    sel[1], sel[2], sel[3] = r, g, b
    if self.prevBtn then self.prevBtn._glyph:SetTextColor(r, g, b, 1) end
    if self.nextBtn then self.nextBtn._glyph:SetTextColor(r, g, b, 1) end
    for _, it in ipairs(self.items) do
        TintItem(self, it, it.curTint or 0)
    end
end

function Proto:Show()
    self.viewport:Show()
end

function Proto:Hide()
    self.viewport:Hide()
end

--- Drops everything so the next SetContext rebuilds and snaps.
function Proto:Reset()
    self:Hide()
    ReleaseAll(self)
    self.gid, self.sig, self.count = nil, nil, 0
    self.target, self.press = nil, nil
    self.selectedId, self.selectedIndex, self.selectedAnchor = nil, nil, nil
    self.moving = false
    self.shownLo, self.shownHi = nil, nil
end

function Proto:IsSettled()
    return self.press == nil and self.target == nil
end

--- Rasterizes every quantized size once so the first drag has no glyph hitches.
local function PreWarm(c)
    if c.warmed then return end
    c.warmed = true
    for s = 6.5, BASE_SIZE, 0.5 do
        c.measureFS:SetFont(c.opts.font, s, "")
        c.measureFS:SetText("Ag")
    end
    c.measureFS:SetFont(c.opts.font, BASE_SIZE, "")
end

--- opts: width, font, arrowFont (chevron glyphs; defaults to font),
--- color = { r, g, b } for the selected name, dimColor = { r, g, b } for the
--- rest (defaults to DIM_COLOR), selectedRoom (px kept clear right of the
--- selected name's glyphs), onSelect(trackerId), onMotion(isMoving)
function Carousel.Create(titleBar, opts)
    local c = setmetatable({ titleBar = titleBar, opts = opts, items = {}, pool = addon.Pool.New(CreateItem, ResetItem), count = 0 }, Proto)
    c.dim = opts.dimColor or DIM_COLOR
    c.selRoom = math.max(0, (opts.selectedRoom or SELECTED_ROOM) - PAD_X)
    c.viewW = math.max(MIN_WIDTH, math.floor(opts.width))

    local vp = CreateFrame("Frame", nil, titleBar)
    vp:SetSize(c.viewW, titleBar:GetHeight())
    vp:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    vp:SetClipsChildren(true)
    vp:SetFrameLevel(titleBar:GetFrameLevel() + 2)
    vp:EnableMouse(true)
    vp:EnableMouseWheel(true)
    vp:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then BeginPress(c, nil) end
    end)
    vp:SetScript("OnMouseWheel", function(_, delta) OnWheel(c, delta) end)
    vp:SetScript("OnHide", function()
        c.press = nil
        if c.ticking then
            vp:SetScript("OnUpdate", nil)
            c.ticking = false
        end
    end)
    vp:SetScript("OnShow", function()
        PreWarm(c)
        if c.target then EnsureTicking(c) end
    end)
    vp:Hide()
    c.viewport = vp

    local function Chevron(glyph, dir)
        local b = CreateFrame("Button", nil, vp)
        b:SetSize(CHEVRON_W, vp:GetHeight())
        b:SetFrameLevel(vp:GetFrameLevel() + 2)   -- above the item buttons
        b:RegisterForClicks("AnyUp")
        local fs = b:CreateFontString(nil, "OVERLAY")
        fs:SetFont(opts.arrowFont or opts.font, CHEVRON_SIZE, "")
        fs:SetPoint("CENTER", b, "CENTER", 0, 0)
        fs:SetText(glyph)
        fs:SetTextColor(opts.color[1], opts.color[2], opts.color[3], 1)
        b._glyph = fs
        b:SetAlpha(0)   -- Layout sets it
        b:SetScript("OnClick", function() StepBy(c, dir) end)
        b:SetScript("OnEnter", function() b.hover = true; ApplyChevronAlpha(c) end)
        b:SetScript("OnLeave", function() b.hover = false; ApplyChevronAlpha(c) end)
        return b
    end
    c.prevBtn = Chevron("\226\151\128", -1) -- ◀
    c.nextBtn = Chevron("\226\150\182", 1)  -- ▶

    -- Measurement string: shown at alpha 0 on the title bar (not inside the
    -- hidden viewport), so widths read true on the first open.
    c.measureFS = titleBar:CreateFontString(nil, "OVERLAY")
    c.measureFS:SetFont(opts.font, BASE_SIZE, "")
    c.measureFS:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
    c.measureFS:SetAlpha(0)
    c.onUpdate = function(_, dt) OnUpdate(c, dt) end
    return c
end

return Carousel
