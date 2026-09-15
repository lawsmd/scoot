-- scootauras/classpower.lua - Class Power trackers: the player's display power
-- as a bar or as a number
--
-- The first kind that owns no AuraContainer. Every element is Scoot art on
-- entry.visual, fed by setters that accept secret arguments: SetMinMaxValues
-- and SetValue on a StatusBar, SetText with an AbbreviateNumbers string on a
-- FontString. Nothing is compared and no value is read back, so both shapes
-- render in every secrecy state, and the structural gate never applies:
-- creation, restyle, and shape flips are legal mid-combat.
--
--   visual (Scoot, W x H from SetHostSize)
--    +- root (Scoot)                                   level visual+3
--        +- element set (Engine.BuildElementSet): the bar and the duration
--           FontString carry the power; icon, name, stacks and the drain
--           cooldown stay hidden
--
-- The bar shape runs the shared bar chain (styling.lua, layout.lua) and takes
-- its fill from UnitPower and UnitPowerMax on the player's power events. The
-- number shape is the duration FontString alone, sized by a ruler measure of
-- a fixed sample string, never of the value, so no geometry depends on a
-- secret. The tracker follows the display power: a form or spec change
-- arrives as UNIT_DISPLAYPOWER and repaints the range and the color.
local addonName, addon = ...

local SAU = addon.ScootAuras
local Engine = SAU.Engine

local ClassPower = {}
SAU.ClassPower = ClassPower

local INTERP_SMOOTH = (Enum and Enum.StatusBarInterpolation
    and Enum.StatusBarInterpolation.ExponentialEaseOut) or 1
local INTERP_IMMEDIATE = (Enum and Enum.StatusBarInterpolation
    and Enum.StatusBarInterpolation.Immediate) or 0

-- The widest strings either mode shows at the styled font: a full percent
-- (plus the sign's advance, since the sign is its own string), and the
-- abbreviated values a mana pool reaches. The host takes the widest.
local PERCENT_SAMPLE = "100"
local SAMPLE_STRINGS = { PERCENT_SAMPLE, "888K", "8.8M" }

-- The percent sign: a second FontString a third the number's size, its
-- vertical center on the number's right edge. Size markup does not exist and
-- the number's secret text cannot be measured, but the engine sizes the
-- number's rect to its text, so an anchor to that rect follows the value
-- with nothing read back.
local SIGN_TEXT = "%"
local SIGN_SCALE = 1 / 3
local SIGN_MIN_SIZE = 6
local SIGN_GAP = 1

-- [trackerId] = entry, for the live trackers. The event frame registers while
-- this holds anything and unregisters when it empties.
local live = {}
local SyncEvents

--------------------------------------------------------------------------------
-- Name: the resource the tracker's specs run on
--------------------------------------------------------------------------------

-- The display power each spec runs on, by Blizzard spec ID, as the token
-- UnitPowerType returns. A Druid's or a Priest's specs disagree, so the name
-- is resolved per tracker from its naming spec (NameForSpecs). A spec this
-- table does not know falls back to its class where the class has one
-- resource.
local POWER_TOKEN_BY_SPEC = {
    [62] = "MANA", [63] = "MANA", [64] = "MANA",                          -- Mage
    [65] = "MANA", [66] = "MANA", [70] = "MANA",                          -- Paladin
    [71] = "RAGE", [72] = "RAGE", [73] = "RAGE",                          -- Warrior
    [102] = "LUNAR_POWER", [103] = "ENERGY", [104] = "RAGE", [105] = "MANA", -- Druid
    [250] = "RUNIC_POWER", [251] = "RUNIC_POWER", [252] = "RUNIC_POWER", -- Death Knight
    [253] = "FOCUS", [254] = "FOCUS", [255] = "FOCUS",                    -- Hunter
    [256] = "MANA", [257] = "MANA", [258] = "INSANITY",                   -- Priest
    [259] = "ENERGY", [260] = "ENERGY", [261] = "ENERGY",                 -- Rogue
    [262] = "MAELSTROM", [263] = "MANA", [264] = "MANA",                  -- Shaman
    [265] = "MANA", [266] = "MANA", [267] = "MANA",                       -- Warlock
    [268] = "ENERGY", [269] = "ENERGY", [270] = "MANA",                   -- Monk
    [577] = "FURY", [581] = "FURY",                                       -- Demon Hunter
    [1467] = "MANA", [1468] = "MANA", [1473] = "MANA",                    -- Evoker
}

local POWER_TOKEN_BY_CLASS = {
    DEATHKNIGHT = "RUNIC_POWER", DEMONHUNTER = "FURY", EVOKER = "MANA", HUNTER = "FOCUS",
    MAGE = "MANA", PALADIN = "MANA", ROGUE = "ENERGY", WARLOCK = "MANA", WARRIOR = "RAGE",
}

-- What the character sheet calls each power: Blizzard's own _G[powerToken]
-- (PaperDollFrame.lua), localized, with the English name behind it.
local POWER_LABELS = {
    MANA = "Mana", RAGE = "Rage", FOCUS = "Focus", ENERGY = "Energy",
    RUNIC_POWER = "Runic Power", LUNAR_POWER = "Astral Power", MAELSTROM = "Maelstrom",
    INSANITY = "Insanity", FURY = "Fury", PAIN = "Pain",
}

local function PowerLabel(token)
    local global = _G[token]
    if type(global) == "string" and global ~= "" then return global end
    return POWER_LABELS[token]
end

local function TokenForSpec(specID)
    if type(specID) ~= "number" then return nil end
    local token = POWER_TOKEN_BY_SPEC[specID]
    if token then return token end
    local class = SAU.ClassTokenForSpec(specID)
    return class and POWER_TOKEN_BY_CLASS[class] or nil
end

--- The tracker's auto name: the resource its naming spec runs on
-- (SAU.NamingSpec: the player's spec while listed, else the spec the tracker
-- was created in, else the first listed), so a Rogue's reads "Energy" and a
-- Shaman's created in Elemental reads "Maelstrom" on every other class. A
-- naming spec with no power falls to the first listed spec that has one;
-- "Class Power" when none does. Live, never stored: the Aura List, the
-- editor title and the Edit Mode label read it through SAU.DisplayName, so a
-- spec change or a widened spec list renames the tracker on its own.
function ClassPower.NameForSpecs(specs, homeSpec)
    local first
    for _, specID in ipairs(type(specs) == "table" and specs or {}) do
        first = TokenForSpec(specID)
        if first then break end
    end
    local token = TokenForSpec(SAU.NamingSpec(specs, homeSpec)) or first
    return token and PowerLabel(token) or "Class Power"
end

--------------------------------------------------------------------------------
-- Scoot-owned visual (per pool entry, session-permanent)
--------------------------------------------------------------------------------

local function EnsureVisual(entry)
    if entry.classPower then return entry.classPower end
    local visual = entry.visual

    -- Above the missing-state underlay (visual + 2), below a parked container
    -- (visual + 5) and the Edit Mode preview (visual + 10).
    local root = CreateFrame("Frame", nil, visual)
    root:SetAllPoints(visual)
    root:SetFrameLevel(visual:GetFrameLevel() + 3)
    root:Hide()

    local set = Engine.BuildElementSet(root)

    -- Text ruler on a hidden holder: the number's host is measured from a
    -- fixed sample, never from the live string.
    local holder = CreateFrame("Frame", nil, visual)
    holder:SetSize(1, 1)
    holder:SetPoint("CENTER", visual, "CENTER", 0, 0)
    holder:Hide()
    local ruler = holder:CreateFontString(nil, "OVERLAY")
    ruler:SetPoint("CENTER", holder, "CENTER", 0, 0)
    addon.ApplyFontStyle(ruler, addon.ResolveFontFace("FRIZQT__"), 12, "")
    ruler:SetWidth(0)
    ruler:SetWordWrap(false)
    -- The sign's own ruler, so neither measure re-fonts the other's string.
    local signRuler = holder:CreateFontString(nil, "OVERLAY")
    signRuler:SetPoint("CENTER", holder, "CENTER", 0, 0)
    addon.ApplyFontStyle(signRuler, addon.ResolveFontFace("FRIZQT__"), 12, "")
    signRuler:SetWidth(0)
    signRuler:SetWordWrap(false)

    -- Beside the number on the same text host. The anchor is set once: the
    -- layout pass re-anchors the number, never the sign.
    local numberFS
    for _, elem in ipairs(set.elements) do
        if elem.type == "text" and elem.def.source == "duration" then numberFS = elem.widget end
    end
    local sign = set.textFrame:CreateFontString(nil, "OVERLAY")
    sign:SetPoint("LEFT", numberFS, "RIGHT", SIGN_GAP, 0)
    sign:Hide()

    entry.classPower = {
        root = root,
        elements = set.elements,
        textFrame = set.textFrame,
        ruler = ruler,
        signRuler = signRuler,
        sign = sign,
        last = {},
    }
    return entry.classPower
end

local function FindElements(elements)
    local barElem, textElem
    for _, elem in ipairs(elements or {}) do
        if elem.type == "bar" then
            barElem = elem
        elseif elem.type == "text" and elem.def.source == "duration" then
            textElem = elem
        end
    end
    return barElem, textElem
end

-- The number's font, as the text styling pass resolves it.
local function NumberFont(db)
    return addon.ResolveFontFace(db and db.textFont), tonumber(db and db.textSize) or 24,
        (db and db.textStyle) or "OUTLINE"
end

--- Point size of the percent sign beside a number at `size`: a third of it,
-- floored where a smaller sign would not read. The editor preview sizes its
-- sign through this too.
function ClassPower.SignSize(size)
    return math.max(SIGN_MIN_SIZE, (tonumber(size) or 24) * SIGN_SCALE)
end

--- Width the percent sign adds beside the number (its string width plus the
-- gap), or 0 when the number shows the value. Plain, because the ruler holds
-- only the sign. The layout pass shifts the number by it.
function ClassPower.SignAdvance(entry, db)
    if not (entry and db and db.powerTextPercent == true) then return 0 end
    local cp = EnsureVisual(entry)
    local face, size, style = NumberFont(db)
    local ruler = cp.signRuler
    addon.ApplyFontStyle(ruler, face, ClassPower.SignSize(size), addon.FontStyles.MetricStyle(style))
    ruler:SetText(SIGN_TEXT)
    local ok, w = pcall(ruler.GetUnboundedStringWidth, ruler)
    if not ok or type(w) ~= "number" or issecretvalue(w) then return 0 end
    return w + SIGN_GAP
end

--- Natural width and height of the widest sample string in the number's
-- font. Called by the layout pass for the number shape; the result is plain
-- because the ruler never holds a secret.
function ClassPower.MeasureSample(entry, db)
    if not entry then return 0, nil end
    local cp = EnsureVisual(entry)
    local face, size, style = NumberFont(db)
    local signW = ClassPower.SignAdvance(entry, db)
    local ruler = cp.ruler
    -- MetricStyle: a Deep Shadow style must not build a companion copy on a
    -- hidden ruler. The metrics are the same either way.
    addon.ApplyFontStyle(ruler, face, size, addon.FontStyles.MetricStyle(style))
    local width, height = 0, nil
    for _, sample in ipairs(SAMPLE_STRINGS) do
        ruler:SetText(sample)
        local ok, w = pcall(ruler.GetUnboundedStringWidth, ruler)
        local ok2, h = pcall(ruler.GetStringHeight, ruler)
        if ok and type(w) == "number" and not issecretvalue(w) then
            if sample == PERCENT_SAMPLE then w = w + signW end
            if w > width then width = w end
        end
        if ok2 and type(h) == "number" and not issecretvalue(h) and (not height or h > height) then
            height = h
        end
    end
    if width == 0 and addon.MeasureTextWidth then
        width = (addon.MeasureTextWidth(PERCENT_SAMPLE, face, size, style) or 0) + signW
    end
    return width, height
end

--------------------------------------------------------------------------------
-- The reads: setters fed straight from the power API
--------------------------------------------------------------------------------

-- Engine breakpoints plus the sub-1K floor (core/abbrev.lua), built once.
local abbrevOpts, abbrevErr, abbrevTried

local function AbbrevOptions()
    if abbrevOpts or abbrevTried then return abbrevOpts end
    abbrevTried = true
    abbrevOpts, abbrevErr = addon.CreateAbbrevConfig(addon.GetDefaultAbbrevBreakpoints)
    return abbrevOpts
end

-- The 0-1 fraction UnitPowerPercent evaluates against the curve, mapped to
-- 0-100 so the string formatter sees a percent.
local pctCurve

local function PercentCurve()
    if pctCurve then return pctCurve end
    if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
    local ok, curve = pcall(C_CurveUtil.CreateCurve)
    if not ok or not curve then return nil end
    if curve.SetType and Enum and Enum.LuaCurveType then
        pcall(curve.SetType, curve, Enum.LuaCurveType.Linear)
    end
    pcall(curve.AddPoint, curve, 0, 0)
    pcall(curve.AddPoint, curve, 1, 100)
    pctCurve = curve
    return curve
end

-- The value chain: ClearText has already run. Returns the verdict string.
local function PaintValue(fs)
    local okV, value = pcall(UnitPower, "player")
    if not okV or type(value) ~= "number" then
        return okV and ("UnitPower returned " .. type(value))
            or ("UnitPower error: " .. tostring(value))
    end
    local opts = AbbrevOptions()
    local okA, str
    if opts then
        okA, str = pcall(AbbreviateNumbers, value, opts)
    else
        -- Engine-default breakpoints: sub-1K floats pass through raw.
        okA, str = pcall(AbbreviateNumbers, value)
    end
    if not okA or type(str) ~= "string" then
        return okA and ("AbbreviateNumbers returned " .. type(str))
            or ("AbbreviateNumbers error: " .. tostring(str))
    end
    if not pcall(fs.SetText, fs, str) then return "SetText failed" end
    return opts and "ok" or "ok (engine default breakpoints)"
end

-- The percent chain: the number alone, since the sign is its own smaller
-- string (StyleSign).
local function PaintPercent(fs)
    local curve = PercentCurve()
    if not (curve and UnitPowerPercent and C_StringUtil and C_StringUtil.FloorToNearestString) then
        return "percent API missing"
    end
    local okP, num = pcall(UnitPowerPercent, "player", nil, false, curve)
    if not okP or type(num) ~= "number" then
        return okP and ("UnitPowerPercent returned " .. type(num))
            or ("UnitPowerPercent error: " .. tostring(num))
    end
    local okF, str = pcall(C_StringUtil.FloorToNearestString, num)
    if not okF or type(str) ~= "string" then
        return okF and ("formatter returned " .. type(str))
            or ("formatter error: " .. tostring(str))
    end
    if not pcall(fs.SetText, fs, str) then return "SetText failed" end
    return "ok (percent)"
end

--- Feeds the live power into the bar and the number. Nothing here reads a
-- value back: the setters take secret arguments, and every verdict written
-- to cp.last describes the call, never the value. Runs on every power event,
-- so it stays a handful of setter calls.
function ClassPower.PaintValues(trackerId, tracker, cp, db)
    local barElem, textElem = FindElements(cp.elements)
    local last = cp.last

    if tracker.shape == "bar" and barElem then
        local fill = barElem.barFill
        local interp = (not db or db.barSmoothFill ~= false) and INTERP_SMOOTH or INTERP_IMMEDIATE
        local okM, pmax = pcall(UnitPowerMax, "player")
        local okV, pcur = pcall(UnitPower, "player")
        if okM and okV and type(pmax) == "number" and type(pcur) == "number" then
            local okR = pcall(fill.SetMinMaxValues, fill, 0, pmax, interp)
            local okS = pcall(fill.SetValue, fill, pcur, interp)
            last.bar = (okR and okS) and "ok" or "setter failed"
        else
            last.bar = "read failed: max=" .. type(pmax) .. " value=" .. type(pcur)
        end
    else
        last.bar = "no bar"
    end

    if not textElem then
        last.text = "no text"
        return
    end
    local vis = SAU.ResolveVisibility(tracker, db)
    if not vis.showText then
        last.text = "hidden"
        return
    end
    local fs = textElem.widget
    -- ClearText first, always: it is the one call that releases the Text
    -- aspect a secret string stamped on the last paint.
    if fs.ClearText then fs:ClearText() end
    if db and db.powerTextPercent == true then
        last.text = PaintPercent(fs)
    else
        last.text = PaintValue(fs)
    end
end

--------------------------------------------------------------------------------
-- Styling and layout (Tier 1: Scoot frames only)
--------------------------------------------------------------------------------

--- Paints one Scoot-owned element set as the tracker: the shared styling and
-- layout chain, then everything the kind never shows hidden. `shim` is the
-- chain's state table for that set ({ container, elements, entry }). The
-- values are painted separately (PaintValues): they move on every power
-- event, and the chain does not.
function ClassPower.PaintElementSet(trackerId, tracker, shim, elements)
    local db = SAU.GetDB(trackerId)
    local vis = SAU.ResolveVisibility(tracker, db)

    SAU._ApplyShapeStyling(trackerId, tracker, shim)
    SAU._ApplyBarStyling(trackerId, tracker, shim)
    SAU._ApplyTextStyling(trackerId, tracker, shim)
    SAU._LayoutElements(trackerId, tracker, shim)

    for _, elem in ipairs(elements or {}) do
        if elem.type == "texture" then
            elem.widget:Hide()
            if elem.borderFrame then elem.borderFrame:Hide() end
            if elem.silhouette then elem.silhouette:Hide() end
        elseif elem.type == "text" then
            if elem.def.source ~= "duration" then elem.widget:Hide() end
        elseif elem.type == "bar" then
            if not vis.showBar then elem.widget:Hide() end
        elseif elem.type == "cooldown" then
            pcall(elem.widget.Clear, elem.widget)
            elem.widget:Hide()
        end
    end
end

-- The percent sign: shown while the toggle is on and the number shows, in the
-- number's face, style and color at SignSize. Its text is a literal, so a
-- Deep Shadow copy mirrors it through the SetText hook.
local function StyleSign(tracker, cp, db)
    local sign = cp.sign
    if not (db and db.powerTextPercent == true and SAU.ResolveVisibility(tracker, db).showText) then
        sign:Hide()
        return
    end
    local face, size, style = NumberFont(db)
    addon.ApplyFontStyle(sign, face, ClassPower.SignSize(size), style)
    local r, g, b, a = SAU._ClassPowerTextColor(db)
    if r then sign:SetTextColor(r, g, b, a) end
    sign:SetText(SIGN_TEXT)
    sign:Show()
end

local function PaintLive(trackerId, tracker, entry, cp)
    local shim = { container = cp.root, elements = cp.elements, entry = entry }
    ClassPower.PaintElementSet(trackerId, tracker, shim, cp.elements)
    local db = SAU.GetDB(trackerId)
    StyleSign(tracker, cp, db)
    ClassPower.PaintValues(trackerId, tracker, cp, db)
end

--- Full Tier 1 pass for one live tracker: build the art on first use, paint
-- it, feed the values, and join the power event fan-out.
function ClassPower.Restyle(trackerId, tracker, state)
    local entry = state and state.entry
    if not entry then return end
    local cp = EnsureVisual(entry)
    PaintLive(trackerId, tracker, entry, cp)
    cp.root:Show()
    live[trackerId] = entry
    SyncEvents()
    Engine._SetResult("build.t" .. trackerId, "class power (no container)")
    -- Text metrics settle a frame after a font change; one deferred repaint
    -- picks up the settled sample width so the number's host is never left
    -- a frame stale. A bar's number moves by the sign's measured advance, so
    -- a bar showing the percent takes the same repaint.
    local db = SAU.GetDB(trackerId)
    local measures = tracker.shape ~= "bar" or (db and db.powerTextPercent == true)
    if measures and not cp.repaintPending then
        cp.repaintPending = true
        C_Timer.After(0, function()
            cp.repaintPending = false
            local current = SAU.GetTracker(trackerId)
            local st = SAU._activeStates[trackerId]
            if current and current.kind == "classpower" and st and st.entry == entry then
                PaintLive(trackerId, current, entry, cp)
            end
        end)
    end
end

--- Hides the art and drops the tracker from the event fan-out. Safe for any
-- tracker id and for an entry that never built one.
function ClassPower.Release(trackerId, entry)
    if trackerId then live[trackerId] = nil end
    if entry and entry.classPower then entry.classPower.root:Hide() end
    SyncEvents()
end

--- The one entry point from ApplyStyling, for every kind: a Class Power
-- tracker repaints, anything else on an entry that once hosted one hides it.
function ClassPower.Sync(trackerId, tracker, state)
    if tracker and tracker.kind == "classpower" then
        ClassPower.Restyle(trackerId, tracker, state)
    else
        ClassPower.Release(trackerId, state and state.entry)
    end
end

-- The art is not torn down: pool frames are session-permanent, and the next
-- occupant's Sync repaints it or leaves it hidden.
function ClassPower.OnEntryReleased(entry, trackerId)
    ClassPower.Release(trackerId or (entry and entry.occupantId), entry)
end

--------------------------------------------------------------------------------
-- Power events
--------------------------------------------------------------------------------

local eventFrame
local registered = false

local function OnPowerEvent(_, event)
    for trackerId, entry in pairs(live) do
        local tracker = SAU.GetTracker(trackerId)
        local state = SAU._activeStates[trackerId]
        local cp = entry.classPower
        if tracker and tracker.kind == "classpower" and state and state.entry == entry and cp then
            if event == "UNIT_DISPLAYPOWER" then
                -- A form or spec change swaps the display power: the range
                -- and the color both move, so this is a full repaint.
                PaintLive(trackerId, tracker, entry, cp)
            else
                ClassPower.PaintValues(trackerId, tracker, cp, SAU.GetDB(trackerId))
            end
        else
            live[trackerId] = nil
        end
    end
end

-- Kept off addon.Events: unit-filtered registration.
-- The frame exists for RegisterUnitEvent: UNIT_POWER_FREQUENT fires for every
-- unit on screen, and C-side filtering to the player is what keeps the
-- handler quiet. The bus carries no unit-event API.
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
    else
        eventFrame:UnregisterAllEvents()
    end
end

--------------------------------------------------------------------------------
-- Debug
--------------------------------------------------------------------------------

local SECRECY_NAMES = {}
if Enum and Enum.SecrecyLevel then
    for name, value in pairs(Enum.SecrecyLevel) do
        if type(value) == "number" then SECRECY_NAMES[value] = name end
    end
end

local POWER_NAMES = {}
if Enum and Enum.PowerType then
    for name, value in pairs(Enum.PowerType) do
        if type(value) == "number" then POWER_NAMES[value] = name end
    end
end

local function Describe(v)
    if issecretvalue and issecretvalue(v) then return "secret" end
    if type(v) == "table" then return "table" end
    return tostring(v)
end

-- Never index a name table with the raw return: a secret table key throws.
local function Named(names, value)
    if issecretvalue and issecretvalue(value) then return "secret" end
    return names[value] or tostring(value)
end

local function Plain(v)
    return type(v) == "number" and not (issecretvalue and issecretvalue(v))
end

--- Lines for /scoot debug sa power <id>: the display power and its secrecy,
-- what each read returns right now, the resolved colors, and the last paint.
function ClassPower.DebugInfo(trackerId)
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
    add("percent=%s smoothFill=%s fillMode=%s textColorMode=%s font=%s style=%s size=%s",
        tostring(db and db.powerTextPercent), tostring(db and db.barSmoothFill),
        tostring(db and db.barForegroundColorMode), tostring(db and db.textColorMode),
        tostring(db and db.textFont), tostring(db and db.textStyle), tostring(db and db.textSize))
    add("specs=%s homeSpec=%s namingSpec=%s specAllows=%s currentSpec=%s active=%s",
        SAU.DescribeSpecs(tracker.specs) or "all", tostring(tracker.homeSpec),
        tostring(SAU.NamingSpec(tracker.specs, tracker.homeSpec)), tostring(SAU.SpecAllows(tracker)),
        tostring(SAU.CurrentSpecID()), tostring(SAU.IsTrackerActive(trackerId, tracker)))
    add("InCombatLockdown=%s editMode=%s gateOpen=%s",
        tostring(InCombatLockdown()),
        tostring(SAU._isEditModeActive and SAU._isEditModeActive()),
        tostring(SAU.CombatGateOpen(tracker)))

    add("")
    add("--- display power ---")
    local okT, powerIndex, powerToken = pcall(UnitPowerType, "player")
    add("UnitPowerType=%s (%s)", okT and Named(POWER_NAMES, powerIndex) or "error",
        okT and Describe(powerToken) or "error")
    if okT and Plain(powerIndex) then
        local sok, level = pcall(function()
            return C_Secrets and C_Secrets.GetPowerTypeSecrecy and C_Secrets.GetPowerTypeSecrecy(powerIndex)
        end)
        add("GetPowerTypeSecrecy=%s", sok and Named(SECRECY_NAMES, level) or "error")
    end
    local okV, value = pcall(UnitPower, "player")
    local okM, pmax = pcall(UnitPowerMax, "player")
    add("UnitPower=%s UnitPowerMax=%s", okV and Describe(value) or ("error: " .. tostring(value)),
        okM and Describe(pmax) or ("error: " .. tostring(pmax)))
    local curve = PercentCurve()
    if curve and UnitPowerPercent then
        local okP, pct = pcall(UnitPowerPercent, "player", nil, false, curve)
        add("UnitPowerPercent(curve)=%s", okP and Describe(pct) or ("error: " .. tostring(pct)))
    else
        add("UnitPowerPercent: curve or API missing")
    end
    local fr, fg, fb = addon.ResolveColorRGBA("power", nil, { barKind = "power", unitForPower = "player" })
    local tr, tg, tb = addon.ResolveColorRGBA("classPower", nil,
        { classPowerMode = true, lightenMana = true, unitForPower = "player" })
    add("fill color=%.2f %.2f %.2f  text color=%.2f %.2f %.2f", fr, fg, fb, tr, tg, tb)
    add("abbrev=%s%s", abbrevOpts and "ok" or (abbrevTried and "failed" or "not built"),
        abbrevErr and (" (" .. tostring(abbrevErr) .. ")") or "")

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
    local cp = entry.classPower
    if not cp then
        add("no visual built")
        return lines
    end
    add("root shown=%s live=%s events=%s", tostring(cp.root:IsShown()),
        tostring(live[trackerId] ~= nil), tostring(registered))
    add("last paint: bar=%s text=%s", tostring(cp.last.bar), tostring(cp.last.text))
    add("sign shown=%s advance=%s", tostring(cp.sign:IsShown()),
        tostring(ClassPower.SignAdvance(entry, db)))
    return lines
end
