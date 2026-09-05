-- unitframesz/setters.lua - Unit Frames Z: the per-instance setters
--
-- Split out of engine.lua. Each setter writes cfg and re-runs the engine
-- workers it invalidates. The workers are captured below from the UFZ._
-- internals engine.lua promotes, so this file loads after it. The table at
-- the bottom registers every setter into UFZ._API, which UFZ.GetAPI(unitKey)
-- publishes per config with the boss fan-out. Registration is at file scope
-- on purpose: GetAPI caches its bound table on the first call.

local addonName, addon = ...
local UFZ = addon.UnitFramesZ

local ensureApplied = UFZ._EnsureApplied
local applyFonts = UFZ._ApplyFonts
local applyStretch = UFZ._ApplyStretch
local applyPowerLayout = UFZ._ApplyPowerLayout
local anchorAbsorbFS = UFZ._AnchorAbsorbFS
local applyEnvelope = UFZ._ApplyEnvelope
local applyLayout = UFZ._ApplyLayout
local updatePower = UFZ._UpdatePower
local applyPowerColor = UFZ._ApplyPowerColor
local updateAbsorb = UFZ._UpdateAbsorb
local updateLevel = UFZ._UpdateLevel
local updateClassification = UFZ._UpdateClassification
local refreshName = UFZ._RefreshName
local update = UFZ._Update
local applyScale = UFZ._ApplyScale
local applyOpacity = UFZ._ApplyOpacity

--------------------------------------------------------------------------------
-- Commands (instance-bound implementations; the table at the bottom of this
-- file registers them into UFZ._API, which UFZ.GetAPI(unitKey) publishes)
--------------------------------------------------------------------------------

-- Read-only snapshot of the current config, for the settings pages. cfg holds
-- plain values only, so nothing secret can leak through this.
local function getConfig(inst)
    local snapshot = {}
    for k, v in pairs(inst.cfg) do snapshot[k] = v end
    return snapshot
end

-- setUnit is gone. The unit token is structural now -- minted from
-- the frame row into inst.unit -- so there is nothing for a setter to write:
-- five boss frames read one config table and each needs its own token. It was
-- a harness relic with no caller outside the API table.

-- The applied-vs-requested check exists because both failure modes here are
-- silent: an unknown key makes ResolveFontFace fall back to the default face,
-- and SetFont on a file the client has not loaded fails inside a pcall. Either
-- way the harness would print success while rendering Friz Quadrata.
--
-- The read-back is deferred and then re-checked a frame later: GetFont reports
-- the OLD face for about a frame after SetFont touches a fresh file (the same
-- settling the nametext caseprobe hit), so a same-frame check fired a false
-- warning naming the previous font on every first switch to a new face.
local function verifyAppliedFace(inst, fs, wantedFn)
    fs = fs or inst.pctFS
    wantedFn = wantedFn or function() return addon.ResolveFontFace(inst.cfg.face) end
    local wanted = wantedFn()
    if type(wanted) ~= "string" then return end
    local function check(finalCheck)
        -- Stale guard: the player may have switched faces while this waited.
        if wantedFn() ~= wanted then return end
        local ok, applied = pcall(fs.GetFont, fs)
        if not ok or type(applied) ~= "string" then return end
        if issecretvalue and issecretvalue(applied) then return end
        local a = applied:lower():gsub("/", "\\")
        local r = wanted:lower():gsub("/", "\\")
        if a == r then return end
        if not finalCheck then
            C_Timer.After(0, function() check(true) end)
            return
        end
        addon:Print("Warning: the client did not load '" .. wanted .. "' (rendering '" .. applied .. "' instead). A brand-new font file requires a FULL client restart, not /reload.")
    end
    C_Timer.After(0, function() check(false) end)
end

local function setFont(inst, face)
    ensureApplied(inst)
    local cfg = inst.cfg
    if face and face ~= "" then cfg.face = face end
    local isPath = type(cfg.face) == "string" and cfg.face:find("[/\\]") ~= nil
    local isLSM = addon.IsLSMKey and addon.IsLSMKey(cfg.face)
    if not isPath and not isLSM and not addon.Fonts[cfg.face] then
        addon:Print("Warning: '" .. cfg.face .. "' is not in this session's font registry, so the resolver falls back to the default face. Registry changes need /reload; new font files need a full client restart.")
    end
    applyFonts(inst)
    applyLayout(inst)
    update(inst)
    refreshName(inst)
    verifyAppliedFace(inst)
end

-- One impl for all four style keys: an outline flag changes glyph metrics, so
-- the full worker list runs -- setFont's, minus the face verification.
local function setStyleImpl(inst, key, style)
    ensureApplied(inst)
    if style and style ~= "" then inst.cfg[key] = style end
    applyFonts(inst)
    applyLayout(inst)
    update(inst)
    refreshName(inst)
end

local function setPctSize(inst, n)
    ensureApplied(inst)
    local cfg = inst.cfg
    cfg.pctSize = math.max(1, math.floor(tonumber(n) or cfg.pctSize))
    applyFonts(inst)
    applyLayout(inst)
    update(inst)
    addon:Print("Percent size: " .. cfg.pctSize)
    if cfg.digits then
        addon:Print("Note: digit mode is on, so the rendered size comes from digitsize 1/2/3; pct sets row geometry and the digits-off fallback.")
    end
end

local function setValSize(inst, n)
    ensureApplied(inst)
    -- Half-point steps: whole-point jumps are too coarse near the width match.
    local v = tonumber(n) or inst.cfg.valSize
    inst.cfg.valSize = math.max(1, math.floor(v * 2 + 0.5) / 2)
    applyFonts(inst)
    applyLayout(inst)
    update(inst)
end

-- The resolved value face for read-back verification and the report.
local function resolveValFace(inst)
    return addon.ResolveFontFace(inst.cfg.valFace ~= "follow" and inst.cfg.valFace or inst.cfg.face)
end

local function setValFont(inst, face)
    ensureApplied(inst)
    local cfg = inst.cfg
    if not face or face == "" then
        addon:Print("UFZ setter usage: valfont <FACE|follow>   (current: " .. cfg.valFace .. ")")
        return
    end
    local lowered = tostring(face):lower()
    if lowered == "follow" or lowered == "off" or lowered == "reset" then
        cfg.valFace = "follow"
    else
        cfg.valFace = face
        local isPath = cfg.valFace:find("[/\\]") ~= nil
        local isLSM = addon.IsLSMKey and addon.IsLSMKey(cfg.valFace)
        if not isPath and not isLSM and not addon.Fonts[cfg.valFace] then
            addon:Print("Warning: '" .. cfg.valFace .. "' is not in this session's font registry, so the resolver falls back to the default face. Registry changes need /reload; new font files need a full client restart.")
        end
    end
    applyFonts(inst)
    verifyAppliedFace(inst, inst.valFS, function() return resolveValFace(inst) end)
    addon:Print("Value face: " .. cfg.valFace)
end

local function setDescent(inst, n)
    ensureApplied(inst)
    local r = tonumber(n)
    if not r then
        addon:Print(string.format("UFZ setter usage: descent <ratio>   (current: %.3f; per-point ink lift for off-master digit sizes -- the font's below-ink descent share)", inst.cfg.descent))
        return
    end
    inst.cfg.descent = math.max(0, math.min(1, r))
    applyLayout(inst)
    addon:Print(string.format("Descent ratio: %.3f -- the 2-digit master look is the anchor; nudge until the '100' gap matches it.", inst.cfg.descent))
end

local function setGap(inst, n)
    ensureApplied(inst)
    -- Fractional gaps are legal: under a fractional UI scale a 0.1 px anchor
    -- offset can land on a different physical pixel, so sub-px steps are the
    -- fine-tuning knob (snapped to 0.1 to keep the report readable).
    local v = tonumber(n) or inst.cfg.gap
    inst.cfg.gap = math.floor(v * 10 + 0.5) / 10
    applyLayout(inst)
    update(inst)
end

local function setCenter(inst, state)
    ensureApplied(inst)
    local cfg = inst.cfg
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("UFZ setter usage: center <on|off>")
        return
    end
    cfg.center = (state == "on")
    applyLayout(inst)
    update(inst)
    if cfg.center then
        addon:Print("Center: on (centerline " .. cfg.centerOffset .. "px in from the " .. cfg.align .. " edge; tune with centeroffset)")
    else
        addon:Print("Center: off (edge-justified)")
    end
end

local function setCenterOffset(inst, n)
    ensureApplied(inst)
    inst.cfg.centerOffset = math.floor(tonumber(n) or inst.cfg.centerOffset)
    applyLayout(inst)
    addon:Print("Center offset: " .. inst.cfg.centerOffset)
end

local function setDigits(inst, state)
    ensureApplied(inst)
    local cfg = inst.cfg
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("UFZ setter usage: digits <on|off>")
        return
    end
    cfg.digits = (state == "on")
    inst.lastDigitCount = nil
    applyFonts(inst)
    applyLayout(inst)
    update(inst)
    if cfg.digits then
        addon:Print(string.format("Digit mode: on (sizes %d/%d/%d for 1/2/3 digits; validate with digitprobe)",
            cfg.digitSize1, cfg.digitSize2, cfg.digitSize3))
    else
        addon:Print("Digit mode: off (static size " .. cfg.pctSize .. ")")
    end
end

local function setDigitSize(inst, which, size)
    ensureApplied(inst)
    local cfg = inst.cfg
    local n = tonumber(which)
    if n ~= 1 and n ~= 2 and n ~= 3 then
        addon:Print("UFZ setter usage: digitsize <1|2|3> <size>")
        return
    end
    local key = "digitSize" .. n
    cfg[key] = math.max(1, math.floor(tonumber(size) or cfg[key]))
    -- applyFonts so a change to the currently rendered count lands now; applyLayout
    -- because the row reserve tracks the largest digit size.
    applyFonts(inst)
    applyLayout(inst)
    addon:Print(string.format("Digit size %d: %d", n, cfg[key]))
end

-- One knob for the digit-size triple (the shipped "% Font Size"): the 2-digit
-- size is the master and the 1/3-digit sizes ride the tuned 38/32 and 26/32
-- ratios. Also feeds pctSize (the digits-off fallback and applyLayout's
-- row-geometry basis).
local function setPctSizeMaster(inst, n)
    ensureApplied(inst)
    local cfg = inst.cfg
    local v = math.max(1, math.floor(tonumber(n) or cfg.digitSize2))
    cfg.digitSize2 = v
    cfg.digitSize1 = math.floor(v * 38 / 32 + 0.5)
    cfg.digitSize3 = math.floor(v * 26 / 32 + 0.5)
    cfg.pctSize = v
    applyFonts(inst)
    applyLayout(inst)
    update(inst)
end

local function setNameSize(inst, n)
    ensureApplied(inst)
    inst.cfg.nameSize = math.max(1, math.floor(tonumber(n) or inst.cfg.nameSize))
    -- No applyLayout: the name's anchor sits on the row-gap midline, which is
    -- name-size-independent by design. refreshName refits (nameSize is the fit
    -- ceiling), so the change lands through the fit when it is on. The envelope
    -- DOES track the ceiling (reserved wrap-box height), hence the refresh.
    applyFonts(inst)
    applyEnvelope(inst)
    refreshName(inst)
end

local function setNameFont(inst, face)
    ensureApplied(inst)
    local cfg = inst.cfg
    if not face or face == "" then
        addon:Print("UFZ setter usage: namefont <FACE|follow>   (current: " .. cfg.nameFace .. ")")
        return
    end
    local lowered = tostring(face):lower()
    if lowered == "follow" or lowered == "off" or lowered == "reset" then
        cfg.nameFace = "follow"
    else
        cfg.nameFace = face
        local isPath = cfg.nameFace:find("[/\\]") ~= nil
        local isLSM = addon.IsLSMKey and addon.IsLSMKey(cfg.nameFace)
        if not isPath and not isLSM and not addon.Fonts[cfg.nameFace] then
            addon:Print("Warning: '" .. cfg.nameFace .. "' is not in this session's font registry, so the resolver falls back to the default face. Registry changes need /reload; new font files need a full client restart.")
        end
    end
    applyFonts(inst)
    refreshName(inst)
end

local function setNameOffset(inst, n)
    ensureApplied(inst)
    inst.cfg.nameOffset = math.floor(tonumber(n) or inst.cfg.nameOffset)
    applyLayout(inst)
end

local function setNameY(inst, n)
    ensureApplied(inst)
    inst.cfg.nameY = math.floor(tonumber(n) or inst.cfg.nameY)
    applyLayout(inst)
end

local function setNameColorMode(inst, mode)
    ensureApplied(inst)
    mode = tostring(mode or ""):lower()
    if mode ~= "gradient" and mode ~= "custom" then
        addon:Print("Name color mode must be one of: gradient | custom")
        return
    end
    inst.cfg.nameColorMode = mode
    refreshName(inst)
end

local function setNameColor(inst, r, g, b, a)
    ensureApplied(inst)
    local cfg = inst.cfg
    cfg.nameColorR = tonumber(r) or 1
    cfg.nameColorG = tonumber(g) or 1
    cfg.nameColorB = tonumber(b) or 1
    cfg.nameColorA = tonumber(a) or 1
    refreshName(inst)
end

local function setNameMaxWidth(inst, n)
    ensureApplied(inst)
    local v = tonumber(n)
    if not v then
        addon:Print(string.format("UFZ setter usage: namemaxwidth <px>   (current: %d)", inst.cfg.nameMaxWidth))
        return
    end
    inst.cfg.nameMaxWidth = math.max(40, math.min(600, math.floor(v)))
    -- The display FS carries the same box the fit measures against.
    applyLayout(inst)
    refreshName(inst)
end

local function setNameMaxLines(inst, n)
    ensureApplied(inst)
    local v = tonumber(n)
    if not v then
        addon:Print(string.format("UFZ setter usage: namemaxlines <n>   (current: %d)", inst.cfg.nameMaxLines))
        return
    end
    inst.cfg.nameMaxLines = math.max(1, math.min(4, math.floor(v)))
    applyLayout(inst)
    refreshName(inst)
end

local function setNameFit(inst, state)
    ensureApplied(inst)
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("UFZ setter usage: namefit <on|off>")
        return
    end
    inst.cfg.nameFit = (state == "on")
    refreshName(inst)
end

local function setNameMinSize(inst, n)
    ensureApplied(inst)
    local v = tonumber(n)
    if not v then
        addon:Print(string.format("UFZ setter usage: nameminsize <n>   (current: %d)", inst.cfg.nameMinSize))
        return
    end
    -- The fit swaps a floor above the ceiling internally, so any value is safe;
    -- clamp to something readable anyway.
    inst.cfg.nameMinSize = math.max(4, math.floor(v))
    refreshName(inst)
end

local function setStretch(inst, n)
    ensureApplied(inst)
    local fx = tonumber(n)
    if not fx then
        addon:Print("UFZ setter usage: stretch <factor>   (1 = off; e.g. 1.35)")
        return
    end
    inst.cfg.stretch = math.max(0.5, math.min(3, fx))
    applyStretch(inst)
    addon:Print(string.format("Stretch: %.2fx wide%s", inst.cfg.stretch, inst.cfg.stretch == 1 and " (off)" or ""))
end

local function setScale(inst, n)
    ensureApplied(inst)
    local s = tonumber(n)
    if not s then
        addon:Print(string.format("UFZ setter usage: scale <0.5-2.0>   (current: %.2f)", inst.cfg.scale))
        return
    end
    inst.cfg.scale = math.max(0.5, math.min(2, s))
    applyScale(inst)
end

local function setOpacityImpl(inst, key, v)
    ensureApplied(inst)
    local pct = tonumber(v)
    if not pct then return end
    inst.cfg[key] = math.max(0, math.min(100, pct))
    applyOpacity(inst)
end

local function setSymbol(inst, state, size)
    ensureApplied(inst)
    local cfg = inst.cfg
    state = tostring(state or ""):lower()
    if state == "on" then
        cfg.symbol = true
    elseif state == "off" then
        cfg.symbol = false
    else
        addon:Print("UFZ setter usage: symbol <on|off> [size|auto]   (auto = a fifth of the percent size, tracks digit mode)")
        return
    end
    if size then
        if tostring(size):lower() == "auto" then
            cfg.symbolSize = 0
        else
            local n = tonumber(size)
            if n then cfg.symbolSize = math.max(1, math.floor(n)) end
        end
    end
    applyFonts(inst)
    applyLayout(inst)
    update(inst)
    -- The experimental secret-width anchor only exists in the NON-centered left
    -- branch; centered mode anchors the '%' identically for both aligns, and the
    -- target instance defaults to centered-left -- no warning noise there.
    if cfg.symbol and cfg.align == "left" and not cfg.center then
        addon:Print("Left mode with symbol on anchors '%' to a secret-width edge (the experiment). Check 'report'.")
    end
end

-- Same 0.1-snapping contract as setGap: sub-px offsets land on different
-- physical pixels under a fractional UI scale. Negative pulls the '%' into the
-- digits' side bearing (the glyph rects carry whitespace, so ink-tight needs
-- overlap).
local function setSymbolGap(inst, n)
    ensureApplied(inst)
    local v = tonumber(n)
    if not v then
        addon:Print(string.format("UFZ setter usage: symbolgap <px>   (current: %.1f; negative tightens)", inst.cfg.symbolGap))
        return
    end
    inst.cfg.symbolGap = math.floor(v * 10 + 0.5) / 10
    applyLayout(inst)
    update(inst)
end

local function setAlign(inst, a)
    ensureApplied(inst)
    local cfg = inst.cfg
    a = tostring(a or ""):lower()
    if a ~= "right" and a ~= "left" then
        addon:Print("Align must be one of: right | left")
        return
    end
    cfg.align = a
    applyLayout(inst)
    update(inst)
    if cfg.symbol and cfg.align == "left" and not cfg.center then
        addon:Print("Left mode with symbol on anchors '%' to a secret-width edge (the experiment). Check 'report'.")
    end
    addon:Print("Align: " .. cfg.align)
end

local function setColor(inst, m)
    ensureApplied(inst)
    m = tostring(m or ""):lower()
    if m ~= "curve" and m ~= "dark" and m ~= "white" then
        addon:Print("Color must be one of: curve | dark | white")
        return
    end
    inst.cfg.color = m
    update(inst)
    addon:Print("Color: " .. inst.cfg.color)
end

local function setRound(inst, m)
    ensureApplied(inst)
    m = tostring(m or ""):lower()
    if m ~= "floor" and m ~= "round" then
        addon:Print("Round must be one of: floor | round")
        return
    end
    inst.cfg.round = m
    update(inst)
    addon:Print("Percent rounding: " .. inst.cfg.round)
end

--------------------------------------------------------------------------------
-- Power text setters: one implementation per knob, keyed by which power
-- ("power" | "altPower") composes the cfg keys. Published through the API table
-- as SetPower*/SetAltPower* closures.
--------------------------------------------------------------------------------

local POWER_LOCS = {
    bottomleft = true, bottomright = true, topleft = true, topright = true, nameside = true,
}

local function powerWord(which)
    if which == "altPower" then return "altpower" end
    if which == "level" then return "level" end
    return "power"
end

local function setPowerShowImpl(inst, which, state)
    ensureApplied(inst)
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("UFZ setter usage: " .. powerWord(which) .. " <on|off>")
        return
    end
    inst.cfg[which .. "Show"] = (state == "on")
    applyEnvelope(inst)  -- a hidden satellite stops reserving envelope space
    update(inst)
end

-- One shared toggle, not per-power: it governs the '%' companion on every
-- power text that renders as a percent (mana, primary or alternate).
local function setPowerSymbolImpl(inst, state)
    ensureApplied(inst)
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("UFZ setter usage: powersymbol <on|off>")
        return
    end
    inst.cfg.powerSymbol = (state == "on")
    updatePower(inst)       -- sets/clears the sign's text
    applyPowerLayout(inst)  -- the right-edge sign reserve changed
end

local function setPowerLocImpl(inst, which, loc)
    ensureApplied(inst)
    loc = tostring(loc or ""):lower()
    if not POWER_LOCS[loc] then
        addon:Print("Location must be one of: bottomleft | bottomright | topleft | topright | nameside")
        return
    end
    inst.cfg[which .. "Loc"] = loc
    applyEnvelope(inst)
    applyPowerLayout(inst)
end

local function setPowerSizeImpl(inst, which, n)
    ensureApplied(inst)
    -- Half-point steps, the setValSize contract.
    local key = which .. "Size"
    local v = tonumber(n) or inst.cfg[key]
    inst.cfg[key] = math.max(1, math.floor(v * 2 + 0.5) / 2)
    applyFonts(inst)
    applyEnvelope(inst)
    applyPowerLayout(inst)  -- the '%' sign's right-edge reserve tracks the size
end

-- nil leaves an axis unchanged -- the dual-slider shape (each sub-slider sets
-- one axis). 0.1 snap, the setGap contract.
local function setPowerOffsetImpl(inst, which, x, y)
    ensureApplied(inst)
    local kx, ky = which .. "X", which .. "Y"
    local vx, vy = tonumber(x), tonumber(y)
    if not vx and not vy then
        addon:Print(string.format("UFZ %soffset usage: <x> [y]   (current: %.1f, %.1f)",
            powerWord(which), inst.cfg[kx], inst.cfg[ky]))
        return
    end
    if vx then inst.cfg[kx] = math.floor(vx * 10 + 0.5) / 10 end
    if vy then inst.cfg[ky] = math.floor(vy * 10 + 0.5) / 10 end
    applyEnvelope(inst)
    applyPowerLayout(inst)
end

local function setPowerColorModeImpl(inst, which, mode)
    ensureApplied(inst)
    mode = tostring(mode or ""):lower()
    if mode ~= "power" and mode ~= "custom" then
        addon:Print("Power color mode must be one of: power | custom")
        return
    end
    inst.cfg[which .. "ColorMode"] = mode
    applyPowerColor(inst)
end

local function setPowerColorImpl(inst, which, r, g, b, a)
    ensureApplied(inst)
    local cfg = inst.cfg
    cfg[which .. "ColorR"] = tonumber(r) or 1
    cfg[which .. "ColorG"] = tonumber(g) or 1
    cfg[which .. "ColorB"] = tonumber(b) or 1
    cfg[which .. "ColorA"] = tonumber(a) or 1
    applyPowerColor(inst)
end

local function setAbsorbShow(inst, state)
    ensureApplied(inst)
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("UFZ setter usage: absorb <on|off>")
        return
    end
    inst.cfg.absorbShow = (state == "on")
    updateAbsorb(inst)
end

-- nil leaves an axis unchanged -- the dual-slider shape. 0.1 snap, the setGap
-- contract. Re-anchors alone: an offset nudge needs none of applyLayout's
-- stretch churn.
local function setAbsorbOffset(inst, x, y)
    ensureApplied(inst)
    local cfg = inst.cfg
    local vx, vy = tonumber(x), tonumber(y)
    if not vx and not vy then
        addon:Print(string.format("UFZ setter usage: absorboffset <x> [y]   (current: %.1f, %.1f)",
            cfg.absorbX, cfg.absorbY))
        return
    end
    if vx then cfg.absorbX = math.floor(vx * 10 + 0.5) / 10 end
    if vy then cfg.absorbY = math.floor(vy * 10 + 0.5) / 10 end
    anchorAbsorbFS(inst)
end

-- The level text's ONE toggle: no regular on/off exists.
local function setLevelHideMax(inst, state)
    ensureApplied(inst)
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("UFZ setter usage: levelhidemax <on|off>")
        return
    end
    inst.cfg.levelHideMax = (state == "on")
    updateLevel(inst)
end

--------------------------------------------------------------------------------
-- Adornment setters: the dead skull and the classification icon
--------------------------------------------------------------------------------

local function setDeadIconScale(inst, pct)
    ensureApplied(inst)
    local v = tonumber(pct)
    if not v then
        addon:Print(string.format("UFZ setter usage: deadiconscale <50-200>   (current: %d)",
            inst.cfg.deadIconScale))
        return
    end
    inst.cfg.deadIconScale = math.max(50, math.min(200, math.floor(v + 0.5)))
    applyLayout(inst)
end

local function setClassifyShow(inst, state)
    ensureApplied(inst)
    state = tostring(state or ""):lower()
    if state ~= "on" and state ~= "off" then
        addon:Print("UFZ setter usage: classify <on|off>")
        return
    end
    inst.cfg.classifyShow = (state == "on")
    -- This one DOES move the envelope: the icon is a satellite, and its
    -- reservation appears and disappears with the toggle.
    applyEnvelope(inst)
    applyPowerLayout(inst)
    updateClassification(inst)
end

local function setClassifyLoc(inst, loc)
    ensureApplied(inst)
    loc = tostring(loc or ""):lower()
    if not POWER_LOCS[loc] then
        addon:Print("Location must be one of: bottomleft | bottomright | topleft | topright | nameside")
        return
    end
    inst.cfg.classifyLoc = loc
    applyEnvelope(inst)
    applyPowerLayout(inst)
end

local function setClassifySize(inst, px)
    ensureApplied(inst)
    local v = tonumber(px)
    if not v then
        addon:Print(string.format("UFZ setter usage: classifysize <8-48>   (current: %d)",
            inst.cfg.classifySize))
        return
    end
    inst.cfg.classifySize = math.max(8, math.min(48, math.floor(v + 0.5)))
    applyEnvelope(inst)
    applyPowerLayout(inst)
end

--------------------------------------------------------------------------------
-- Stack setters (Boss only)
--------------------------------------------------------------------------------
-- The keys exist only on a config whose defaults declare them (core.lua), so
-- these are no-ops on Player and Target rather than a way to grow them a
-- stack. _ApplyStack owns the combat guard.

local function setStackSpacing(inst, px)
    ensureApplied(inst)
    if inst.cfg.stackSpacing == nil then return end
    local v = tonumber(px)
    if not v then
        addon:Print(string.format("UFZ setter usage: stackspacing <-20-40>   (current: %d)",
            inst.cfg.stackSpacing))
        return
    end
    inst.cfg.stackSpacing = math.max(-20, math.min(40, math.floor(v + 0.5)))
    UFZ._ApplyStack(inst.unitKey)
end

local function setStackGrowth(inst, dir)
    ensureApplied(inst)
    if inst.cfg.stackGrowth == nil then return end
    dir = tostring(dir or ""):lower()
    if dir ~= "down" and dir ~= "up" then
        addon:Print("Stack growth must be one of: down | up")
        return
    end
    inst.cfg.stackGrowth = dir
    UFZ._ApplyStack(inst.unitKey)
end

Mixin(UFZ._API, {
    GetConfig = getConfig,
    SetFont = setFont,
    SetStyle = function(inst, s) return setStyleImpl(inst, "style", s) end,
    SetNameStyle = function(inst, s) return setStyleImpl(inst, "nameStyle", s) end,
    SetPowerStyle = function(inst, s) return setStyleImpl(inst, "powerStyle", s) end,
    SetLevelStyle = function(inst, s) return setStyleImpl(inst, "levelStyle", s) end,
    SetPctSize = setPctSize,
    SetValSize = setValSize,
    SetValFont = setValFont,
    SetDescent = setDescent,
    SetGap = setGap,
    SetCenter = setCenter,
    SetCenterOffset = setCenterOffset,
    SetDigits = setDigits,
    SetDigitSize = setDigitSize,
    SetPctSizeMaster = setPctSizeMaster,
    SetNameSize = setNameSize,
    SetNameFont = setNameFont,
    SetNameOffset = setNameOffset,
    SetNameY = setNameY,
    SetNameColorMode = setNameColorMode,
    SetNameColor = setNameColor,
    SetNameMaxWidth = setNameMaxWidth,
    SetNameMaxLines = setNameMaxLines,
    SetNameFit = setNameFit,
    SetNameMinSize = setNameMinSize,
    SetStretch = setStretch,
    SetScale = setScale,
    SetOpacityOutOfCombat = function(inst, v) return setOpacityImpl(inst, "opacityOutOfCombat", v) end,
    SetOpacityInCombat = function(inst, v) return setOpacityImpl(inst, "opacityInCombat", v) end,
    SetOpacityWithTarget = function(inst, v) return setOpacityImpl(inst, "opacityWithTarget", v) end,
    SetSymbol = setSymbol,
    SetSymbolGap = setSymbolGap,
    SetAlign = setAlign,
    SetColor = setColor,
    SetRound = setRound,
    SetPowerSymbol = setPowerSymbolImpl,
    SetPowerShow = function(inst, s) return setPowerShowImpl(inst, "power", s) end,
    SetPowerLoc = function(inst, l) return setPowerLocImpl(inst, "power", l) end,
    SetPowerSize = function(inst, n) return setPowerSizeImpl(inst, "power", n) end,
    SetPowerOffset = function(inst, x, y) return setPowerOffsetImpl(inst, "power", x, y) end,
    SetPowerColorMode = function(inst, m) return setPowerColorModeImpl(inst, "power", m) end,
    SetPowerColor = function(inst, r, g, b, a) return setPowerColorImpl(inst, "power", r, g, b, a) end,
    SetAltPowerShow = function(inst, s) return setPowerShowImpl(inst, "altPower", s) end,
    SetAltPowerLoc = function(inst, l) return setPowerLocImpl(inst, "altPower", l) end,
    SetAltPowerSize = function(inst, n) return setPowerSizeImpl(inst, "altPower", n) end,
    SetAltPowerOffset = function(inst, x, y) return setPowerOffsetImpl(inst, "altPower", x, y) end,
    SetAltPowerColorMode = function(inst, m) return setPowerColorModeImpl(inst, "altPower", m) end,
    SetAltPowerColor = function(inst, r, g, b, a) return setPowerColorImpl(inst, "altPower", r, g, b, a) end,
    SetAbsorbShow = setAbsorbShow,
    SetAbsorbOffset = setAbsorbOffset,
    SetLevelHideMax = setLevelHideMax,
    SetLevelLoc = function(inst, l) return setPowerLocImpl(inst, "level", l) end,
    SetLevelSize = function(inst, n) return setPowerSizeImpl(inst, "level", n) end,
    SetLevelOffset = function(inst, x, y) return setPowerOffsetImpl(inst, "level", x, y) end,
    SetDeadIconScale = setDeadIconScale,
    SetClassifyShow = setClassifyShow,
    SetClassifyLoc = setClassifyLoc,
    SetClassifySize = setClassifySize,
    SetStackSpacing = setStackSpacing,
    SetStackGrowth = setStackGrowth,
})
