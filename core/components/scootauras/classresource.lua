-- scootauras/classresource.lua - Class Resource trackers: the player's point
-- resource (combo points, runes, arcane charges, holy power, chi, soul shards,
-- essence) as a segmented bar or as a row of icons
--
-- The second kind that owns no AuraContainer (classpower.lua is the first).
-- Every pip is a Scoot StatusBar fed by setters that accept secret arguments:
-- a pip ranged (i-1, i) and fed the count is full at or above i and empty at
-- or below i-1, so C compares and Lua never does. Nothing is read back, the
-- structural gate never applies, and creation, restyle and shape flips are
-- legal mid-combat.
--
--   visual (Scoot, W x H from SetHostSize)
--    +- root (Scoot)                                   level visual+3
--        +- element set (Engine.BuildElementSet): the bar element is the
--        |  outer bar on the Bar shape (size, background and border from the
--        |  shared chain); its own fill is never fed. Icon, texts and the
--        |  drain stay hidden.
--        +- pip[i] StatusBar, the gate                  level root+2
--        |   +- backdrop  Texture, SetAllPoints(pip)               Icons shape
--        |   +- fg        Texture, SetAllPoints(the pip's fill)    Icons shape
--        |   +- cooldown  Cooldown, reverse swipe        Icons shape; runes, essence
--        +- tick[i] Texture on the outer bar, between pip i and i+1   Bar shape
--
-- Runes and the recharging essence ride timers: SetTimerDuration on a bar
-- segment, and on an icon a reverse Cooldown swipe of the pip's own atlas in
-- the foreground color, so the color sweeps back in over the backdrop. The
-- tracker follows the character: class, spec and (for a Druid) the display
-- power decide the resource, and a character with none hides the art outside
-- Edit Mode.
local addonName, addon = ...

local SAU = addon.ScootAuras
local Engine = SAU.Engine

local ClassResource = {}
SAU.ClassResource = ClassResource

local INTERP_IMMEDIATE = (Enum and Enum.StatusBarInterpolation
    and Enum.StatusBarInterpolation.Immediate) or 0
local DIR_ELAPSED = (Enum and Enum.StatusBarTimerDirection
    and Enum.StatusBarTimerDirection.ElapsedTime) or 0
local WHITE8x8 = "Interface\\Buttons\\WHITE8x8"

-- Seven combo points is the widest resource today; the cap keeps a bad max
-- from building an unbounded row.
local MAX_PIPS = 10
local RUNE_COUNT = 6
-- Essence regenerates one point per five seconds when the API reports no
-- rate, the same fallback Blizzard's essence frame uses.
local ESSENCE_FALLBACK_REGEN = 0.2
local PLACEHOLDER_COUNT = 5

-- [trackerId] = entry, for the live trackers. The event frame registers while
-- this holds anything and unregisters when it empties.
local live = {}
local SyncEvents

--------------------------------------------------------------------------------
-- Secret-aware helpers
--------------------------------------------------------------------------------

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Plain(v)
    return type(v) == "number" and not IsSecret(v)
end

local function PlainBool(v)
    return type(v) == "boolean" and not IsSecret(v)
end

local function Describe(v)
    if IsSecret(v) then return "secret" end
    if type(v) == "table" then return "table" end
    return tostring(v)
end

-- Never index a name table with the raw return: a secret table key throws.
local function Named(names, value)
    if IsSecret(value) then return "secret" end
    return names[value] or tostring(value)
end

local POWER_NAMES = {}
local SECRECY_NAMES = {}
if Enum and Enum.PowerType then
    for name, value in pairs(Enum.PowerType) do
        if type(value) == "number" then POWER_NAMES[value] = name end
    end
end
if Enum and Enum.SecrecyLevel then
    for name, value in pairs(Enum.SecrecyLevel) do
        if type(value) == "number" then SECRECY_NAMES[value] = name end
    end
end

--------------------------------------------------------------------------------
-- The resources
--------------------------------------------------------------------------------

local PT = (Enum and Enum.PowerType) or {}
local POWER_ENERGY = PT.Energy or 3

-- token: the string Blizzard's power color table and the power events use.
-- Colors are looked up by this token, never by the enum number, whose
-- numeric fallback rows disagree with the enum. classColor: the resource
-- has no power color of its own, so the power mode paints the class color.
-- variedTail: the last two points may take their own colors.
local RESOURCES = {
    COMBO_POINTS   = { token = "COMBO_POINTS",   powerType = PT.ComboPoints   or 4,  defaultCount = 5, label = "Combo Points", classColor = true, variedTail = true },
    RUNES          = { token = "RUNES",          powerType = PT.Runes         or 5,  defaultCount = 6, label = "Runes", runes = true },
    SOUL_SHARDS    = { token = "SOUL_SHARDS",    powerType = PT.SoulShards    or 7,  defaultCount = 5, label = "Soul Shards", fractionalSpec = 267 },
    HOLY_POWER     = { token = "HOLY_POWER",     powerType = PT.HolyPower     or 9,  defaultCount = 5, label = "Holy Power" },
    CHI            = { token = "CHI",            powerType = PT.Chi           or 12, defaultCount = 5, label = "Chi", eventTokens = { CHI = true, DARK_FORCE = true } },
    ARCANE_CHARGES = { token = "ARCANE_CHARGES", powerType = PT.ArcaneCharges or 16, defaultCount = 4, label = "Arcane Charges" },
    ESSENCE        = { token = "ESSENCE",        powerType = PT.Essence       or 19, defaultCount = 5, label = "Essence", essence = true, labelGlobal = "POWER_TYPE_ESSENCE" },
}

local RESOURCE_BY_CLASS = {
    ROGUE = "COMBO_POINTS", DRUID = "COMBO_POINTS", DEATHKNIGHT = "RUNES", MAGE = "ARCANE_CHARGES",
    PALADIN = "HOLY_POWER", MONK = "CHI", WARLOCK = "SOUL_SHARDS", EVOKER = "ESSENCE",
}

-- Resources one spec of the class owns: Arcane Charges (Arcane), Chi
-- (Windwalker). Every other resource belongs to every spec of its class.
local RESOURCE_SPECS = {
    ARCANE_CHARGES = { [62] = true },
    CHI = { [269] = true },
}

-- What the character sheet calls each resource: Blizzard's own global string
-- for the token, localized, with the English name behind it.
local function ResourceLabel(res)
    local global = _G[res.labelGlobal or res.token]
    if type(global) == "string" and global ~= "" then return global end
    return res.label
end

local function ClassToken()
    local ok, token = pcall(addon.GetClassTokenForUnit, "player")
    if ok and type(token) == "string" then return token end
    return nil
end

--- The resource this character runs on right now: class, then the spec
-- table, then (for a Druid) the display power, since combo points exist in
-- cat form alone. Returns a fresh record; `applicable` false carries the
-- reason. Plain reads only: class and spec are plain, and the display power
-- index is guarded.
local function Resolve()
    local classToken = ClassToken()
    local specID = SAU.CurrentSpecID()
    local key = classToken and RESOURCE_BY_CLASS[classToken] or nil
    local rec = {
        classToken = classToken, specID = specID, key = key,
        res = key and RESOURCES[key] or nil,
        applicable = false, reason = nil, fractional = false,
    }
    if not rec.res then
        rec.reason = "no point resource for " .. tostring(classToken)
        return rec
    end
    local specs = RESOURCE_SPECS[key]
    if specs and not (specID and specs[specID]) then
        rec.reason = "spec " .. tostring(specID) .. " does not use " .. rec.res.label
        return rec
    end
    if classToken == "DRUID" then
        local ok, idx = pcall(UnitPowerType, "player")
        if not (ok and Plain(idx) and idx == POWER_ENERGY) then
            rec.reason = "display power is " .. (ok and Named(POWER_NAMES, idx) or "unknown") .. ", not Energy"
            return rec
        end
    end
    rec.applicable = true
    rec.reason = "class"
    rec.fractional = (rec.res.fractionalSpec ~= nil and specID == rec.res.fractionalSpec)
    return rec
end

--- The resolved record, for the editor preview and the debug dump.
function ClassResource.CurrentResource()
    return Resolve()
end

--------------------------------------------------------------------------------
-- Name: the resource the tracker's specs run on
--------------------------------------------------------------------------------

local function KeyForSpec(specID)
    if type(specID) ~= "number" then return nil end
    local classToken = SAU.ClassTokenForSpec(specID)
    local key = classToken and RESOURCE_BY_CLASS[classToken] or nil
    if not key then return nil end
    local specs = RESOURCE_SPECS[key]
    if specs and not specs[specID] then return nil end
    return key
end

--- The tracker's auto name: the resource its naming spec runs on
-- (SAU.NamingSpec, as the Class Power name), "Combo Points" for a Rogue's. A
-- naming spec the table excludes falls to the first listed spec it accepts,
-- so a Fire Mage's three-spec tracker still reads "Arcane Charges"; "Class
-- Resource" when none does. Live, never stored, as the Class Power name is.
function ClassResource.NameForSpecs(specs, homeSpec)
    local first
    for _, specID in ipairs(type(specs) == "table" and specs or {}) do
        first = KeyForSpec(specID)
        if first then break end
    end
    local key = KeyForSpec(SAU.NamingSpec(specs, homeSpec)) or first
    return key and ResourceLabel(RESOURCES[key]) or "Class Resource"
end

--------------------------------------------------------------------------------
-- Scoot-owned visual (per pool entry, session-permanent)
--------------------------------------------------------------------------------

local function FindBarElem(elements)
    for _, elem in ipairs(elements or {}) do
        if elem.type == "bar" then return elem end
    end
    return nil
end

local function EnsureVisual(entry)
    if entry.classResource then return entry.classResource end
    local visual = entry.visual

    -- Above the missing-state underlay (visual + 2), below a parked container
    -- (visual + 5) and the Edit Mode preview (visual + 10). The Class Power
    -- root sits at the same level; the two Sync passes keep them exclusive.
    local root = CreateFrame("Frame", nil, visual)
    root:SetAllPoints(visual)
    root:SetFrameLevel(visual:GetFrameLevel() + 3)
    root:Hide()

    local set = Engine.BuildElementSet(root)

    local cr = {
        root = root,
        elements = set.elements,
        textFrame = set.textFrame,
        pips = {},
        count = 0,
        last = {},
        lastMax = {},
        runeScratch = {},
        eventCount = 0,
    }
    for i = 1, RUNE_COUNT do cr.runeScratch[i] = { index = i } end
    entry.classResource = cr
    return cr
end

-- One pip: the gate StatusBar and everything that rides it. Every frame here
-- is Scoot's, so creation is legal in combat.
local function CreatePip(cr)
    local root = cr.root
    local bar = CreateFrame("StatusBar", nil, root)
    bar:SetFrameLevel(root:GetFrameLevel() + 2)
    bar:SetStatusBarTexture(WHITE8x8)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:Hide()

    local backdrop = bar:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints(bar)
    backdrop:Hide()

    local fg = bar:CreateTexture(nil, "ARTWORK")
    fg:Hide()

    -- The drain recipe (regions.lua): reverse, so the swipe grows as the
    -- cooldown runs. Painted in the foreground color, the swipe is the color
    -- sweeping in over the backdrop.
    local cooldown = CreateFrame("Cooldown", nil, bar, "CooldownFrameTemplate")
    cooldown:SetAllPoints(bar)
    cooldown:SetFrameLevel(bar:GetFrameLevel() + 1)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:SetHideCountdownNumbers(true)
    cooldown:SetReverse(true)
    cooldown:SetDrawSwipe(false)

    -- On the outer bar, so it hides with it on the Icons shape.
    local barElem = FindBarElem(cr.elements)
    local tickHost = barElem and barElem.widget or root
    local tick = tickHost:CreateTexture(nil, "ARTWORK")
    tick:Hide()

    local dur
    if C_DurationUtil and C_DurationUtil.CreateDuration then
        local ok, obj = pcall(C_DurationUtil.CreateDuration)
        if ok then dur = obj end
    end

    return { bar = bar, backdrop = backdrop, fg = fg, cooldown = cooldown, tick = tick, dur = dur }
end

-- Pips are never destroyed: a count that shrinks hides the extras, and a
-- count that grows reuses them.
local function EnsurePips(cr, n)
    n = math.max(1, math.min(MAX_PIPS, math.floor(n)))
    for i = #cr.pips + 1, n do
        cr.pips[i] = CreatePip(cr)
    end
    for i = n + 1, #cr.pips do
        cr.pips[i].bar:Hide()
        cr.pips[i].tick:Hide()
    end
    cr.count = n
end

-- The pip count: the plain max when it reads plain, else the last plain max
-- this session saw for the resource, else the resource's default. A character
-- with no resource takes a placeholder count for the Edit Mode art.
local function SyncCount(cr, resolved)
    local res = resolved.res
    if not res then
        cr.countSource = "placeholder"
        return PLACEHOLDER_COUNT
    end
    local ok, pmax = pcall(UnitPowerMax, "player", res.powerType)
    if ok and Plain(pmax) and pmax >= 1 then
        local n = math.floor(pmax)
        cr.lastMax[res.token] = n
        cr.countSource = "UnitPowerMax"
        return n
    end
    if cr.lastMax[res.token] then
        cr.countSource = "last plain max"
        return cr.lastMax[res.token]
    end
    cr.countSource = "default"
    return res.defaultCount
end

--- Host size of the Icons shape: the row of pips at the configured size and
-- spacing. Called by the layout pass; the count is the set's, never a read.
function ClassResource.IconsHostSize(entry, db)
    local cr = entry and entry.classResource
    local n = cr and cr.count or 0
    if n < 1 then n = PLACEHOLDER_COUNT end
    local size = tonumber(db and db.pipSize) or 16
    local gap = tonumber(db and db.pipSpacing) or 2
    return n * size + (n - 1) * gap, size
end

--------------------------------------------------------------------------------
-- Colors
--------------------------------------------------------------------------------

local function ClassColor()
    local r, g, b = addon.GetClassColorRGB("player")
    return r or 1, g or 1, b or 1
end

-- The resource's own color: the power color by token, or the class color
-- for a resource that has none (Combo Points).
local function PowerColor(resolved)
    local res = resolved and resolved.res
    if res and not res.classColor then
        local r, g, b = addon.GetPowerColorRGB(res.token)
        return r or 1, g or 1, b or 1
    end
    return ClassColor()
end

--- The resource's own color, for the editor preview.
function ClassResource.ResourceColorRGB()
    return PowerColor(Resolve())
end

-- The last two combo points: the last in TAIL_COLOR, a crimson, the one
-- before it halfway between the base color and TAIL_COLOR. Every earlier
-- point keeps the base color. Crimson rather than a plain red: the Druid
-- orange differs from a red in the green channel alone, so a red midpoint
-- reads as a duller orange; the blue cast keeps both tail points apart
-- from it and the midpoint bright.
local TAIL_COLOR = { 0.90, 0.12, 0.30 }

local function VariedTail(db, resolved)
    local res = resolved and resolved.res
    return (res and res.variedTail and (not db or db.variedLastPoints ~= false)) and true or false
end

--- Pip i of n in the tail scheme, from the base color; the editor preview
--- paints its sample through this.
function ClassResource.TailColorAt(i, n, r, g, b)
    if n < 2 then return r, g, b end
    if i == n then return TAIL_COLOR[1], TAIL_COLOR[2], TAIL_COLOR[3] end
    if i == n - 1 then
        return (r + TAIL_COLOR[1]) / 2, (g + TAIL_COLOR[2]) / 2, (b + TAIL_COLOR[3]) / 2
    end
    return r, g, b
end

local function PipColorAt(varied, i, n, r, g, b)
    if not varied then return r, g, b end
    return ClassResource.TailColorAt(i, n, r, g, b)
end

-- Kept off addon.ResolveColorRGBA: three-mode dialect whose power source is the resource token, not a unit.
local function PipColor(db, resolved)
    local mode = db and db.pipColorMode or "power"
    if mode == "custom" then
        local c = db.pipTint or { 1, 1, 1, 1 }
        return c[1] or 1, c[2] or 1, c[3] or 1
    elseif mode == "class" then
        return ClassColor()
    end
    return PowerColor(resolved)
end

--------------------------------------------------------------------------------
-- Pip layout (Tier 1: Scoot frames only)
--------------------------------------------------------------------------------

-- Bar shape: N segments tiling the outer bar's inner rect exactly (the rect
-- inside the Square border's reach, regions.lua CreateBarElement), a tick of
-- the configured thickness between neighbours, each segment carrying the
-- fill texture and color the shared chain resolves for a bar, the last two
-- in the tail colors where the resource offers them.
local function LayoutBarPips(cr, db, barElem, tracker, resolved)
    local n = cr.count
    local barW = tonumber(db and db.barWidth) or 120
    local barH = tonumber(db and db.barHeight) or 12
    local inset = barElem.fillInset
    if inset then
        barW = math.max(1, barW - (inset.left or 0) - (inset.right or 0))
        barH = math.max(1, barH - (inset.top or 0) - (inset.bottom or 0))
    end
    local tick = math.max(0, math.floor(tonumber(db and db.tickThickness) or 2))
    local tickColor = (db and db.tickColor) or { 0, 0, 0, 1 }
    local fgPath, r, g, b, a = SAU._ResolveBarFill(tracker, db, { PowerColor(resolved) })
    local varied = VariedTail(db, resolved)
    local segW = (barW - (n - 1) * tick) / n
    if segW < 1 then segW = 1 end
    local host = barElem.inner or barElem.widget
    for i = 1, n do
        local pip = cr.pips[i]
        local x0 = math.floor((i - 1) * (segW + tick) + 0.5)
        local x1 = math.floor(i * segW + (i - 1) * tick + 0.5)
        local bar = pip.bar
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", host, "TOPLEFT", x0, 0)
        bar:SetSize(math.max(1, x1 - x0), barH)
        bar:SetStatusBarTexture(fgPath or WHITE8x8)
        local sr, sg, sb = PipColorAt(varied, i, n, r, g, b)
        bar:SetStatusBarColor(sr, sg, sb, a)
        bar:Show()
        pip.backdrop:Hide()
        pip.fg:Hide()
        pcall(pip.cooldown.SetDrawSwipe, pip.cooldown, false)
        local t = pip.tick
        if i < n and tick > 0 then
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", host, "TOPLEFT", x1, 0)
            t:SetSize(tick, barH)
            t:SetColorTexture(tickColor[1] or 0, tickColor[2] or 0, tickColor[3] or 0, tickColor[4] or 1)
            t:Show()
        else
            t:Hide()
        end
    end
end

-- Icons shape: a row of glyphs. The gate's own fill is invisible; the
-- foreground glyph is anchored to the fill's rect, so it is whole when the
-- pip is full and has no rect when it is empty. The backdrop is the same
-- glyph beneath, desaturated and tinted, and shows alone for a missing
-- point. The cooldown's swipe is the glyph in the foreground color, drawn
-- for the resources that recharge.
local function LayoutIconPips(cr, db, resolved)
    local n = cr.count
    local size = math.max(1, tonumber(db and db.pipSize) or 16)
    local gap = tonumber(db and db.pipSpacing) or 2
    local atlas = SAU._AtlasFromShapeKey(db and db.pipStyle) or "SquareMask"
    local pr, pg, pb = PipColor(db, resolved)
    local varied = VariedTail(db, resolved)
    local bd = (db and db.pipBackdropTint) or { 0, 0, 0, 1 }
    local bdAlpha = (tonumber(db and db.pipBackdropOpacity) or 100) / 100
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    local res = resolved and resolved.res
    local timed = (res and (res.runes or res.essence)) and true or false
    for i = 1, n do
        local pip = cr.pips[i]
        local bar = pip.bar
        bar:ClearAllPoints()
        bar:SetPoint("LEFT", cr.root, "LEFT", (i - 1) * (size + gap), 0)
        bar:SetSize(size, size)
        bar:SetStatusBarTexture(WHITE8x8)
        bar:SetStatusBarColor(1, 1, 1, 0)
        bar:Show()
        pip.tick:Hide()

        local backdrop = pip.backdrop
        if pcall(backdrop.SetAtlas, backdrop, atlas) then
            -- A white mask ignores desaturation alone, so both calls.
            backdrop:SetDesaturated(true)
            backdrop:SetVertexColor(bd[1] or 0, bd[2] or 0, bd[3] or 0, 1)
        else
            backdrop:SetColorTexture(bd[1] or 0, bd[2] or 0, bd[3] or 0, 1)
        end
        backdrop:SetAlpha(bdAlpha)
        backdrop:Show()

        local pipR, pipG, pipB = PipColorAt(varied, i, n, pr, pg, pb)
        local fg = pip.fg
        if pcall(fg.SetAtlas, fg, atlas) then
            fg:SetDesaturated(false)
            fg:SetVertexColor(pipR, pipG, pipB, 1)
        else
            fg:SetColorTexture(pipR, pipG, pipB, 1)
        end
        fg:ClearAllPoints()
        fg:SetAllPoints(bar:GetStatusBarTexture())
        fg:Show()

        local cd = pip.cooldown
        pcall(cd.SetSwipeColor, cd, pipR, pipG, pipB, 1)
        if info and (info.file or info.filename) then
            pcall(cd.SetSwipeTexture, cd, info.file or info.filename)
            pcall(cd.SetTexCoordRange, cd,
                { x = info.leftTexCoord, y = info.topTexCoord },
                { x = info.rightTexCoord, y = info.bottomTexCoord })
        else
            pcall(cd.SetSwipeTexture, cd, WHITE8x8)
        end
        pcall(cd.SetReverse, cd, true)
        pcall(cd.SetDrawSwipe, cd, timed)
    end
end

--- Paints one Scoot-owned element set as the tracker: the shared styling and
-- layout chain on the outer bar, everything the kind never shows hidden, then
-- the pips laid out for the shape. The values are painted separately
-- (PaintValues): they move on every power event, and the chain does not.
function ClassResource.PaintElementSet(trackerId, tracker, shim, elements, cr)
    local db = SAU.GetDB(trackerId)

    SAU._ApplyShapeStyling(trackerId, tracker, shim)
    SAU._ApplyBarStyling(trackerId, tracker, shim)
    SAU._LayoutElements(trackerId, tracker, shim)

    local barElem
    for _, elem in ipairs(elements or {}) do
        if elem.type == "texture" then
            elem.widget:Hide()
            if elem.borderFrame then elem.borderFrame:Hide() end
            if elem.silhouette then elem.silhouette:Hide() end
        elseif elem.type == "text" then
            elem.widget:Hide()
        elseif elem.type == "bar" then
            barElem = elem
            -- The outer bar's own fill is never fed; the segments are.
            elem.barFill:Hide()
            if tracker.shape ~= "bar" then elem.widget:Hide() end
        elseif elem.type == "cooldown" then
            pcall(elem.widget.Clear, elem.widget)
            elem.widget:Hide()
        end
    end

    if not (cr and db) then return end
    if tracker.shape == "bar" and barElem then
        LayoutBarPips(cr, db, barElem, tracker, cr.resolved)
    else
        LayoutIconPips(cr, db, cr.resolved)
    end
end

--------------------------------------------------------------------------------
-- The feeds: setters fed straight from the power API
--------------------------------------------------------------------------------

local function SetPipFull(cr, i)
    local pip = cr.pips[i]
    pcall(pip.bar.SetMinMaxValues, pip.bar, 0, 1, INTERP_IMMEDIATE)
    pcall(pip.bar.SetValue, pip.bar, 1, INTERP_IMMEDIATE)
    pcall(pip.cooldown.Clear, pip.cooldown)
    cr.last[i] = "full"
end

local function SetPipEmpty(cr, i)
    local pip = cr.pips[i]
    pcall(pip.bar.SetMinMaxValues, pip.bar, 0, 1, INTERP_IMMEDIATE)
    pcall(pip.bar.SetValue, pip.bar, 0, INTERP_IMMEDIATE)
    pcall(pip.cooldown.Clear, pip.cooldown)
    cr.last[i] = "empty"
end

local function ZeroPips(cr)
    for i = 1, cr.count do SetPipEmpty(cr, i) end
end

-- A recharge on one pip. Bar: the engine timer fills the segment over the
-- span, no Lua ticking. Icons: the glyph collapses (SetValue 0) and the
-- reverse swipe paints the color sweeping in; it equals the whole glyph at
-- the end, so the hand-off to a full pip on the next event shows no step.
-- Both take plain timings only.
local function StartTimer(cr, i, start, duration, shape)
    local pip = cr.pips[i]
    local bar = pip.bar
    pcall(bar.SetMinMaxValues, bar, 0, 1, INTERP_IMMEDIATE)
    if shape == "bar" then
        pcall(pip.cooldown.Clear, pip.cooldown)
        if pip.dur and bar.SetTimerDuration then
            local okT = pcall(pip.dur.SetTimeFromStart, pip.dur, start, duration)
            local okB = okT and pcall(bar.SetTimerDuration, bar, pip.dur, INTERP_IMMEDIATE, DIR_ELAPSED)
            cr.last[i] = okB and "timer" or "timer failed"
        else
            pcall(bar.SetValue, bar, 0, INTERP_IMMEDIATE)
            cr.last[i] = "no duration API"
        end
    else
        pcall(bar.SetValue, bar, 0, INTERP_IMMEDIATE)
        local ok = pcall(pip.cooldown.SetCooldown, pip.cooldown, start, duration)
        cr.last[i] = ok and "swipe" or "swipe failed"
    end
end

-- The count feed: range and value on every pip, every event. Both, because
-- a plain SetValue is what cancels a running timer, and the range is what
-- returns a pip from the timer path to the count. On the Bar shape a
-- fractional resource is read unmodified and the ranges scale by the display
-- modifier, so the partial pip fills by tenths with no arithmetic on the
-- value; the Icons shape always takes the whole count. Returns the count as
-- read (possibly secret), or nil when the read failed.
local function FeedCount(cr, tracker, resolved)
    local res = resolved.res
    local unmodified = (tracker.shape == "bar" and resolved.fractional) and true or false
    local okV, cur = pcall(UnitPower, "player", res.powerType, unmodified)
    if not okV or type(cur) ~= "number" then
        cr.last.feed = okV and ("UnitPower returned " .. type(cur)) or "UnitPower error"
        return nil
    end
    local mod = 1
    if unmodified then
        local okD, m = pcall(UnitPowerDisplayMod, res.powerType)
        mod = (okD and Plain(m) and m > 0) and m or 10
    end
    for i = 1, cr.count do
        local pip = cr.pips[i]
        pcall(pip.bar.SetMinMaxValues, pip.bar, (i - 1) * mod, i * mod, INTERP_IMMEDIATE)
        pcall(pip.bar.SetValue, pip.bar, cur, INTERP_IMMEDIATE)
        pcall(pip.cooldown.Clear, pip.cooldown)
        cr.last[i] = "count"
    end
    cr.last.feed = unmodified and "count (tenths)" or "count"
    return cur
end

-- Ready first; then the earliest start, the first to come back; a rune whose
-- cooldown has not begun last; the rune index breaks ties so equal starts
-- never swap pips between events.
local function RuneBefore(a, b)
    if a.ready ~= b.ready then return a.ready end
    if a.ready then return a.index < b.index end
    local aHas, bHas = a.start ~= nil, b.start ~= nil
    if aHas ~= bHas then return aHas end
    if aHas and a.start ~= b.start then return a.start < b.start end
    return a.index < b.index
end

-- Runes: the six read plain, sorted, and assigned to pips left to right. A
-- read that comes back secret or fails falls to the count feed, which shows
-- the ready count whole-or-empty. The rune events carry secret payloads, so
-- the payload is never consulted; every event rescans all six.
local function PaintRunes(cr, tracker, resolved)
    local scratch = cr.runeScratch
    local plain = true
    for i = 1, RUNE_COUNT do
        local rec = scratch[i]
        local ok, start, duration, ready = pcall(GetRuneCooldown, i)
        rec.index = i
        if not ok or IsSecret(start) or IsSecret(duration) or IsSecret(ready) then
            plain = false
        end
        rec.ready = PlainBool(ready) and ready or false
        rec.start = (Plain(start) and start > 0) and start or nil
        rec.duration = (Plain(duration) and duration > 0) and duration or nil
    end
    if not plain then
        cr.last.runes = "secret or error; count feed"
        FeedCount(cr, tracker, resolved)
        return
    end
    table.sort(scratch, RuneBefore)
    local order = {}
    local slots = math.min(cr.count, RUNE_COUNT)
    for slot = 1, slots do
        local rec = scratch[slot]
        order[slot] = rec.index
        if rec.ready then
            SetPipFull(cr, slot)
        elseif rec.start and rec.duration then
            StartTimer(cr, slot, rec.start, rec.duration, tracker.shape)
        else
            SetPipEmpty(cr, slot)
        end
    end
    for slot = slots + 1, cr.count do SetPipEmpty(cr, slot) end
    cr.runeOrder = table.concat(order, " ")
    cr.last.runes = "ok"
end

-- Essence: the pip after the whole count recharges on the rune timer path.
-- Needs the count, the partial and the regen rate plain; otherwise the count
-- feed's whole-or-empty pips stand. The rate is re-read on every essence
-- event; a haste change mid-point drifts until the next one.
local function PaintEssence(cr, cur, res, tracker)
    if not Plain(cur) then
        cr.last.essence = "count secret; whole-or-empty"
        return
    end
    local idx = math.floor(cur) + 1
    if idx > cr.count then
        cr.last.essence = "full"
        return
    end
    local okP, partial = pcall(UnitPartialPower, "player", res.powerType)
    local okR, regen = pcall(GetPowerRegenForPowerType, res.powerType)
    if not (okP and Plain(partial) and okR and Plain(regen)) then
        cr.last.essence = "partial or regen secret; whole-or-empty"
        return
    end
    if regen <= 0 then regen = ESSENCE_FALLBACK_REGEN end
    local dur = 1 / regen
    local start = GetTime() - (partial / 1000) * dur
    StartTimer(cr, idx, start, dur, tracker.shape)
    cr.essencePip = idx
    cr.last.essence = "timer"
end

--- Feeds the live resource into the pips. Nothing here reads a value back:
-- the setters take secret arguments, and every verdict written to cr.last
-- describes the call, never the value. Runs on every power event, so it
-- stays a handful of setter calls per pip.
function ClassResource.PaintValues(trackerId, tracker, cr, db)
    local resolved = cr.resolved
    if not (resolved and resolved.applicable) then
        ZeroPips(cr)
        cr.last.feed = "inapplicable"
        return
    end
    local res = resolved.res
    if res.runes then
        PaintRunes(cr, tracker, resolved)
        return
    end
    local cur = FeedCount(cr, tracker, resolved)
    if res.essence and cur ~= nil then
        PaintEssence(cr, cur, res, tracker)
    end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

--- Whether the art shows: the resource applies, or Edit Mode is open, where
-- an inapplicable resource shows as empty pips so the frame stays draggable.
-- Plain state only; the combat gate is the shell's.
function ClassResource.UpdateGate(trackerId)
    local state = SAU._activeStates[trackerId]
    local entry = state and state.entry
    local cr = entry and entry.classResource
    if not cr or live[trackerId] ~= entry then return end
    local applicable = cr.resolved and cr.resolved.applicable or false
    local editing = SAU._isEditModeActive and SAU._isEditModeActive() or false
    cr.root:SetShown(applicable or editing)
end

local function Repaint(trackerId, tracker, entry, cr)
    cr.resolved = Resolve()
    EnsurePips(cr, SyncCount(cr, cr.resolved))
    local shim = { container = cr.root, elements = cr.elements, entry = entry }
    ClassResource.PaintElementSet(trackerId, tracker, shim, cr.elements, cr)
    ClassResource.PaintValues(trackerId, tracker, cr, SAU.GetDB(trackerId))
    ClassResource.UpdateGate(trackerId)
end

--- Full Tier 1 pass for one live tracker: build the art on first use,
-- resolve the resource, paint the set, feed the values, and join the power
-- event fan-out.
function ClassResource.Restyle(trackerId, tracker, state)
    local entry = state and state.entry
    if not entry then return end
    local cr = EnsureVisual(entry)
    live[trackerId] = entry
    Repaint(trackerId, tracker, entry, cr)
    SyncEvents()
    local res = cr.resolved and cr.resolved.res
    Engine._SetResult("build.t" .. trackerId, ("class resource (no container): %s n=%d (%s)"):format(
        res and res.token or "none", cr.count, tostring(cr.countSource)))
end

--- Hides the art and drops the tracker from the event fan-out. Safe for any
-- tracker id and for an entry that never built one.
function ClassResource.Release(trackerId, entry)
    if trackerId then live[trackerId] = nil end
    if entry and entry.classResource then entry.classResource.root:Hide() end
    SyncEvents()
end

--- The one entry point from ApplyStyling, for every kind: a Class Resource
-- tracker repaints, anything else on an entry that once hosted one hides it.
function ClassResource.Sync(trackerId, tracker, state)
    if tracker and tracker.kind == "classresource" then
        ClassResource.Restyle(trackerId, tracker, state)
    else
        ClassResource.Release(trackerId, state and state.entry)
    end
end

-- The art is not torn down: pool frames are session-permanent, and the next
-- occupant's Sync repaints it or leaves it hidden.
function ClassResource.OnEntryReleased(entry, trackerId)
    ClassResource.Release(trackerId or (entry and entry.occupantId), entry)
end

--------------------------------------------------------------------------------
-- Power events
--------------------------------------------------------------------------------

local eventFrame
local registered = false

-- Whether a power event's token names this tracker's resource. A secret
-- token fails open: a repaint costs a few setters, a missed event costs a
-- stale pip.
local function TokenMatches(resolved, token)
    local res = resolved and resolved.res
    if not res then return false end
    if IsSecret(token) then return true end
    if res.eventTokens then return res.eventTokens[token] == true end
    return token == res.token
end

local function OnPowerEvent(_, event, _, token)
    for trackerId, entry in pairs(live) do
        local tracker = SAU.GetTracker(trackerId)
        local state = SAU._activeStates[trackerId]
        local cr = entry.classResource
        if tracker and tracker.kind == "classresource" and state and state.entry == entry and cr then
            cr.eventCount = cr.eventCount + 1
            local resolved = cr.resolved
            if event == "UNIT_DISPLAYPOWER" then
                -- A form or spec change: the resource, the range and the
                -- color all move, so this is a full repaint.
                Repaint(trackerId, tracker, entry, cr)
            elseif event == "UNIT_MAXPOWER" then
                if TokenMatches(resolved, token) then
                    Repaint(trackerId, tracker, entry, cr)
                end
            elseif event == "RUNE_POWER_UPDATE" then
                if resolved and resolved.res and resolved.res.runes then
                    ClassResource.PaintValues(trackerId, tracker, cr, SAU.GetDB(trackerId))
                end
            elseif TokenMatches(resolved, token) then
                if resolved.applicable then
                    ClassResource.PaintValues(trackerId, tracker, cr, SAU.GetDB(trackerId))
                else
                    -- The candidate resource moved while the record read it
                    -- inapplicable (a Druid whose display power settled after
                    -- the form event): re-resolve.
                    Repaint(trackerId, tracker, entry, cr)
                end
            end
        else
            live[trackerId] = nil
        end
    end
end

-- Kept off addon.Events: unit-filtered registration.
-- The frame exists for RegisterUnitEvent: UNIT_POWER_FREQUENT fires for every
-- unit on screen, and C-side filtering to the player is what keeps the
-- handler quiet. The bus carries no unit-event API. RUNE_POWER_UPDATE rides
-- the same frame so the kind has one registration site.
function SyncEvents()
    local want = next(live) ~= nil
    if want == registered then return end
    registered = want
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", OnPowerEvent)
    end
    if want then
        eventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        eventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        eventFrame:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
        eventFrame:RegisterEvent("RUNE_POWER_UPDATE")
    else
        eventFrame:UnregisterAllEvents()
    end
end

--------------------------------------------------------------------------------
-- Debug
--------------------------------------------------------------------------------

local function R(ok, v)
    if ok then return Describe(v) end
    return "error: " .. tostring(v)
end

--- Lines for /scoot debug sa resource <id>: the resolved resource and its
-- secrecy, what each read returns right now, the colors, the pip count and
-- its source, the rune order, and the last paint per pip.
function ClassResource.DebugInfo(trackerId)
    local lines, add = addon.DebugLines()

    local tracker = SAU.GetTracker(trackerId)
    if not tracker then
        add("t%s: no such tracker", tostring(trackerId))
        return lines
    end
    local db = SAU.GetDB(trackerId)
    add("t%d name=%q (stored %s) kind=%s shape=%s onlyInCombat=%s enabled=%s",
        trackerId, SAU.DisplayName(tracker), tostring(tracker.name), tostring(tracker.kind),
        tostring(tracker.shape), tostring(tracker.onlyInCombat), tostring(tracker.enabled))
    add("fillMode=%s tick=%s pipStyle=%s pipSize=%s pipSpacing=%s pipColorMode=%s backdropOpacity=%s",
        tostring(db and db.barForegroundColorMode), tostring(db and db.tickThickness),
        tostring(db and db.pipStyle), tostring(db and db.pipSize), tostring(db and db.pipSpacing),
        tostring(db and db.pipColorMode), tostring(db and db.pipBackdropOpacity))
    add("specs=%s homeSpec=%s namingSpec=%s specAllows=%s currentSpec=%s active=%s",
        SAU.DescribeSpecs(tracker.specs) or "all", tostring(tracker.homeSpec),
        tostring(SAU.NamingSpec(tracker.specs, tracker.homeSpec)), tostring(SAU.SpecAllows(tracker)),
        tostring(SAU.CurrentSpecID()), tostring(SAU.IsTrackerActive(trackerId, tracker)))
    add("InCombatLockdown=%s editMode=%s gateOpen=%s",
        tostring(InCombatLockdown()),
        tostring(SAU._isEditModeActive and SAU._isEditModeActive()),
        tostring(SAU.CombatGateOpen(tracker)))

    add("")
    add("--- resource ---")
    local resolved = Resolve()
    local res = resolved.res
    add("class=%s spec=%s resource=%s applicable=%s (%s) fractional=%s",
        tostring(resolved.classToken), tostring(resolved.specID), res and res.token or "none",
        tostring(resolved.applicable), tostring(resolved.reason), tostring(resolved.fractional))
    if res then
        local pt = res.powerType
        local sok, level = pcall(function()
            return C_Secrets and C_Secrets.GetPowerTypeSecrecy and C_Secrets.GetPowerTypeSecrecy(pt)
        end)
        add("GetPowerTypeSecrecy=%s", sok and Named(SECRECY_NAMES, level) or "error")
        local pok, ps = pcall(function()
            return C_Secrets and C_Secrets.ShouldUnitPowerBeSecret and C_Secrets.ShouldUnitPowerBeSecret("player", pt)
        end)
        local mok, ms = pcall(function()
            return C_Secrets and C_Secrets.ShouldUnitPowerMaxBeSecret and C_Secrets.ShouldUnitPowerMaxBeSecret("player", pt)
        end)
        add("ShouldUnitPowerBeSecret=%s ShouldUnitPowerMaxBeSecret=%s", R(pok, ps), R(mok, ms))

        add("")
        add("--- reads now ---")
        local okV, v = pcall(UnitPower, "player", pt)
        local okU, u = pcall(UnitPower, "player", pt, true)
        local okM, m = pcall(UnitPowerMax, "player", pt)
        local okD, d = pcall(UnitPowerDisplayMod, pt)
        add("UnitPower=%s unmodified=%s UnitPowerMax=%s UnitPowerDisplayMod=%s",
            R(okV, v), R(okU, u), R(okM, m), R(okD, d))
        local okP, p = pcall(UnitPartialPower, "player", pt)
        local okR, r1, r2 = pcall(GetPowerRegenForPowerType, pt)
        add("UnitPartialPower=%s GetPowerRegenForPowerType=%s / %s", R(okP, p), R(okR, r1), R(okR, r2))
        local okC, s, dur, ready = pcall(GetRuneCooldown, 1)
        add("GetRuneCooldown(1)=%s %s %s  GetTime=%.2f  durationApi=%s",
            R(okC, s), R(okC, dur), R(okC, ready), GetTime(),
            tostring(C_DurationUtil ~= nil and C_DurationUtil.CreateDuration ~= nil))
        local okT, idx, tok = pcall(UnitPowerType, "player")
        add("UnitPowerType=%s (%s)", okT and Named(POWER_NAMES, idx) or "error", okT and Describe(tok) or "error")
    end
    local fr, fgc, fb = PowerColor(resolved)
    local pr, pg, pb = PipColor(db or {}, resolved)
    add("power color=%.2f %.2f %.2f  pip color=%.2f %.2f %.2f  varied tail=%s (setting %s)",
        fr, fgc, fb, pr, pg, pb, tostring(VariedTail(db, resolved)), tostring(db and db.variedLastPoints))

    local state = SAU._activeStates[trackerId]
    local entry = state and state.entry
    if not entry then
        add("no pool entry (not claimed)")
        return lines
    end
    add("")
    add("--- entry ---")
    local results = Engine._results or {}
    add("build=%s wired=%s container=%s host=%sx%s grouped=%s",
        tostring(results["build.t" .. trackerId]), tostring(entry.wired),
        tostring(entry.container ~= nil), tostring(entry.hostW), tostring(entry.hostH),
        tostring(entry.grouped))
    local cr = entry.classResource
    if not cr then
        add("no visual built")
        return lines
    end
    add("root shown=%s live=%s events=%s eventCount=%d pips=%d (%s) lastMax=%s",
        tostring(cr.root:IsShown()), tostring(live[trackerId] ~= nil), tostring(registered),
        cr.eventCount, cr.count, tostring(cr.countSource), tostring(res and cr.lastMax[res.token]))
    add("last paint: feed=%s runes=%s essence=%s essencePip=%s runeOrder=%s",
        tostring(cr.last.feed), tostring(cr.last.runes), tostring(cr.last.essence),
        tostring(cr.essencePip), tostring(cr.runeOrder))
    for i = 1, cr.count do
        add("pip %d: %s", i, tostring(cr.last[i]))
    end
    return lines
end
