-- scootauras/stacks.lua - Stacks trackers: the aura's application count as a
-- number on the icon, a segmented bar, a row of shapes, or the number alone
--
-- The Floating Number (the "text" shape) draws nothing here: the count
-- FontString is the whole display, and layout.lua sizes its host from
-- Stacks.MeasureNumber.
--
-- The engine owns the count. SetApplicationBar binds one StatusBar per button
-- and runs SetMinMaxValues(0, N) and SetValue(count) on it itself, N being
-- the addon's maxApplications option (SAU.ResolveMaxStacks finds it);
-- SetApplicationCount writes the number. Lua never reads either. The two
-- segmented shapes are geometry over that one fill:
--
--   Bar:    the bar element's own fill, bound as the application bar, with
--           N-1 tick textures drawn above it at the segment boundaries. The
--           shared segment formula (pips.lua) puts boundary c inside the tick
--           after segment c, so a fill at c/N ends under a tick and the bar
--           reads as c whole segments.
--   Shapes: a transparent StatusBar spanning the row, bound as the
--           application bar; a clip frame anchored to its fill texture; the
--           colored glyphs inside the clip, the backdrops beneath on the
--           button. A bordered key puts a black ring under each backdrop at
--           the full cell and insets the backdrop and glyph inside it. At count c the fill edge sits in the gap after shape c,
--           so c whole glyphs show over N backdrops; at 0 the fill has no
--           width, the clip has no rect, and the backdrops show alone.
--
-- Spacing floors at 0 on these kinds: a negative gap would put the fill edge
-- inside shape c.
--
--   button (engine)
--    +- bar element (regions.lua)  widget > inner > barClip > barFill (B+1)
--    |   +- tickHost  Frame, SetAllPoints(inner), level barFill+1   Bar shape
--    |       +- tick[i] Texture
--    +- pipHost   Frame, level B+1                                 Shapes
--    |   +- ring[i] Texture, sublevel -1, bordered keys only
--    |   +- backdrop[i] Texture
--    +- stackBar  StatusBar, level B+1, transparent fill            Shapes
--        +- clip  Frame, level B+2, SetAllPoints(fill texture), clips
--            +- glyph[i] Texture, anchored to cell i of the row
--
-- The same pieces are built on a Scoot-owned element set (the Edit Mode
-- preview, the missing-state underlay), where Lua feeds the StatusBar a
-- sample or 0. Everything on the live button is created inside
-- initializeFrame or under the structural gate, where ApplyAll runs.
local addonName, addon = ...

local SAU = addon.ScootAuras
local Engine = SAU.Engine

local Stacks = {}
SAU.Stacks = Stacks

local SetResult = Engine._SetResult
local SafeToString = Engine._SafeToString

local WHITE8x8 = "Interface\\Buttons\\WHITE8x8"
local INTERP_IMMEDIATE = (Enum and Enum.StatusBarInterpolation
    and Enum.StatusBarInterpolation.Immediate) or 0

--------------------------------------------------------------------------------
-- Engine options
--------------------------------------------------------------------------------

-- Without a formatter the engine writes the count only above 1, the Cooldown
-- Manager rule, which hides the one reading a stacks tracker exists to show.
-- Any NumericFormatter makes it write every count; the abbreviating one
-- prints a stack count as its digits. One formatter for every tracker (the
-- duration formatter's shape in regions.lua); a creation failure falls back
-- to the engine default and is recorded once.
local countFormatter
local countFormatterFailed = false

local function GetCountFormatter()
    if countFormatter then return countFormatter end
    if countFormatterFailed then return nil end
    local su = C_StringUtil
    if not (su and su.CreateAbbreviatedNumberFormatter) then
        countFormatterFailed = true
        SetResult("stackfmt", "API missing; engine default (blank at 1)")
        return nil
    end
    local ok, f = pcall(su.CreateAbbreviatedNumberFormatter)
    if not ok or not f then
        countFormatterFailed = true
        SetResult("stackfmt", "create failed; engine default (blank at 1)")
        return nil
    end
    countFormatter = f
    return f
end

--- The options table for SetApplicationCount on a stacks tracker, or nil for
-- the engine default.
function Stacks.CountOptions()
    local f = GetCountFormatter()
    return f and { formatter = f } or nil
end

--- The options table for SetApplicationBar: the segment count, and no
-- easing, since a count steps.
function Stacks.BarOptions(tracker)
    local n = SAU.ResolveMaxStacks(tracker)
    return { maxApplications = n, interpolation = INTERP_IMMEDIATE }
end

--------------------------------------------------------------------------------
-- Pieces
--------------------------------------------------------------------------------

local function FindBarElem(elements)
    for _, elem in ipairs(elements or {}) do
        if elem.type == "bar" then return elem end
    end
    return nil
end

-- The frames one set needs, under `parent` (the engine button, or a
-- Scoot-owned root). The pools of ticks and shapes grow at paint time.
local function Build(parent, barElem)
    local level = parent:GetFrameLevel()
    local s = { ticks = {}, pips = {} }

    if barElem and barElem.widget and barElem.barFill then
        local tickHost = CreateFrame("Frame", nil, barElem.widget)
        tickHost:SetFrameLevel(barElem.barFill:GetFrameLevel() + 1)
        tickHost:SetAllPoints(barElem.inner or barElem.widget)
        tickHost:Hide()
        s.tickHost = tickHost
    end

    local pipHost = CreateFrame("Frame", nil, parent)
    pipHost:SetFrameLevel(level + 1)
    pipHost:SetAllPoints(parent)
    pipHost:Hide()
    s.pipHost = pipHost

    local stackBar = CreateFrame("StatusBar", nil, parent)
    stackBar:SetFrameLevel(level + 1)
    stackBar:SetStatusBarTexture(WHITE8x8)
    stackBar:SetStatusBarColor(1, 1, 1, 0)
    stackBar:SetMinMaxValues(0, 1)
    stackBar:SetValue(0)
    stackBar:Hide()
    s.stackBar = stackBar

    local clip = CreateFrame("Frame", nil, stackBar)
    clip:SetFrameLevel(level + 2)
    clip:SetClipsChildren(true)
    clip:SetAllPoints(stackBar:GetStatusBarTexture())
    s.clip = clip

    return s
end

--- Called from Engine.WireButton inside initializeFrame, for every kind:
-- the pieces of an earlier container die hidden with it, and a stacks kind
-- gets a fresh set on the new button.
function Stacks.OnWire(entry, button, tracker, elements)
    entry.stacks = nil
    if not SAU.KindTracksStacks(tracker and tracker.kind) then return end
    local ok, s = pcall(Build, button, FindBarElem(elements))
    if ok then
        entry.stacks = s
    elseif entry.occupantId then
        SetResult("stacks.t" .. entry.occupantId, "create FAILED: " .. SafeToString(s))
    end
end

--- The same pieces on a Scoot-owned element set ({ root, elements }): the
-- Edit Mode preview and the missing-state underlay. Built once per set.
function Stacks.EnsureSetPieces(set)
    if set.stacks then return set.stacks end
    local ok, s = pcall(Build, set.root, FindBarElem(set.elements))
    if ok then set.stacks = s end
    return set.stacks
end

--------------------------------------------------------------------------------
-- Painting
--------------------------------------------------------------------------------

-- Class color or a tint; any other stored mode reads as the class color, the
-- rule the editor's selector applies.
local function ShapeColor(db)
    if db and db.pipColorMode == "custom" then
        local c = db.pipTint or { 1, 1, 1, 1 }
        return c[1] or 1, c[2] or 1, c[3] or 1
    end
    local r, g, b = addon.GetClassColorRGB("player")
    return r or 1, g or 1, b or 1
end

local function Hide(s)
    if s.tickHost then s.tickHost:Hide() end
    s.pipHost:Hide()
    s.stackBar:Hide()
end

--- Hides every piece; for a set whose occupant is no longer a stacks kind.
function Stacks.HideSet(s)
    if s then Hide(s) end
end

-- N-1 ticks over the bar's inner rect at the shared segment boundaries, above
-- the fill. The host follows the inner rect, so a border change moves them.
local function LayoutTicks(s, db, barElem, n)
    local host = s.tickHost
    if not host then return end
    local barW = tonumber(db and db.barWidth) or 120
    local inset = barElem.fillInset
    if inset then
        barW = math.max(1, barW - (inset.left or 0) - (inset.right or 0))
    end
    local tick = math.max(0, math.floor(tonumber(db and db.tickThickness) or 2))
    local color = (db and db.tickColor) or { 0, 0, 0, 1 }
    host:Show()
    for i = 1, n - 1 do
        local tex = s.ticks[i]
        if not tex then
            tex = host:CreateTexture(nil, "ARTWORK")
            s.ticks[i] = tex
        end
        if tick > 0 then
            local _, x1 = SAU.Pips.SegmentEdges(barW, n, tick, i)
            tex:ClearAllPoints()
            tex:SetPoint("TOP", host, "TOP", 0, 0)
            tex:SetPoint("BOTTOM", host, "BOTTOM", 0, 0)
            tex:SetPoint("LEFT", host, "LEFT", x1, 0)
            tex:SetWidth(tick)
            tex:SetColorTexture(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
            tex:Show()
        else
            tex:Hide()
        end
    end
    for i = math.max(1, n), #s.ticks do
        s.ticks[i]:Hide()
    end
end

-- The row: the transparent StatusBar spanning it, N backdrops on the host,
-- N glyphs in the clip, every piece anchored to its cell on the container.
local function LayoutShapes(s, container, db, n)
    local size = math.max(1, tonumber(db and db.pipSize) or 16)
    local gap = math.max(0, tonumber(db and db.pipSpacing) or 2)
    local atlas = SAU._AtlasFromShapeKey(db and db.pipStyle) or "SquareMask"
    local bw = SAU.Pips.BorderWidth(db and db.pipStyle, size)
    local pr, pg, pb = ShapeColor(db)
    local bd = (db and db.pipBackdropTint) or { 0, 0, 0, 1 }
    local bdAlpha = (tonumber(db and db.pipBackdropOpacity) or 100) / 100

    local bar = s.stackBar
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    bar:SetSize(SAU.Pips.RowWidth(n, size, gap), size)
    bar:Show()
    s.pipHost:Show()

    for i = 1, n do
        local pip = s.pips[i]
        if not pip then
            pip = {
                ring = s.pipHost:CreateTexture(nil, "ARTWORK", nil, -1),
                backdrop = s.pipHost:CreateTexture(nil, "ARTWORK"),
                fg = s.clip:CreateTexture(nil, "ARTWORK"),
            }
            s.pips[i] = pip
        end
        local x = (i - 1) * (size + gap)
        local inner = math.max(1, size - 2 * bw)

        local ring = pip.ring
        ring:ClearAllPoints()
        ring:SetPoint("TOPLEFT", container, "TOPLEFT", x, 0)
        ring:SetSize(size, size)
        SAU.Pips.PaintRing(ring, atlas, bw)

        local backdrop = pip.backdrop
        backdrop:ClearAllPoints()
        backdrop:SetPoint("TOPLEFT", container, "TOPLEFT", x + bw, -bw)
        backdrop:SetSize(inner, inner)
        if pcall(backdrop.SetAtlas, backdrop, atlas) then
            -- A white mask ignores desaturation alone, so both calls.
            backdrop:SetDesaturated(true)
            backdrop:SetVertexColor(bd[1] or 0, bd[2] or 0, bd[3] or 0, 1)
        else
            backdrop:SetColorTexture(bd[1] or 0, bd[2] or 0, bd[3] or 0, 1)
        end
        backdrop:SetAlpha(bdAlpha)
        backdrop:Show()

        local fg = pip.fg
        fg:ClearAllPoints()
        fg:SetPoint("TOPLEFT", container, "TOPLEFT", x + bw, -bw)
        fg:SetSize(inner, inner)
        if pcall(fg.SetAtlas, fg, atlas) then
            fg:SetDesaturated(false)
            fg:SetVertexColor(pr, pg, pb, 1)
        else
            fg:SetColorTexture(pr, pg, pb, 1)
        end
        fg:Show()
    end
    for i = n + 1, #s.pips do
        s.pips[i].ring:Hide()
        s.pips[i].backdrop:Hide()
        s.pips[i].fg:Hide()
    end
end

--- Lays the pieces out on one set for the tracker's shape. `set` carries
-- `container` (the frame the layout sized), `elements` and `stacks`.
-- `filled` is nil on the live set, whose fill the engine feeds, and a number
-- on a Scoot-owned set, which takes it as a plain value.
function Stacks.PaintSet(set, tracker, db, n, filled)
    local s = set and set.stacks
    if not s then return end
    Hide(s)
    local shape = tracker and tracker.shape
    local barElem = FindBarElem(set.elements)
    if shape == "bar" and barElem then
        LayoutTicks(s, db, barElem, n)
        if filled ~= nil and barElem.barFill then
            barElem.barFill:SetMinMaxValues(0, n)
            barElem.barFill:SetValue(filled)
        end
    elseif shape == "icons" then
        LayoutShapes(s, set.container, db, n)
        if filled ~= nil then
            s.stackBar:SetMinMaxValues(0, n)
            s.stackBar:SetValue(filled)
        end
    end
end

-- The Floating Number's host is the widest of these in the count's font.
local NUMBER_SAMPLES = { "9", "99", "999" }
local numberRuler

--- Natural width and height of the widest sample count in the stack font.
-- Called by the layout pass for the Floating Number; plain, because the
-- ruler never holds the live count.
function Stacks.MeasureNumber(db)
    if not numberRuler then
        local holder = CreateFrame("Frame", nil, UIParent)
        holder:SetSize(1, 1)
        holder:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        holder:Hide()
        numberRuler = holder:CreateFontString(nil, "OVERLAY")
        numberRuler:SetPoint("CENTER", holder, "CENTER", 0, 0)
        numberRuler:SetWidth(0)
        numberRuler:SetWordWrap(false)
    end
    local face = addon.ResolveFontFace(db and db.stackTextFont)
    local size = tonumber(db and db.stackTextSize) or 14
    -- MetricStyle: a Deep Shadow style must not build a companion copy on a
    -- hidden ruler. The metrics are the same either way.
    addon.ApplyFontStyle(numberRuler, face, size,
        addon.FontStyles.MetricStyle((db and db.stackTextStyle) or "OUTLINE"))
    local width, height = 0, nil
    for _, sample in ipairs(NUMBER_SAMPLES) do
        numberRuler:SetText(sample)
        local ok, w = pcall(numberRuler.GetUnboundedStringWidth, numberRuler)
        local ok2, h = pcall(numberRuler.GetStringHeight, numberRuler)
        if ok and type(w) == "number" and not issecretvalue(w) and w > width then width = w end
        if ok2 and type(h) == "number" and not issecretvalue(h) and (not height or h > height) then
            height = h
        end
    end
    return width, height
end

--- Host size of the Group of Shapes: the row at the configured size and
-- spacing. Called by the layout pass; no widget is read.
function Stacks.IconsHostSize(tracker, db)
    local n = SAU.ResolveMaxStacks(tracker)
    local size = math.max(1, tonumber(db and db.pipSize) or 16)
    local gap = math.max(0, tonumber(db and db.pipSpacing) or 2)
    return SAU.Pips.RowWidth(n, size, gap), size
end

--- The live pass, from Engine.ApplyAll after the layout, under the structural
-- gate (the pieces are children of the engine button). A kind that is not a
-- stacks kind has no pieces on its wire: OnWire dropped them.
function Stacks.Paint(trackerId, tracker, state)
    local entry = state and state.entry
    local s = entry and entry.stacks
    if not s or not SAU.KindTracksStacks(tracker.kind) then return end
    local db = SAU.GetDB(trackerId)
    local n, source = SAU.ResolveMaxStacks(tracker)
    local ok, err = pcall(Stacks.PaintSet,
        { container = state.container, elements = state.elements, stacks = s }, tracker, db, n, nil)
    if ok then
        SetResult("stacks.t" .. trackerId, string.format("n=%d (%s) shape=%s", n, source, tostring(tracker.shape)))
    else
        SetResult("stacks.t" .. trackerId, "paint FAILED: " .. SafeToString(err))
    end
end

--------------------------------------------------------------------------------
-- Debug
--------------------------------------------------------------------------------

function Stacks.DebugInfo(trackerId)
    local lines, add = addon.DebugLines()

    local tracker = SAU.GetTracker(trackerId)
    if not tracker then
        add("t%s: no such tracker", tostring(trackerId))
        return lines
    end
    local db = SAU.GetDB(trackerId)
    add("t%d name=%q kind=%s shape=%s unit=%s spell=%s stacksKind=%s",
        trackerId, SAU.DisplayName(tracker), tostring(tracker.kind), tostring(tracker.shape),
        tostring(tracker.unit), tostring(tracker.spellId), tostring(SAU.KindTracksStacks(tracker.kind)))
    add("missingVisual stored=%s resolved=%s", tostring(tracker.missingVisual), SAU.MissingVisualFor(tracker))

    local n, source = SAU.ResolveMaxStacks(tracker)
    add("max=%d (%s) override=%s default=%d cap=%d", n, source, tostring(tracker.maxStacks),
        SAU.DEFAULT_MAX_STACKS, SAU.MAX_STACK_PIPS)
    local detected, sawSecret = SAU.DetectMaxStacks(tracker.spellId)
    add("detected=%s sawSecret=%s ShouldAurasBeSecret=%s", tostring(detected), tostring(sawSecret),
        tostring(C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()))
    local getter = C_Spell and C_Spell.GetSpellMaxCumulativeAuraApplications
    add("GetSpellMaxCumulativeAuraApplications=%s", getter and "function" or "missing")
    if getter and addon.AuraIds and addon.AuraIds.GetExpansion then
        local set = addon.AuraIds.GetExpansion(tracker.spellId) or {}
        for id in pairs(set) do
            local ok, v = pcall(getter, id)
            local secret = ok and issecretvalue and issecretvalue(v)
            add("  id=%d -> %s%s", id, ok and (secret and "secret" or tostring(v)) or ("error: " .. SafeToString(v)),
                (id == tracker.spellId) and "  (picked)" or "")
        end
    end

    add("pipStyle=%s pipSize=%s pipSpacing=%s pipColorMode=%s tick=%s hideStackText=%s stackTextInnerAnchor=%s",
        tostring(db and db.pipStyle), tostring(db and db.pipSize), tostring(db and db.pipSpacing),
        tostring(db and db.pipColorMode), tostring(db and db.tickThickness), tostring(db and db.hideStackText),
        tostring(db and db.stackTextInnerAnchor))
    add("countFormatter=%s", countFormatter and "ready" or (countFormatterFailed and "failed" or "not built"))

    local state = SAU._activeStates[trackerId]
    local entry = state and state.entry
    local s = entry and entry.stacks
    add("entry=%s wired=%s button=%s pieces=%s hostW=%s hostH=%s",
        tostring(entry ~= nil), tostring(entry and entry.wired), tostring(entry and entry.button ~= nil),
        tostring(s ~= nil), tostring(entry and entry.hostW), tostring(entry and entry.hostH))
    if s then
        add("ticks=%d shapes=%d tickHost=%s stackBar shown=%s",
            #s.ticks, #s.pips, tostring(s.tickHost ~= nil), tostring(s.stackBar:IsShown()))
    end
    local results = Engine._results
    if type(results) == "table" then
        for _, key in ipairs({ "stacks.t" .. trackerId, "bind.t" .. trackerId .. ".SetApplicationBar",
            "bind.t" .. trackerId .. ".SetApplicationCount", "stackfmt", "underlay.t" .. trackerId }) do
            if results[key] ~= nil then add("%s = %s", key, tostring(results[key])) end
        end
    end
    return lines
end
