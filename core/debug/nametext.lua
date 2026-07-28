-- debug/nametext.lua - /scoot debug nametext
--
-- Feasibility harness for auto-fitting a target's name into a fixed-size box, and
-- for coloring it with a gradient.
--
-- Round 1 answered: does FontString *geometry* stay readable when the text itself is
-- a secret? Yes -- only a secret anchor chain breaks measurement, not secret text.
--
-- Round 2 asks: can a horizontal gradient restart on each wrapped line? For readable
-- names, yes -- CalculateScreenAreaFromCharacterSpan reports where the engine broke
-- the lines, so each one gets its own |cff ramp. For secret names (any NPC) no string
-- operation is legal at all, so per-character coloring is impossible; the slice mode
-- fakes it with clipped copies instead, which never reads the string.
--
-- Everything here is addon-owned and anchored to UIParent with plain numbers, which
-- keeps the anchor chain non-secret. That is load-bearing, not incidental.

local addonName, addon = ...

local cfg = {
    width    = 150,
    -- Tall enough for one line at maxSize. The fitter derives its line budget from
    -- height/lineHeight, so this also means extra lines unlock as the text shrinks.
    height   = 70,
    maxLines = 2,
    minSize  = 9,
    maxSize  = 52,
    -- What renders when the name cannot be measured -- i.e. every restricted unit.
    -- Deliberately NOT maxSize: at maxSize a bail is indistinguishable from a fit
    -- that decided the text already fitted, which is exactly how the last round of
    -- testing read as working when nothing had run.
    fallbackSize = 20,
    mode     = "font",
    face     = "FRIZQT__",
    style    = "OUTLINE",

    -- Gradient
    gradient    = "auto",   -- off | line | block | slice | auto
    slices      = 16,
    forcedClass = nil,      -- nil = read the target's class
    treatment   = "cast",   -- cast (darken start 25%, as CastBar X) | raw
    identity    = "player", -- player (class ramp only for real players) | class
}

-- NPC placeholder ramp: near-white into a light gray.
local NPC_START = { 1.00, 1.00, 1.00 }
local NPC_END   = { 0.62, 0.64, 0.68 }

-- Edge cases that are tedious to find in the world on demand.
local SAMPLES = {
    "Bob",
    "Grand Magistrix Elisande",
    "Hulking Bloodthirsty Blackrock Battlemaster",
    "High General Brashthorn of the Broken Shore Vanguard",
    "Supercalifragilisticexpialidociousaurus",
    "Verylongcharactername-Verylongrealmnamehere",
    -- Heavily accented: 25 bytes but 18 characters, so any index-based API that
    -- reports a length reveals which of the two it counts. Nothing else here
    -- separates them -- every other sample is pure ASCII.
    "Ëlïsändë Vörthälâk",
}

local frame, nameFS, boundsBox
local slicePool = {}

local lastResult, lastSource
local currentValue, currentIsSecret
local lastColors, lastLines, lastDiscovery, lastGradientMode, lastGradientNote
local lastRamped
local fitRetries, lastRetries = 0, 0
-- What applySlices actually replayed onto the copies, recorded rather than recomputed
-- so the report shows the values that were used, not the values that would be used now.
local lastSliceSize, lastSliceScale, lastSliceMaxLines, lastSliceFallback

--------------------------------------------------------------------------------
-- Safe formatting
--------------------------------------------------------------------------------

local function safeStr(v)
    if v == nil then return "nil" end
    if issecretvalue and issecretvalue(v) then return "<SECRET>" end
    local ok, s = pcall(tostring, v)
    return ok and s or "<error>"
end

-- Report a single measurement API as ok / SECRET / error. This per-API tagging is
-- the actual deliverable of the harness.
local function measureOn(obj, method)
    if not obj then return "<no fontstring>" end
    local fn = obj[method]
    if type(fn) ~= "function" then return "<API not present>" end
    local ok, v = pcall(fn, obj)
    if not ok then return "<error: " .. safeStr(v) .. ">" end
    if issecretvalue and issecretvalue(v) then return "SECRET" end
    if type(v) == "number" then return string.format("%.2f", v) end
    return safeStr(v)
end

local function measure(method)
    return measureOn(nameFS, method)
end

local function hex(r, g, b)
    return string.format("%02x%02x%02x",
        math.floor((r or 0) * 255 + 0.5),
        math.floor((g or 0) * 255 + 0.5),
        math.floor((b or 0) * 255 + 0.5))
end

--------------------------------------------------------------------------------
-- Colors
--------------------------------------------------------------------------------

-- Start color is the target's class color; end color is the curated per-class
-- endpoint. Same treatment CastBar X applies to spell names, so the cadence matches.
-- No class (every NPC, and any player whose class won't resolve) falls to the
-- white -> gray placeholder.
-- UnitIsPlayer carries no secret annotation at all -- SecretArguments only -- so it
-- is a plain boolean for any unit, and it is the only honest test for "is this a
-- player". A resolvable class token is NOT: Blizzard assigns internal classes to
-- NPCs, so most of a capital city reads back as WARRIOR / PALADIN / MAGE and would
-- otherwise pick up a class ramp it has no business wearing.
local function targetIsPlayer()
    local ok, v = pcall(UnitIsPlayer, "target")
    return ok and v == true
end

local function resolveColors()
    local token = cfg.forcedClass
    if not token and addon.GetClassTokenForUnit then
        if cfg.identity ~= "player" or targetIsPlayer() then
            token = addon.GetClassTokenForUnit("target")
        end
    end

    local cr, cg, cb
    if token and addon.GetClassColorRGB then
        cr, cg, cb = addon.GetClassColorRGB(token)
    end

    if not cr then
        return {
            token = nil,
            r1 = NPC_START[1], g1 = NPC_START[2], b1 = NPC_START[3],
            r2 = NPC_END[1],   g2 = NPC_END[2],   b2 = NPC_END[3],
        }
    end

    local r1, g1, b1 = cr, cg, cb
    if cfg.treatment == "cast" and addon.DarkenColor then
        r1, g1, b1 = addon.DarkenColor(cr, cg, cb, 0.25)
    end

    local ep = addon.CLASS_GRADIENT_ENDPOINTS and addon.CLASS_GRADIENT_ENDPOINTS[token]
    local r2, g2, b2
    if ep and addon.LightenColor then
        r2, g2, b2 = addon.LightenColor(ep[1], ep[2], ep[3], 0.10)
    elseif addon.LightenColor then
        r2, g2, b2 = addon.LightenColor(cr, cg, cb, 0.45)
    else
        r2, g2, b2 = cr, cg, cb
    end

    return { token = token, r1 = r1, g1 = g1, b1 = b1, r2 = r2, g2 = g2, b2 = b2 }
end

local function rampAt(c, t)
    return c.r1 + (c.r2 - c.r1) * t,
           c.g1 + (c.g2 - c.g1) * t,
           c.b1 + (c.b2 - c.b1) * t
end

--------------------------------------------------------------------------------
-- Slice stack (the only technique that works on a secret name)
--------------------------------------------------------------------------------
-- N column-shaped clip frames tiled across the box, each holding an identical copy
-- of the same FontString at a different solid color. Each copy shows only its own
-- column, so left-to-right the stack reads as a banded gradient. No string is ever
-- read, split or measured -- SetText is AllowedWhenTainted, so a secret pours in fine.
--
-- The ramp necessarily spans the box rather than each line: per-line ramps need each
-- line's own horizontal extent, and that comes only from
-- CalculateScreenAreaFromCharacterSpan, which is dead once the text is secret.

local function ensureSlice(index)
    local s = slicePool[index]
    if s then return s end

    local clip = CreateFrame("Frame", nil, frame)
    clip:SetClipsChildren(true)
    -- Frame level left to auto-inherit from the parent, as cast/textfill.lua does.

    -- Anchored to the container, not to the clip frame, so every copy lays out
    -- identically and the clip only decides which slice of it is visible. Same
    -- relationship as filledText -> clipFrame -> cast bar in cast/textfill.lua.
    local fs = clip:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    fs:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 12, "")

    s = { clip = clip, fs = fs }
    slicePool[index] = s
    return s
end

local function hideSlices()
    for _, s in ipairs(slicePool) do s.clip:Hide() end
end

local function applySlices(result, colors)
    local n = math.max(1, math.floor(cfg.slices))
    local face = addon.ResolveFontFace(cfg.face)

    -- Take the fit's own report and nothing else. The old form was
    --   size = result.size or cfg.maxSize
    --   maxLines = GetMaxLines(nameFS) or cfg.maxLines
    -- which papered over a fit that never ran: the copies rendered at cfg.maxSize
    -- with an unlimited line budget and looked like a deliberate layout. If the fit
    -- did not produce numbers, draw nothing and say why.
    local size     = result and result.size
    local scale    = (result and result.scale) or 1
    local maxLines = result and result.maxLines

    lastSliceSize, lastSliceScale, lastSliceMaxLines = size, scale, maxLines
    lastSliceFallback = result and result.fallback or false

    if not size or not maxLines then
        hideSlices()
        return false, "fit reported no size/maxLines"
    end

    for i = 1, n do
        local s = ensureSlice(i)

        -- Snap column edges to whole pixels. Fractional edges under a fractional UI
        -- scale leave visible seams between columns.
        local left  = math.floor(cfg.width * (i - 1) / n + 0.5)
        local right = math.floor(cfg.width * i / n + 0.5)

        s.clip:ClearAllPoints()
        s.clip:SetPoint("TOPLEFT", frame, "TOPLEFT", left, 0)
        s.clip:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", right, -cfg.height)

        -- Replay the fit the way it was applied, not the way it reads. "scale" and
        -- "blizzard" leave the font at maxSize and shrink via SetTextScale, so
        -- applying result.size AND result.scale would shrink twice.
        --
        -- A fallback bail is the exception: it applies the point size directly at
        -- scale 1 whatever the mode, so replaying it through the scale branch would
        -- put the copies at maxSize while the master sits at fallbackSize.
        if cfg.mode == "font" or lastSliceFallback then
            addon.ApplyFontStyle(s.fs, face, size, cfg.style)
            if s.fs.SetTextScale then pcall(s.fs.SetTextScale, s.fs, 1) end
        else
            addon.ApplyFontStyle(s.fs, face, cfg.maxSize, cfg.style)
            if s.fs.SetTextScale then pcall(s.fs.SetTextScale, s.fs, scale) end
        end
        if s.fs.SetSmoothScaling then pcall(s.fs.SetSmoothScaling, s.fs, cfg.mode ~= "font") end
        pcall(s.fs.SetWordWrap, s.fs, true)
        pcall(s.fs.SetNonSpaceWrap, s.fs, false)
        pcall(s.fs.SetMaxLines, s.fs, maxLines)

        -- Sample the ramp at the column's centre so the bands sit symmetrically.
        local t = (n == 1) and 0 or ((i - 0.5) / n)
        s.fs:SetTextColor(rampAt(colors, t))

        if s.fs.ClearText then pcall(s.fs.ClearText, s.fs) end
        pcall(s.fs.SetText, s.fs, currentValue)

        s.clip:Show()
    end

    for i = n + 1, #slicePool do slicePool[i].clip:Hide() end
    return true
end

--------------------------------------------------------------------------------
-- Fit + gradient
--------------------------------------------------------------------------------

-- True while nameFS holds the raw value rather than a |cff-coded gradient string.
local plainApplied = false

local function applyValue()
    if nameFS.ClearText then pcall(nameFS.ClearText, nameFS) end
    pcall(nameFS.SetText, nameFS, currentValue)
    plainApplied = true
end

local function setValue(value, isSecret, source)
    currentValue = value
    currentIsSecret = isSecret and true or false
    lastSource = source
    fitRetries = 0
    applyValue()
end

local function applySolid(colors, note)
    nameFS:SetTextColor(colors.r1, colors.g1, colors.b1, 1)
    lastGradientNote = note
end

local function applyGradient(result)
    local mode = cfg.gradient
    if mode == "auto" then mode = currentIsSecret and "slice" or "line" end
    lastGradientMode = mode
    lastGradientNote = nil
    lastLines = nil
    lastDiscovery = nil
    lastRamped = nil

    local colors = resolveColors()
    lastColors = colors

    hideSlices()
    nameFS:SetAlpha(1)

    if mode == "slice" then
        local drawn, why = applySlices(result, colors)
        if drawn then
            nameFS:SetAlpha(0)
        else
            -- Nothing was drawn. Keep the master visible: an empty box is
            -- indistinguishable from having no target, which is the failure mode
            -- this whole pass exists to stop.
            applySolid(colors, "slices not drawn - " .. tostring(why))
        end
        return
    end

    if mode == "off" then
        applySolid(colors, "solid (control)")
        return
    end

    -- line / block: per-character |cff codes, which means string operations.
    if currentIsSecret then
        applySolid(colors, "text is secret - no string ops possible")
        return
    end

    local lines = addon.DiscoverTextLines and addon.DiscoverTextLines(nameFS, currentValue)
    if lines then
        lastDiscovery = "span API"
    elseif addon.WrapTextGreedy then
        lines = addon.WrapTextGreedy(currentValue, {
            width = cfg.width,
            face  = addon.ResolveFontFace(cfg.face),
            size  = result and result.size or cfg.maxSize,
            style = cfg.style,
        })
        lastDiscovery = lines and "greedy fallback" or "none"
    end
    lastLines = lines

    if not lines then
        applySolid(colors, "line discovery failed")
        return
    end

    -- The fit already settled how many lines the plain text occupies. If discovery
    -- disagrees, its breaks are wrong, and applying them would render the name at a
    -- layout the fitter never approved -- one line ellipsized, most likely. Keep the
    -- fitted layout and drop the gradient instead.
    local fitLines = result and result.lines
    if type(fitLines) == "number" and fitLines >= 1 and #lines ~= fitLines then
        applySolid(colors, string.format(
            "discovery found %d line(s), fit produced %d", #lines, fitLines))
        return
    end

    local ramped = addon.BuildPerLineRampString and addon.BuildPerLineRampString(
        lines, colors.r1, colors.g1, colors.b1, colors.r2, colors.g2, colors.b2,
        { mode = (mode == "block") and "block" or "line" })

    if not ramped then
        applySolid(colors, "ramp build failed")
        return
    end
    lastRamped = ramped

    -- Inline |cff codes multiply against the text color, so it has to be white.
    nameFS:SetTextColor(1, 1, 1, 1)
    -- Word wrap stays ON. The explicit "\n" already forces our breaks, so wrap only
    -- ever adds one -- and that is the safety net: |cff hex values shift sub-pixel
    -- kerning by 1-2px (castbarX pitfall #28), so a line sitting on the boundary can
    -- come out fractionally wider than the plain text it was measured from. With wrap
    -- off that is a guaranteed "...", with wrap on it is a reflow at worst.
    pcall(nameFS.SetWordWrap, nameFS, true)
    pcall(nameFS.SetText, nameFS, ramped)
    plainApplied = false
end

-- A FontString that has never been drawn reports zero geometry, and one frame is not
-- always enough to settle it. That is only survivable if we notice: the IsTruncated()
-- check that would normally catch a bad fit is reading the same unsettled layout, so
-- the fitter accepts maxSize and the name renders at full size with "...". Symptom is
-- the first name after a reload being wrong and every one after it being right.
local FIT_MAX_RETRIES = 3
local runFit  -- forward declaration: the verification pass below re-enters it

local function measureAndPaint(onDone)
    lastResult = addon.FitTextToBox(nameFS, {
        maxLines = cfg.maxLines,
        maxSize  = cfg.maxSize,
        minSize  = cfg.minSize,
        mode     = cfg.mode,
        face     = addon.ResolveFontFace(cfg.face),
        style    = cfg.style,
        -- Secret text cannot be measured at all, so this is what actually renders on
        -- every restricted unit. It is the shipping size, not an error path.
        fallbackSize = cfg.fallbackSize,
    })

    -- secretText means the fit will fail identically forever; retrying only delays
    -- the paint by three frames. Only an unsettled layout is worth another look.
    local unsettled = (lastResult.zeroWidth or lastResult.measurable == false)
        and not lastResult.secretText
    if unsettled and fitRetries < FIT_MAX_RETRIES then
        fitRetries = fitRetries + 1
        -- The plain value is still on the FontString, so re-fitting is idempotent.
        C_Timer.After(0, function() measureAndPaint(onDone) end)
        return
    end
    lastRetries = fitRetries

    applyGradient(lastResult)

    -- Mirror the measured text bounds. If the geometry ever comes back secret this
    -- box simply stops drawing, which is a faster signal than reading a dump.
    local w = addon.FitSafeNumber(nameFS, "GetStringWidth")
    local h = addon.FitSafeNumber(nameFS, "GetStringHeight")
    if boundsBox then
        if w and h and w > 0 and h > 0 then
            boundsBox:SetSize(w, h)
            boundsBox:Show()
        else
            boundsBox:Hide()
        end
    end

    if onDone then onDone() end

    -- Verification pass. The fitter's own IsTruncated() reads the layout it just
    -- mutated, so a stale "not truncated" is indistinguishable from a real one and the
    -- loop exits having verified nothing. Re-ask once the layout has settled: a fit
    -- that claimed truncated == false over text that is visibly truncated is a flat
    -- contradiction, whatever the underlying cause. Cheaper and more reliable than
    -- guessing which read went stale.
    if lastResult.truncated == false and fitRetries < FIT_MAX_RETRIES then
        C_Timer.After(0, function()
            if addon.FitSafeBool(nameFS, "IsTruncated") == true then
                fitRetries = fitRetries + 1
                runFit()
            end
        end)
    end
end

-- Fitting and line discovery both have to run against the uncolored string, so a
-- gradient pass has to be undone first. But a FontString under-reports its width
-- until it has been laid out once with its current text, and FitTextToBox reading a
-- zero width is exactly how text ends up rendered at full size and ellipsized. So
-- restoring the plain value costs a frame before anything may be measured.
function runFit(onDone)
    if not nameFS then return end
    if type(currentValue) == "nil" then return end

    if plainApplied then
        measureAndPaint(onDone)
        return
    end

    applyValue()
    C_Timer.After(0, function() measureAndPaint(onDone) end)
end

-- Same reason, for the SetText/SetSize that just happened in the caller.
local function scheduleFit()
    C_Timer.After(0, function() runFit() end)
end

--------------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------------

local function ensureFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "ScootNameTextTest", UIParent)
    frame:SetSize(cfg.width, cfg.height)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)

    -- skipDimensionCheck is required: ApplySquare silently refuses frames wider than
    -- 400px or taller than 100px, and this one gets resized live during testing.
    if addon.Borders and addon.Borders.ApplySquare then
        addon.Borders.ApplySquare(frame, {
            size = 1,
            color = { 0.35, 0.85, 1.0, 1 },
            skipDimensionCheck = true,
        })
    end

    boundsBox = CreateFrame("Frame", nil, frame)
    boundsBox:SetSize(1, 1)
    boundsBox:SetPoint("CENTER", frame, "CENTER", 0, 0)
    if addon.Borders and addon.Borders.ApplySquare then
        addon.Borders.ApplySquare(boundsBox, {
            size = 1,
            color = { 1.0, 0.45, 0.1, 0.9 },
            skipDimensionCheck = true,
        })
    end
    -- Stays hidden until a measurement actually succeeds.
    boundsBox:Hide()

    nameFS = frame:CreateFontString(nil, "OVERLAY")
    -- A font at creation time, before any text is ever set. CreateFontString with no
    -- template leaves the region with no font object at all, so the first SetText has
    -- nothing to lay out against -- and the first fit then measures a FontString whose
    -- font was assigned microseconds earlier. Same reason cast/textfill.lua:206 and
    -- the measurement ruler both set a default font up front.
    nameFS:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    nameFS:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    nameFS:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    nameFS:SetJustifyH("CENTER")
    nameFS:SetJustifyV("MIDDLE")
    nameFS:SetTextColor(1, 1, 1, 1)

    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:SetScript("OnEvent", function() addon.DebugNameTextRefresh() end)

    -- CreateFrame returns a shown frame; start hidden so the first toggle reveals it.
    frame:Hide()

    return frame
end

-- Measurements are unreliable on a never-laid-out region, so every mutator shows the
-- harness rather than silently fitting into a hidden box.
local function ensureShown()
    ensureFrame()
    if not frame:IsShown() then frame:Show() end
    return frame
end

local function pullTargetName()
    local name = UnitName("target")

    -- type() reports the real type for secrets, so this only separates "no target"
    -- from "has a name". Never boolean-test the name itself.
    if type(name) == "nil" then
        setValue("(no target)", false, "no target")
    else
        local secret = (issecretvalue and issecretvalue(name)) and true or false
        setValue(name, secret, "UnitName('target')")
    end
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

function addon.DebugNameTextRefresh()
    if not frame or not frame:IsShown() then return end
    pullTargetName()
    scheduleFit()
end

function addon.DebugNameTextToggle()
    ensureFrame()
    if frame:IsShown() then
        frame:Hide()
        hideSlices()
        addon:Print("Name text harness hidden.")
        return
    end
    frame:Show()
    addon:Print("Name text harness shown. Target something, or: /scoot debug nametext sample 4")
    addon.DebugNameTextRefresh()
end

function addon.DebugNameTextSetSize(w, h)
    ensureShown()
    cfg.width  = tonumber(w) or cfg.width
    cfg.height = tonumber(h) or cfg.height
    frame:SetSize(cfg.width, cfg.height)
    scheduleFit()
    addon:Print(string.format("Container: %dx%d", cfg.width, cfg.height))
end

function addon.DebugNameTextSetLines(n)
    ensureShown()
    cfg.maxLines = math.max(1, math.floor(tonumber(n) or cfg.maxLines))
    scheduleFit()
    addon:Print("Max lines: " .. cfg.maxLines)
end

function addon.DebugNameTextSetRange(minSize, maxSize)
    ensureShown()
    cfg.minSize = tonumber(minSize) or cfg.minSize
    cfg.maxSize = tonumber(maxSize) or cfg.maxSize
    scheduleFit()
    addon:Print(string.format("Font size range: %s - %s", tostring(cfg.minSize), tostring(cfg.maxSize)))
end

-- The size used when nothing can be measured, which is every restricted name. On the
-- secret path this is not an error size, it IS the render size.
function addon.DebugNameTextSetFallback(n)
    ensureShown()
    cfg.fallbackSize = math.max(1, math.floor(tonumber(n) or cfg.fallbackSize))
    scheduleFit()
    addon:Print("Fallback size (unmeasurable text): " .. cfg.fallbackSize)
end

function addon.DebugNameTextSetMode(mode)
    ensureShown()
    mode = tostring(mode or ""):lower()
    if mode ~= "font" and mode ~= "scale" and mode ~= "blizzard" then
        addon:Print("Mode must be one of: font | scale | blizzard")
        return
    end
    cfg.mode = mode
    -- "scale" leaves a residual text scale behind; reset before switching away.
    if nameFS and nameFS.SetTextScale then pcall(nameFS.SetTextScale, nameFS, 1) end
    scheduleFit()
    addon:Print("Fit mode: " .. cfg.mode)
end

function addon.DebugNameTextSetFont(face)
    ensureShown()
    if face and face ~= "" then cfg.face = face end
    scheduleFit()
    addon:Print("Font face: " .. cfg.face)
end

function addon.DebugNameTextSample(n)
    ensureShown()
    n = math.floor(tonumber(n) or 1)
    local index = ((n - 1) % #SAMPLES) + 1
    setValue(SAMPLES[index], false, "sample " .. index)
    scheduleFit()
    addon:Print(string.format("Sample %d/%d: %s", index, #SAMPLES, SAMPLES[index]))
end

function addon.DebugNameTextSetGradient(mode)
    ensureShown()
    mode = tostring(mode or ""):lower()
    if mode ~= "off" and mode ~= "line" and mode ~= "block"
       and mode ~= "slice" and mode ~= "auto" then
        addon:Print("Gradient must be one of: off | line | block | slice | auto")
        return
    end
    cfg.gradient = mode
    scheduleFit()
    addon:Print("Gradient: " .. cfg.gradient
        .. (mode == "auto" and "  (line when readable, slice when secret)" or ""))
end

function addon.DebugNameTextSetSlices(n)
    ensureShown()
    cfg.slices = math.max(1, math.min(64, math.floor(tonumber(n) or cfg.slices)))
    scheduleFit()
    addon:Print("Slice columns: " .. cfg.slices)
end

function addon.DebugNameTextSetClass(token)
    ensureShown()
    token = token and token ~= "" and token or "auto"
    if token:lower() == "auto" then
        cfg.forcedClass = nil
        addon:Print("Class: auto (read from target)")
    else
        cfg.forcedClass = token:upper()
        addon:Print("Class forced to: " .. cfg.forcedClass)
    end
    scheduleFit()
end

function addon.DebugNameTextSetTreatment(which)
    ensureShown()
    which = tostring(which or ""):lower()
    if which ~= "cast" and which ~= "raw" then
        addon:Print("Treatment must be one of: cast | raw")
        return
    end
    cfg.treatment = which
    scheduleFit()
    addon:Print("Treatment: " .. cfg.treatment
        .. (which == "cast" and "  (start = class color darkened 25%)"
                             or "  (start = class color untouched)"))
end

local function buildReport()
    local lines = {}
    local function push(s) lines[#lines + 1] = s end

    local r = lastResult or {}
    local c = lastColors or {}

    push("== Scoot name auto-fit + gradient feasibility ==")
    push("")

    -- Verdict first: this is the whole point of the harness.
    local verdict
    if r.measurable == true and currentIsSecret then
        verdict = "PASS - measured a SECRET name successfully. Auto-fit is viable."
    elseif r.measurable == true then
        verdict = "PASS (weak) - measurement works, but this name was NOT secret. "
                .. "Re-run while targeting an NPC."
    elseif r.fallback then
        verdict = string.format(
            "NOT MEASURED - rendering at the fallback size (%s), NOT a fit. Reason: %s",
            safeStr(r.size), safeStr(r.reason))
    else
        verdict = "FAIL - geometry unreadable: " .. safeStr(r.reason)
    end
    push("FIT VERDICT:      " .. verdict)

    local gverdict
    if lastGradientMode == "slice" then
        gverdict = "slice stack active (" .. cfg.slices .. " columns) - works on secret text, "
                 .. "banded, ramp spans the box not each line"
    elseif lastLines and #lastLines > 1 then
        gverdict = "PASS - " .. #lastLines .. " lines, each with its own ramp (via "
                 .. safeStr(lastDiscovery) .. ")"
    elseif lastLines then
        gverdict = "single line ramp (via " .. safeStr(lastDiscovery)
                 .. ") - force a wrap to test per-line"
    else
        gverdict = "no |cff ramp: " .. safeStr(lastGradientNote)
    end
    push("GRADIENT VERDICT: " .. gverdict)
    push("")

    push("-- Restriction state --")
    if C_Secrets then
        if C_Secrets.HasSecretRestrictions then
            local ok, v = pcall(C_Secrets.HasSecretRestrictions)
            push("  HasSecretRestrictions():              " .. (ok and safeStr(v) or "<error>"))
        end
        if C_Secrets.ShouldUnitIdentityBeSecret then
            local ok, v = pcall(C_Secrets.ShouldUnitIdentityBeSecret, "target")
            push("  ShouldUnitIdentityBeSecret('target'): " .. (ok and safeStr(v) or "<error>"))
        end
    else
        push("  C_Secrets not present")
    end
    push("  InCombatLockdown():                   " .. safeStr(InCombatLockdown()))
    push("")

    push("-- Text source --")
    push("  source:            " .. safeStr(lastSource))
    push("  name was secret:   " .. safeStr(currentIsSecret))
    push("  GetText():         " .. measure("GetText"))
    push("")

    push("-- Anchoring (the gate) --")
    if type(nameFS.IsAnchoringSecret) == "function" then
        push("  fs:IsAnchoringSecret():   " .. measure("IsAnchoringSecret"))
    else
        push("  fs:IsAnchoringSecret():   <API not present>")
    end
    if frame.IsAnchoringSecret then
        local ok, v = pcall(frame.IsAnchoringSecret, frame)
        push("  frame:IsAnchoringSecret(): " .. (ok and safeStr(v) or "<error>"))
    end
    push("")

    push("-- Measurements --")
    push("  GetStringWidth():          " .. measure("GetStringWidth"))
    push("  GetUnboundedStringWidth(): " .. measure("GetUnboundedStringWidth"))
    push("  GetStringHeight():         " .. measure("GetStringHeight"))
    push("  GetWrappedWidth():         " .. measure("GetWrappedWidth"))
    push("  GetNumLines():             " .. measure("GetNumLines"))
    push("  IsTruncated():             " .. measure("IsTruncated"))
    push("  GetLineHeight():           " .. measure("GetLineHeight"))
    push("  GetMaxLines():             " .. measure("GetMaxLines"))
    push("  GetTextScale():            " .. measure("GetTextScale"))
    push("  fs GetWidth()/GetHeight(): " .. measure("GetWidth") .. " x " .. measure("GetHeight"))
    push("")

    push("-- Fit result --")
    push("  mode:        " .. safeStr(cfg.mode))
    push("  box:         " .. string.format("%dx%d", cfg.width, cfg.height))
    push("  size range:  " .. safeStr(cfg.minSize) .. " - " .. safeStr(cfg.maxSize))
    push("  fallback:    " .. safeStr(cfg.fallbackSize) .. "  (used when nothing is measurable)")
    push("  max lines:   " .. safeStr(cfg.maxLines))
    push("  font face:   " .. safeStr(cfg.face) .. " (" .. safeStr(cfg.style) .. ")")
    push("  -> measurable:  " .. safeStr(r.measurable))
    push("  -> fallback:    " .. safeStr(r.fallback)
        .. (r.fallback and "  (size below was DECLARED, not measured)" or ""))
    push("  -> secretText:  " .. safeStr(r.secretText)
        .. (r.secretText and "  (will never be measurable; retries skipped)" or ""))
    push("  -> applied size:" .. safeStr(r.size))
    push("  -> text scale:  " .. safeStr(r.scale))
    push("  -> max lines:   " .. safeStr(r.maxLines) .. "  (as applied by the fit)")
    push("  -> lines used:  " .. safeStr(r.lines))
    push("  -> truncated:   " .. safeStr(r.truncated))
    push("  -> iterations:  " .. ((cfg.mode == "blizzard") and "n/a (internal to Blizzard's loop)" or safeStr(r.iterations)))
    if r.zeroWidth then push("  -> zeroWidth:   true (layout had not settled; descended from maxSize)") end
    push("  -> settle retries: " .. safeStr(lastRetries)
        .. ((lastRetries > 0) and "  (layout was not ready on the first pass)" or ""))
    if r.reason then push("  -> reason:      " .. safeStr(r.reason)) end
    push("")

    push("-- Gradient --")
    push("  requested:      " .. safeStr(cfg.gradient))
    push("  effective:      " .. safeStr(lastGradientMode))
    push("  treatment:      " .. safeStr(cfg.treatment))
    push("  identity:       " .. safeStr(cfg.identity))
    push("  UnitIsPlayer('target'): " .. safeStr(targetIsPlayer()))
    push("  class token:    " .. safeStr(c.token) .. (cfg.forcedClass and "  (forced)" or ""))
    push("  ramp start:     #" .. hex(c.r1, c.g1, c.b1))
    push("  ramp end:       #" .. hex(c.r2, c.g2, c.b2))
    push("  discovery path: " .. safeStr(lastDiscovery))
    if lastGradientNote then push("  note:           " .. safeStr(lastGradientNote)) end
    push("  slice columns:  " .. safeStr(cfg.slices)
        .. ((lastGradientMode == "slice") and "  (live)" or "  (idle)"))
    push("")

    -- Everything under "Measurements" above describes the MASTER FontString, which is
    -- held at alpha 0 while the slice stack is drawing. So the master can fit perfectly
    -- and the screen can still be wrong. These are the copies you are actually looking
    -- at; any disagreement with the master localises the bug to the replay.
    push("-- Slice stack (what is on screen in slice mode) --")
    local s1 = slicePool[1]
    if lastGradientMode ~= "slice" then
        push("  idle - the master FontString above is what is drawing")
    elseif not s1 then
        push("  slice mode active but no slices were built")
    else
        push("  replayed size:      " .. safeStr(lastSliceSize)
            .. "   scale " .. safeStr(lastSliceScale)
            .. (lastSliceFallback and "   *** FROM A FALLBACK FIT, not a measurement ***" or ""))
        push("  replayed maxLines:  " .. safeStr(lastSliceMaxLines)
            .. "   (from result.maxLines - what the fit applied, not a read-back)")
        push("  slice[1] GetNumLines():       " .. measureOn(s1.fs, "GetNumLines"))
        push("  slice[1] IsTruncated():       " .. measureOn(s1.fs, "IsTruncated"))
        push("  slice[1] GetMaxLines():       " .. measureOn(s1.fs, "GetMaxLines"))
        push("  slice[1] GetLineHeight():     " .. measureOn(s1.fs, "GetLineHeight"))
        push("  slice[1] GetStringWidth():    " .. measureOn(s1.fs, "GetStringWidth"))
        push("  slice[1] GetStringHeight():   " .. measureOn(s1.fs, "GetStringHeight"))
        push("  slice[1] GetWordWrap():       " .. measureOn(s1.fs, "GetWordWrap"))
        push("  slice[1] fs W/H:              " .. measureOn(s1.fs, "GetWidth")
            .. " x " .. measureOn(s1.fs, "GetHeight"))
        push("  slice[1] IsAnchoringSecret(): " .. measureOn(s1.fs, "IsAnchoringSecret"))
        push("  clip[1] W/H:                  " .. measureOn(s1.clip, "GetWidth")
            .. " x " .. measureOn(s1.clip, "GetHeight"))
        push("  slices built:                 " .. #slicePool)
    end
    push("")

    push("-- Discovered lines --")
    if lastLines then
        for i, ln in ipairs(lastLines) do
            push(string.format("  [%d] bytes %s-%s  left=%s width=%s%s",
                i, safeStr(ln.first), safeStr(ln.last),
                ln.left and string.format("%.1f", ln.left) or "n/a",
                ln.width and string.format("%.1f", ln.width) or "n/a",
                ln.overflow and "  OVERFLOW" or ""))
            push("      \"" .. safeStr(ln.text) .. "\"")
        end
    else
        push("  none")
    end
    push("")

    -- What actually went onto the FontString. Per-character |cff markup turns every
    -- glyph into its own shaping run, so the ramped width is not automatically the
    -- plain width -- compare them here rather than assume.
    push("-- Ramped string --")
    if lastRamped then
        push("  total bytes:   " .. #lastRamped)
        local face = addon.ResolveFontFace(cfg.face)
        local size = (lastResult and lastResult.size) or cfg.maxSize
        local seg = 0
        for chunk in (lastRamped .. "\n"):gmatch("(.-)\n") do
            seg = seg + 1
            local stripped = chunk:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local rw = addon.MeasureTextWidth(chunk, face, size, cfg.style)
            local pw = addon.MeasureTextWidth(stripped, face, size, cfg.style)
            push(string.format("  [%d] %d chars  plain=%s  ramped=%s  box=%d",
                seg, #stripped,
                pw and string.format("%.1f", pw) or "nil",
                rw and string.format("%.1f", rw) or "nil",
                cfg.width))
            push("      \"" .. stripped .. "\"")
        end
        push("  segments:      " .. seg)
    else
        push("  none")
    end
    push("")

    push("-- Environment --")
    push("  AutoScalingFontStringMixin present: " .. safeStr(_G.AutoScalingFontStringMixin ~= nil))
    push("  ScaleTextToFit present:             "
        .. safeStr(_G.AutoScalingFontStringMixin ~= nil
                   and type(_G.AutoScalingFontStringMixin.ScaleTextToFit) == "function"))
    push("  fs.ClearText present:               " .. safeStr(type(nameFS.ClearText) == "function"))
    push("  fs.SetSmoothScaling present:        " .. safeStr(type(nameFS.SetSmoothScaling) == "function"))
    push("  fs.CalculateScreenAreaFromCharacterSpan: "
        .. safeStr(type(nameFS.CalculateScreenAreaFromCharacterSpan) == "function"))
    push("  fs.GetUnboundedStringWidthForText:  "
        .. safeStr(type(nameFS.GetUnboundedStringWidthForText) == "function"))

    -- Diagnostic only, no render path uses it. isWithinText is a way to probe a
    -- SECRET string's length without reading it, which may matter later.
    if type(nameFS.SetAlphaGradient) == "function" then
        local ok, within = pcall(nameFS.SetAlphaGradient, nameFS, 1, 1)
        push("  SetAlphaGradient(1,1) -> isWithinText: " .. (ok and safeStr(within) or "<error>"))
        if nameFS.ClearAlphaGradient then pcall(nameFS.ClearAlphaGradient, nameFS) end
    else
        push("  fs.SetAlphaGradient:                <API not present>")
    end

    addon.DebugShowWindow("Name Auto-Fit + Gradient Feasibility", lines)
end

function addon.DebugNameTextSetIdentity(which)
    ensureShown()
    which = tostring(which or ""):lower()
    if which ~= "player" and which ~= "class" then
        addon:Print("Identity must be one of: player | class")
        return
    end
    cfg.identity = which
    scheduleFit()
    addon:Print("Identity: " .. cfg.identity
        .. (which == "player" and "  (class ramp only when UnitIsPlayer)"
                               or "  (class ramp whenever a class token resolves)"))
end

-- Which units, right now, actually report restricted identity? Capital-city NPCs come
-- back unrestricted, so "target an NPC" is not a reliable way to exercise the secret
-- path. This sweeps every unit token worth trying and says which ones qualify.
local SCAN_UNITS = {
    "player", "target", "targettarget", "focus", "mouseover", "pet",
    "boss1", "boss2", "boss3", "boss4", "boss5",
    "arena1", "arena2", "arena3",
    "party1", "party2", "party3", "party4",
    "nameplate1", "nameplate2", "nameplate3", "nameplate4", "nameplate5",
    "nameplate6", "nameplate7", "nameplate8", "nameplate9", "nameplate10",
}

function addon.DebugNameTextScan()
    local lines = {}
    local function push(s) lines[#lines + 1] = s end

    push("== Unit identity secrecy sweep ==")
    push("")
    if C_Secrets and C_Secrets.HasSecretRestrictions then
        local ok, v = pcall(C_Secrets.HasSecretRestrictions)
        push("HasSecretRestrictions(): " .. (ok and safeStr(v) or "<error>"))
    end
    push("InCombatLockdown():      " .. safeStr(InCombatLockdown()))
    push("")
    push("unit            exists  isPlayer  shouldBeSecret  nameIsSecret")
    push(string.rep("-", 64))

    local secretCount = 0
    for _, unit in ipairs(SCAN_UNITS) do
        local okE, exists = pcall(UnitExists, unit)
        if okE and exists then
            local _, isPlayer = pcall(UnitIsPlayer, unit)

            local shouldSecret = "n/a"
            if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
                local okS, v = pcall(C_Secrets.ShouldUnitIdentityBeSecret, unit)
                shouldSecret = okS and safeStr(v) or "<error>"
            end

            -- The ground truth: ask for the name and see what comes back.
            local nameSecret = "n/a"
            local okN, name = pcall(UnitName, unit)
            if okN and type(name) ~= "nil" then
                nameSecret = (issecretvalue and issecretvalue(name)) and "SECRET" or "plain"
                if nameSecret == "SECRET" then secretCount = secretCount + 1 end
            end

            push(string.format("%-15s %-7s %-9s %-15s %s",
                unit, "yes", safeStr(isPlayer), shouldSecret, nameSecret))
        end
    end

    push("")
    if secretCount > 0 then
        push(secretCount .. " unit(s) returned a SECRET name. Target one and run "
            .. "'/scoot debug nametext report' to exercise the secret path.")
    else
        push("No unit currently returns a secret name. Retry in combat, in an instance,")
        push("or against hostile/boss units -- restriction level is contextual.")
    end

    addon.DebugShowWindow("Unit Identity Secrecy Sweep", lines)
end

--------------------------------------------------------------------------------
-- SetAlphaGradient length oracle probe
--------------------------------------------------------------------------------
-- SetAlphaGradient(start, length) -> isWithinText is the only FontString function
-- found that reports something about a SECRET string's content and is not annotated
-- to go secret itself: no SecretReturnsForAspect, no SecretWhenAnchoringSecret, only
-- SecretArguments = "AllowedWhenUntainted" -- which constrains what we pass in
-- (plain integers), not what comes back (SimpleFontStringAPIDocumentation.lua:463).
-- It has zero callers in Blizzard's source and no Documentation field, so every
-- claim about it has to be measured rather than read.
--
-- If isWithinText is monotonic in `start`, its transition point is the length of a
-- string nobody can read, recoverable by bisection in ~7 calls. That would put a
-- size-bucketed auto-fit back on the table for restricted names, which is currently
-- the one thing the secret rules take away outright.
--
-- Probed on two subjects, because which one answers tells us what it counts:
--   free    -- no width, wrap off: holds the whole string, so its transition is the
--              STRING length
--   display -- the harness box: wrapped and possibly ellipsized. A lower transition
--              here means the oracle counts RENDERED characters, which would make it
--              a truncation detector rather than a length oracle. Either is useful;
--              they are useful for different designs.

local PROBE_LIMIT = 128
local probeFS

local function ensureProbeFS()
    if probeFS then return probeFS end

    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(1, 1)
    holder:SetPoint("CENTER", UIParent, "CENTER", 0, -300)
    -- Shown but transparent, not hidden. A hidden region may skip layout entirely,
    -- and a layout-sensitive oracle would then answer about nothing at all.
    holder:SetAlpha(0)

    probeFS = holder:CreateFontString(nil, "OVERLAY")
    probeFS:SetPoint("CENTER", holder, "CENTER", 0, 0)  -- single point => natural width
    probeFS:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    if probeFS.SetWidth then probeFS:SetWidth(0) end
    if probeFS.SetWordWrap then probeFS:SetWordWrap(false) end
    if probeFS.SetTextScale then probeFS:SetTextScale(1) end

    return probeFS
end

-- true / false, or nil plus a tag describing why it was not a plain boolean.
local function alphaProbe(fs, start, length)
    if not fs or type(fs.SetAlphaGradient) ~= "function" then return nil, "noAPI" end
    local ok, within = pcall(fs.SetAlphaGradient, fs, start, length or 1)
    if not ok then return nil, "err" end
    if issecretvalue and issecretvalue(within) then return nil, "SECRET" end
    if within == true or within == false then return within end
    return nil, "nonbool(" .. safeStr(within) .. ")"
end

-- Exhaustive sweep. Bisection is what a shipping fitter would use, but it only gives
-- the right answer if the predicate is monotonic, and that is exactly the assumption
-- under test -- so measure every index once and check.
local function alphaScan(fs, limit)
    local out = { seq = {}, calls = 0, monotonic = true }
    local sawFalse = false
    for i = 0, limit do
        local v, tag = alphaProbe(fs, i, 1)
        out.calls = out.calls + 1
        out.seq[i] = (v == true and "T") or (v == false and "F") or tag
        if tag then
            if tag == "SECRET" and not out.firstSecret then out.firstSecret = i end
            if not out.firstBad then out.firstBad = i .. ":" .. tag end
        elseif v then
            out.lastTrue = i
            if sawFalse then out.monotonic = false end
        else
            sawFalse = true
            if not out.firstFalse then out.firstFalse = i end
        end
    end
    return out
end

-- The production shape: largest n in [0, limit] with isWithinText true. Measured
-- 2026-07-28: the index is 0-BASED and inclusive, so the character count is
-- best + 1, and best == -1 means the string is empty. Bisecting from 1 instead
-- would report 0 for both a one-character string and an empty one.
local function alphaBisect(fs, limit)
    local lo, hi, best, calls = 0, limit, -1, 0
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        calls = calls + 1
        if alphaProbe(fs, mid, 1) == true then
            best = mid
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    return best, calls
end

-- Run-length encoded so a 129-entry sweep reads as one line.
local function formatSeq(seq, limit)
    local parts, i = {}, 0
    while i <= limit do
        local ch, j = seq[i], i
        while j + 1 <= limit and seq[j + 1] == ch do j = j + 1 end
        parts[#parts + 1] = (j > i) and string.format("%s[%d..%d]", tostring(ch), i, j)
                                     or string.format("%s[%d]", tostring(ch), i)
        i = j + 1
    end
    return table.concat(parts, "  ")
end

-- Continuation bytes are 0x80..0xBF; everything else starts a character.
local function utf8Count(s)
    local n = 0
    for i = 1, #s do
        local b = string.byte(s, i)
        if b < 0x80 or b >= 0xC0 then n = n + 1 end
    end
    return n
end

local function buildProbeReport()
    local out = {}
    local function push(s) out[#out + 1] = s end

    push("== SetAlphaGradient length-oracle probe ==")
    push("")

    if type(nameFS.SetAlphaGradient) ~= "function" then
        push("FontString:SetAlphaGradient is not present in this build.")
        push("The oracle does not exist; auto-fit on secret names is closed.")
        addon.DebugShowWindow("Length Oracle Probe", out)
        return
    end

    local free = ensureProbeFS()

    -- Everything is measured before anything is cleared.
    local freeScan = alphaScan(free, PROBE_LIMIT)
    local freeBest, freeCalls = alphaBisect(free, PROBE_LIMIT)
    local dispScan = alphaScan(nameFS, PROBE_LIMIT)
    local dispBest, dispCalls = alphaBisect(nameFS, PROBE_LIMIT)

    -- Does the second argument influence the answer, or is it purely a render knob?
    local lengthCtl = {}
    for _, L in ipairs({ 0, 1, 8, 1000 }) do
        local v, tag = alphaProbe(free, 1, L)
        lengthCtl[#lengthCtl + 1] = string.format("start=1 length=%-4d -> %s",
            L, (v == nil) and (tag or "?") or safeStr(v))
    end

    -- A gradient is render state, not a query. Put both subjects back.
    local canClear = type(nameFS.ClearAlphaGradient) == "function"
    if canClear then
        pcall(nameFS.ClearAlphaGradient, nameFS)
        pcall(free.ClearAlphaGradient, free)
    end

    local bytes, chars
    local readable = type(currentValue) == "string"
        and not (issecretvalue and issecretvalue(currentValue))
    if readable then
        bytes = #currentValue
        chars = utf8Count(currentValue)
    end

    ----------------------------------------------------------------------------
    -- Verdict
    ----------------------------------------------------------------------------
    local verdict
    if freeScan.firstSecret then
        verdict = "DEAD - isWithinText returned SECRET at start=" .. freeScan.firstSecret
            .. ". The oracle is annotated non-secret but does not behave that way."
    elseif freeScan.firstBad then
        verdict = "DEAD - probe failed at index " .. freeScan.firstBad
    elseif not freeScan.monotonic then
        verdict = "UNUSABLE - isWithinText is not monotonic in start. "
            .. "Bisection cannot recover a length from a non-monotonic predicate."
    elseif freeBest ~= (freeScan.lastTrue or -1) then
        verdict = string.format(
            "UNUSABLE - bisection says %d, exhaustive scan says %s. They must agree.",
            freeBest, safeStr(freeScan.lastTrue))
    elseif freeBest < 0 then
        verdict = "NO SIGNAL - isWithinText was false at every index, including 0. "
            .. "Either the FontString had not laid out, or the text is empty."
    elseif readable then
        -- The index is 0-based and inclusive, so the count is one more than the last
        -- true index. Checked against BOTH units: only an accented name separates
        -- them, which is what sample 7 exists for.
        local count = freeBest + 1
        local unit
        if bytes == chars and count == bytes then
            unit = "bytes and characters are equal for this name (pure ASCII) - "
                .. "re-run on sample 7 to tell them apart"
        elseif count == chars then
            unit = "counts CHARACTERS (UTF-8 aware) - accented names do not skew it"
        elseif count == bytes then
            unit = "counts BYTES - accented names will over-report"
        else
            unit = string.format("count %d matches NEITHER #text (%d) nor the UTF-8 count (%d)",
                count, bytes, chars)
        end
        verdict = string.format(
            "ORACLE RESPONDS on a readable name: last true index %d -> count %d, "
            .. "in %d bisection calls; %s", freeBest, count, freeCalls, unit)
        verdict = verdict .. "  --  now re-run while targeting a unit whose name IS secret."
    else
        verdict = string.format(
            "ORACLE HOLDS ON A SECRET NAME: %d characters, recovered in %d bisection calls "
            .. "without reading a byte.", freeBest + 1, freeCalls)
    end
    push("ORACLE VERDICT:  " .. verdict)
    push("")

    ----------------------------------------------------------------------------
    push("-- Subject --")
    push("  source:            " .. safeStr(lastSource))
    push("  name was secret:   " .. safeStr(currentIsSecret))
    push("  GetText():         " .. measure("GetText"))
    push("  #text (bytes):     " .. (bytes and tostring(bytes) or "unreadable"))
    push("  UTF-8 characters:  " .. (chars and tostring(chars) or "unreadable"))
    push("  probe limit:       " .. PROBE_LIMIT)
    push("  ClearAlphaGradient present: " .. safeStr(canClear)
        .. (canClear and "" or "   <- a gradient has been LEFT on both FontStrings"))
    push("")

    push("-- Probe A: free FontString (no width, wrap off, whole string on one line) --")
    push("  fs:IsAnchoringSecret():  " .. measureOn(free, "IsAnchoringSecret"))
    push("  fs:GetStringWidth():     " .. measureOn(free, "GetStringWidth"))
    push("  last true index:         " .. safeStr(freeScan.lastTrue))
    push("  first false index:       " .. safeStr(freeScan.firstFalse))
    push("  monotonic:               " .. safeStr(freeScan.monotonic))
    push("  first SECRET return:     " .. (freeScan.firstSecret and tostring(freeScan.firstSecret) or "none"))
    push("  first bad return:        " .. (freeScan.firstBad or "none"))
    push("  bisection:               last true " .. freeBest .. " => count "
        .. (freeBest + 1) .. ", in " .. freeCalls .. " calls"
        .. ((freeBest == (freeScan.lastTrue or -1)) and "   (agrees with scan)"
                                                     or "   *** DISAGREES WITH SCAN ***"))
    push("  sweep (" .. freeScan.calls .. " calls):")
    push("    " .. formatSeq(freeScan.seq, PROBE_LIMIT))
    push("")

    push("-- Probe B: display FontString (box-constrained, wrapped, may be ellipsized) --")
    push("  fs:IsAnchoringSecret():  " .. measure("IsAnchoringSecret"))
    push("  last true index:         " .. safeStr(dispScan.lastTrue))
    push("  first false index:       " .. safeStr(dispScan.firstFalse))
    push("  monotonic:               " .. safeStr(dispScan.monotonic))
    push("  first SECRET return:     " .. (dispScan.firstSecret and tostring(dispScan.firstSecret) or "none"))
    push("  first bad return:        " .. (dispScan.firstBad or "none"))
    push("  bisection:               last true " .. dispBest .. " => count "
        .. (dispBest + 1) .. ", in " .. dispCalls .. " calls")
    push("  sweep (" .. dispScan.calls .. " calls):")
    push("    " .. formatSeq(dispScan.seq, PROBE_LIMIT))
    push("")

    push("-- What the second argument does --")
    for _, s in ipairs(lengthCtl) do push("  " .. s) end
    push("")

    push("-- Interpretation --")
    local layoutNote
    if dispBest == freeBest then
        layoutNote = string.format(
            "identical (%d) -> nothing was dropped: the name fits on one line at this "
            .. "size and no break character was consumed", freeBest + 1)
    elseif dispBest < freeBest then
        -- Measured 2026-07-28: a wrap CONSUMES the space it breaks on, so a clean
        -- two-line layout already reads one short. The gap is dropped characters of
        -- any kind -- breaks plus ellipsis -- not truncation alone.
        layoutNote = string.format(
            "display %d < free %d, %d character(s) dropped -> counts RENDERED "
            .. "characters. Each wrap eats its space, so expect (lines - 1) of the gap "
            .. "to be breaks; anything beyond that is ellipsis.",
            dispBest + 1, freeBest + 1, freeBest - dispBest)
    else
        layoutNote = string.format(
            "display %d > free %d -> unexplained; both hold the same value, so this "
            .. "should not happen", dispBest + 1, freeBest + 1)
    end
    push("  layout sensitivity: " .. layoutNote)
    push("  index base:         probe(0) = " .. safeStr(freeScan.seq[0])
        .. "   probe(1) = " .. safeStr(freeScan.seq[1])
        .. "   (0-based inclusive: count = lastTrue + 1)")
    if readable then
        push(string.format("  units:              oracle count=%d  bytes=%d  utf8=%d",
            freeBest + 1, bytes, chars))
    else
        push("  units:              cannot be checked - the name is secret, which is the point. "
            .. "Calibrate on a readable name first.")
    end
    push("")

    push("-- Fit state at probe time --")
    local r = lastResult or {}
    push("  measurable:  " .. safeStr(r.measurable))
    push("  fallback:    " .. safeStr(r.fallback))
    push("  applied size:" .. safeStr(r.size))
    push("  max lines:   " .. safeStr(r.maxLines))
    push("  reason:      " .. safeStr(r.reason))

    addon.DebugShowWindow("Length Oracle Probe", out)
end

function addon.DebugNameTextLengthProbe()
    ensureShown()
    if not lastSource then pullTargetName() end

    -- Fit first, so Probe B describes the layout the harness actually renders. Then
    -- force the PLAIN value back on: under a |cff ramp every index is a markup byte
    -- and both counts become meaningless.
    runFit(function()
        applyValue()

        local free = ensureProbeFS()
        addon.ApplyFontStyle(free, addon.ResolveFontFace(cfg.face), cfg.maxSize, cfg.style)
        if free.SetTextScale then pcall(free.SetTextScale, free, 1) end
        if free.ClearText then pcall(free.ClearText, free) end
        pcall(free.SetText, free, currentValue)

        -- Both subjects were just re-texted. A FontString that has not been laid out
        -- since its last SetText reports stale geometry, and if the oracle turns out
        -- to be layout-driven it would answer about the previous string. Same
        -- one-frame settle the fitter needs.
        C_Timer.After(0, function()
            buildProbeReport()
            runFit()  -- repaint whatever the gradient mode was drawing
        end)
    end)
end

--------------------------------------------------------------------------------
-- Oracle-driven fit probe: does D(size) settle within the same frame?
--------------------------------------------------------------------------------
-- The length probe established two things: SetAlphaGradient answers on a secret
-- string, and its answer is LAYOUT-sensitive -- on a box-constrained FontString it
-- counts the characters that actually rendered. So as the font grows and the engine
-- starts consuming break characters and ellipsizing, the count falls. Call that
-- D(size).
--
-- D being monotonic in size is what makes a blind shrink-to-fit possible: read D at
-- the smallest size to get the ceiling, then bisect for the largest size that still
-- hits it. That is the largest size which loses nothing -- computed without reading a
-- byte and without asking for a single dimension.
--
-- Whether it is PRACTICAL comes down to settling. If D reflects a size change in the
-- same frame, the entire search is one synchronous function costing ~40 oracle calls.
-- If it lags a frame, every candidate costs a frame and the name visibly steps through
-- ~6 sizes after each target change. Both are workable, but they are different
-- designs, and assuming the convenient one is exactly how the previous round of this
-- work went wrong. So measure D three times per size -- immediately, one frame later,
-- two frames later -- and compare the columns.
--
-- The +2 frame column is the control on the control. If it disagrees with +1, the
-- deferred reads are not settled either and neither column can be treated as truth.

local FITPROBE_STEPS = 12

-- count, calls, tag. The leading probe(0) is not redundant: alphaBisect treats any
-- non-true return as false, so a SECRET or errored return would silently shorten the
-- count instead of announcing itself. Cheap per-row integrity check.
local function measureCount(fs)
    local _, tag = alphaProbe(fs, 0, 1)
    if tag then return nil, 1, tag end

    local best, calls = alphaBisect(fs, PROBE_LIMIT)
    if type(fs.ClearAlphaGradient) == "function" then
        pcall(fs.ClearAlphaGradient, fs)
    end
    -- True at the very top of the range is not a count, it is the absence of one: a
    -- FontString whose layout is dirty answers "yes, inside the text" at every index.
    -- Measured 2026-07-28: that is exactly what a read taken in the same frame as the
    -- SetFont returns. Reporting it as PROBE_LIMIT+1 characters invents a number, and
    -- an invented number that large silently poisons every comparison downstream.
    if best >= PROBE_LIMIT then return nil, calls + 1, "saturated" end
    return best + 1, calls + 1
end

-- Whatever layout the fitter would have applied, applied by hand. The probe drives the
-- point size directly rather than SetTextScale whatever cfg.mode says, because a
-- size-bisecting fitter is a point-size design -- scaling a fitted string is a
-- different question.
local function fitProbeLayout()
    if nameFS.SetWordWrap then pcall(nameFS.SetWordWrap, nameFS, true) end
    if nameFS.SetMaxLines then pcall(nameFS.SetMaxLines, nameFS, cfg.maxLines) end
    if nameFS.SetTextScale then pcall(nameFS.SetTextScale, nameFS, 1) end
end

local function buildSizeLadder(steps)
    local lo, hi = cfg.minSize, cfg.maxSize
    if hi < lo then lo, hi = hi, lo end

    steps = math.max(3, math.min(math.floor(tonumber(steps) or FITPROBE_STEPS), 44))

    local out, seen = {}, {}
    for i = 0, steps - 1 do
        local s = math.floor(lo + (hi - lo) * i / (steps - 1) + 0.5)
        if not seen[s] then
            seen[s] = true
            out[#out + 1] = s
        end
    end
    return out
end

local function fmtCount(v, tag)
    if v ~= nil then return tostring(v) end
    return "<" .. (tag or "?") .. ">"
end

-- Largest ladder size whose count still equals the ceiling -- i.e. exactly what a
-- bisecting fitter would land on, computed from one column of the table. Running it
-- over each column separately is the point: if the same-frame column picks a different
-- size than the settled one, that difference IS the cost of trusting same-frame reads.
local function pickFromColumn(rows, key, ceiling)
    local best
    for _, row in ipairs(rows) do
        if row[key] ~= nil and row[key] == ceiling then best = row.size end
    end
    return best
end

local function buildFitProbeReport(rows, freeCount, freeTag, calls, frames)
    local out = {}
    local function push(s) out[#out + 1] = s end

    ----------------------------------------------------------------------------
    -- Analysis
    ----------------------------------------------------------------------------
    local anyTag, varied, monotonic = nil, false, true
    local deferAgree, deferChecked = 0, 0
    local sameAgree, sameChecked = 0, 0
    local staleByOne, staleChecked = 0, 0
    local sameSaturated = 0
    local prevTruth

    -- Saturation is an expected answer, not a malfunction -- it is the finding. Only a
    -- genuinely broken return (SECRET, error, non-boolean) invalidates the run.
    local function realTag(t)
        if t and t ~= "saturated" then return t end
        return nil
    end

    for i, row in ipairs(rows) do
        anyTag = anyTag or realTag(row.sameTag) or realTag(row.d1Tag) or realTag(row.d2Tag)
        if row.sameTag == "saturated" then sameSaturated = sameSaturated + 1 end

        -- d2 is the settled value; d1 is only trustworthy if it matches.
        if row.d1 ~= nil and row.d2 ~= nil then
            deferChecked = deferChecked + 1
            if row.d1 == row.d2 then deferAgree = deferAgree + 1 end
        end

        if row.same ~= nil and row.d2 ~= nil then
            sameChecked = sameChecked + 1
            if row.same == row.d2 then
                sameAgree = sameAgree + 1
            elseif i > 1 and prevTruth ~= nil then
                -- The signature of a one-frame lag: the "new" reading is the previous
                -- size's answer. Distinguishing that from generic disagreement is the
                -- difference between "add a frame" and "the oracle is unreliable".
                staleChecked = staleChecked + 1
                if row.same == prevTruth then staleByOne = staleByOne + 1 end
            end
        end

        if row.d2 ~= nil then
            if prevTruth ~= nil then
                if row.d2 ~= prevTruth then varied = true end
                if row.d2 > prevTruth then monotonic = false end
            end
            prevTruth = row.d2
        end
    end

    local ceiling = rows[1] and rows[1].d2
    local pickTruth = ceiling and pickFromColumn(rows, "d2", ceiling)
    local pickSame  = ceiling and pickFromColumn(rows, "same", ceiling)
    local pickD1    = ceiling and pickFromColumn(rows, "d1", ceiling)

    local sameFrameOK = (sameChecked > 0) and (sameAgree == sameChecked)
    local oneFrameOK  = (deferChecked > 0) and (deferAgree == deferChecked)

    -- What the shipping fitter would cost: a bisection over the size range, each
    -- candidate itself a bisection over the character index.
    local function log2(n) return math.ceil(math.log(n) / math.log(2)) end
    local sizeCandidates    = math.max(1, log2(math.abs(cfg.maxSize - cfg.minSize) + 1))
    local callsPerCandidate = log2(PROBE_LIMIT + 1)

    ----------------------------------------------------------------------------
    -- Verdict
    ----------------------------------------------------------------------------
    local verdict
    if anyTag then
        verdict = "BROKEN - the oracle stopped returning a plain boolean (" .. anyTag
            .. "). Every count below is suspect; re-run 'lengthprobe' first."
    elseif not oneFrameOK then
        verdict = string.format(
            "UNSETTLED - the +1 frame and +2 frame columns disagree at %d of %d sizes. "
            .. "Even a deferred read is not stable, so there is no trustworthy column "
            .. "here and the fitter needs a settle loop, not a fixed delay.",
            deferChecked - deferAgree, deferChecked)
    elseif not varied then
        verdict = string.format(
            "INCONCLUSIVE - D never changed across the whole ladder (always %s). The "
            .. "box never forced the engine to drop a character, so nothing was under "
            .. "test. Use a longer name (sample 4 or 5) or narrow the box "
            .. "('/scoot debug nametext size 90 40') and re-run.",
            safeStr(ceiling))
    elseif not monotonic then
        -- Measured cause, 2026-07-28: the truncation ellipsis is itself three rendered
        -- characters. The instant the engine starts ellipsizing, D jumps by +3 and then
        -- resumes falling, so the curve has a step back up in it.
        verdict = "NON-MONOTONIC - a larger font reported MORE rendered characters. The "
            .. "known cause is the ellipsis: '...' is three rendered characters, so D "
            .. "gains +3 the moment truncation starts. 'Largest size that still keeps "
            .. "the full count' is therefore UNSOUND -- an ellipsized layout that "
            .. "dropped exactly 3 characters reads as a perfect fit. Size the text from "
            .. "a scratch FontString with maxLines unbounded, where nothing is ever "
            .. "ellipsized, rather than from the display one."
    elseif sameFrameOK then
        verdict = string.format(
            "SAME-FRAME READS ARE TRUSTWORTHY - all %d sizes agree with the settled "
            .. "value. A blind shrink-to-fit is one synchronous function: ~%d size "
            .. "candidates x ~%d oracle calls = ~%d calls, ZERO extra frames.",
            sameChecked, sizeCandidates, callsPerCandidate,
            sizeCandidates * callsPerCandidate)
    elseif sameSaturated > 0 then
        verdict = string.format(
            "ONE FRAME PER CANDIDATE - the same-frame reads are not stale, they are "
            .. "SATURATED: %d of %d answered true at EVERY index, which is what a dirty "
            .. "layout reports. They carry no information at all, so there is nothing to "
            .. "trust or distrust. The +1f and +2f columns agree at all %d sizes, so one "
            .. "frame settles it cleanly: a ~%d-step size search costs ~%d frames per "
            .. "target change.",
            sameSaturated, #rows, deferChecked, sizeCandidates, sizeCandidates)
    else
        local stale = (staleChecked > 0 and staleByOne == staleChecked)
        verdict = string.format(
            "SAME-FRAME READS ARE STALE - they disagree with the settled value at %d of "
            .. "%d sizes.%s Each candidate costs a frame, so a ~%d-step bisection means "
            .. "~%d frames per target change and the name steps through sizes on screen.",
            sameChecked - sameAgree, sameChecked,
            stale and " Every disagreement equals the PREVIOUS size's answer, so the read"
                .. " is exactly one frame behind -- not noisy, just late." or "",
            sizeCandidates, sizeCandidates)
    end

    push("== Oracle fit probe: does D(size) settle in the same frame? ==")
    push("")
    push("VERDICT:  " .. verdict)
    push("")

    ----------------------------------------------------------------------------
    push("-- Subject --")
    push("  source:            " .. safeStr(lastSource))
    push("  name was secret:   " .. safeStr(currentIsSecret))
    push("  GetText():         " .. measure("GetText"))
    push("  free-string count: " .. fmtCount(freeCount, freeTag)
        .. "   (unconstrained FontString = the true character count)")
    push(string.format("  box:               %d x %d, maxLines %d, %s %s",
        cfg.width, cfg.height, cfg.maxLines, cfg.face, cfg.style))
    push(string.format("  ladder:            %d sizes from %d to %d",
        #rows, cfg.minSize, cfg.maxSize))
    push(string.format("  cost:              %d oracle calls over %d frames", calls, frames))
    push("")

    ----------------------------------------------------------------------------
    push("-- D(size): characters that survived layout, at each font size --")
    push("   size    same-frame    +1 frame    +2 frames   same == +2f?")
    for _, row in ipairs(rows) do
        local mark
        if row.same == nil or row.d2 == nil then
            mark = "-"
        elseif row.same == row.d2 then
            mark = "yes"
        else
            mark = "NO"
        end
        push(string.format("   %4d    %10s    %8s    %9s   %s",
            row.size,
            fmtCount(row.same, row.sameTag),
            fmtCount(row.d1, row.d1Tag),
            fmtCount(row.d2, row.d2Tag),
            mark))
    end
    push("")

    ----------------------------------------------------------------------------
    push("-- Settling --")
    push(string.format("  +1f vs +2f:         %d of %d agree%s",
        deferAgree, deferChecked,
        oneFrameOK and "   (one frame is enough to settle)" or "   *** NOT SETTLED ***"))
    push(string.format("  same-frame vs +2f:  %d of %d agree", sameAgree, sameChecked))
    if staleChecked > 0 then
        push(string.format("  stale-by-one:       %d of %d disagreements equal the PREVIOUS "
            .. "size's answer", staleByOne, staleChecked))
    end
    push("  note: row 1's same-frame read follows whatever size the fit left behind, so")
    push("        it is excluded from the stale-by-one signature.")
    push("")

    ----------------------------------------------------------------------------
    push("-- What a bisecting fitter would pick --")
    push("  ceiling (D at size " .. (rows[1] and rows[1].size or "?") .. "): "
        .. safeStr(ceiling))
    push("  largest size holding the ceiling:")
    push("     using +2 frame reads (truth):  " .. safeStr(pickTruth))
    push("     using +1 frame reads:          " .. safeStr(pickD1)
        .. ((pickD1 == pickTruth) and "   (matches)" or "   *** DIFFERS ***"))
    push("     using same-frame reads:        " .. safeStr(pickSame)
        .. ((pickSame == pickTruth) and "   (matches)" or "   *** DIFFERS ***"))
    if freeCount and ceiling then
        if ceiling == freeCount then
            push("  ceiling == free count -> nothing is dropped even at the smallest size,")
            push("     so the ceiling really is the whole name.")
        else
            push(string.format("  ceiling %d < free count %d -> even the smallest size loses %d "
                .. "character(s).", ceiling, freeCount, freeCount - ceiling))
            push("     The fit can only ever be 'least bad'; widen the box or raise maxLines")
            push("     if that matters.")
        end
    end
    push("")

    ----------------------------------------------------------------------------
    push("-- Fit state before the probe ran --")
    local r = lastResult or {}
    push("  measurable:   " .. safeStr(r.measurable))
    push("  fallback:     " .. safeStr(r.fallback))
    push("  applied size: " .. safeStr(r.size))
    push("  reason:       " .. safeStr(r.reason))

    addon.DebugShowWindow("Oracle Fit Probe", out)
end

function addon.DebugNameTextFitProbe(steps)
    ensureShown()
    if not lastSource then pullTargetName() end

    if not nameFS or type(nameFS.SetAlphaGradient) ~= "function" then
        addon.DebugShowWindow("Oracle Fit Probe", {
            "FontString:SetAlphaGradient is not present in this build.",
            "There is no oracle to drive a fit with.",
        })
        return
    end

    local ladder = buildSizeLadder(steps)
    local face = addon.ResolveFontFace(cfg.face)
    local rows, calls, frames = {}, 0, 0

    -- Fit first so the harness is in a known state, then force the PLAIN value back on:
    -- under a |cff ramp every index is a markup byte and D counts nothing meaningful.
    runFit(function()
        applyValue()
        fitProbeLayout()

        local free = ensureProbeFS()
        addon.ApplyFontStyle(free, face, cfg.maxSize, cfg.style)
        if free.SetTextScale then pcall(free.SetTextScale, free, 1) end
        if free.ClearText then pcall(free.ClearText, free) end
        pcall(free.SetText, free, currentValue)

        -- Both subjects were just re-texted; let that land before anything is measured,
        -- or the first row reports on the previous string rather than the previous size.
        C_Timer.After(0, function()
            frames = frames + 1

            local freeCount, freeCalls, freeTag = measureCount(free)
            calls = calls + freeCalls

            local i = 1
            local function step()
                if i > #ladder then
                    buildFitProbeReport(rows, freeCount, freeTag, calls, frames)
                    runFit()   -- hand the box back to the normal fit + gradient path
                    return
                end

                local row = { size = ladder[i] }
                rows[i] = row

                addon.ApplyFontStyle(nameFS, face, row.size, cfg.style)
                fitProbeLayout()

                -- No yield between the size change and this read. That is the question.
                local c
                row.same, c, row.sameTag = measureCount(nameFS)
                calls = calls + c

                C_Timer.After(0, function()
                    frames = frames + 1
                    row.d1, c, row.d1Tag = measureCount(nameFS)
                    calls = calls + c

                    C_Timer.After(0, function()
                        frames = frames + 1
                        row.d2, c, row.d2Tag = measureCount(nameFS)
                        calls = calls + c
                        i = i + 1
                        step()
                    end)
                end)
            end
            step()
        end)
    end)
end

function addon.DebugNameTextReport()
    ensureShown()
    -- Seed from the target if nothing has been fitted yet, then re-fit before dumping
    -- so the numbers describe what is actually on screen. runFit may need a frame to
    -- restore the plain string first, hence the callback.
    if not lastSource then pullTargetName() end
    runFit(buildReport)
end
