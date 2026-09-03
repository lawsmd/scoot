-- fonts.lua - Font definitions, registration, and font picker UI
local addonName, addon = ...

addon.Fonts = addon.Fonts or {}
addon.WorldTextFontLog = addon.WorldTextFontLog or {}

-- Last-resort face. Stock with the client, so it is the one path that can be
-- relied on to load in any session.
local FALLBACK_FONT_PATH = "Fonts\\FRIZQT__.TTF"
addon.FALLBACK_FONT_PATH = FALLBACK_FONT_PATH

local function SnapshotFontObject(fontObj)
    if type(fontObj) ~= "table" or not fontObj.GetFont then
        return "<unavailable>"
    end
    local ok, path, size, flags = pcall(fontObj.GetFont, fontObj)
    if not ok then
        return "<error>"
    end
    return string.format("%s | size=%s | flags=%s", tostring(path or "?"), tostring(size or "?"), tostring(flags or ""))
end

local function FormatExtra(info)
    if type(info) ~= "table" then
        return tostring(info or "")
    end
    local parts = {}
    for k, v in pairs(info) do
        table.insert(parts, string.format("%s=%s", tostring(k), tostring(v)))
    end
    table.sort(parts)
    return table.concat(parts, "; ")
end

local function AppendWorldTextFontLog(stage, info)
    local log = addon.WorldTextFontLog
    if type(log) ~= "table" then
        log = {}
        addon.WorldTextFontLog = log
    end
    local timestamp = string.format("%.1fms", debugprofilestop())
    local snapshot = string.format("DAMAGE_TEXT_FONT=%s | CombatTextFont=%s | CombatTextFontOutline=%s",
        tostring(_G.DAMAGE_TEXT_FONT),
        SnapshotFontObject(_G.CombatTextFont),
        SnapshotFontObject(_G.CombatTextFontOutline)
    )
    local line = string.format("[%s] %s :: %s", timestamp, tostring(stage or "?"), snapshot)
    local extra = FormatExtra(info)
    if extra ~= "" then
        line = line .. " || " .. extra
    end
    table.insert(log, line)
    -- Limit log size
    if #log > 200 then
        table.remove(log, 1)
    end
end

addon.LogWorldTextFont = AppendWorldTextFontLog

function addon.ShowWorldTextFontLog()
    if addon.DebugShowWindow then
        addon.DebugShowWindow("World Text Font Log", addon.WorldTextFontLog)
    elseif addon.Print then
        addon:Print("Debug window unavailable; open after core/debug.lua loads.")
    end
end

AppendWorldTextFontLog("fonts.lua:load", { init = true })

-- Build a container compatible with Settings dropdown options for font faces.
-- Uses stock fonts available in all clients; extensible via media.
function addon.BuildFontOptionsContainer()
    local create = _G.Settings and _G.Settings.CreateControlTextContainer
    local displayNames = addon.FontDisplayNames or {}

    local add = function(container, key, text)
        if container._seen and container._seen[key] then return end
        if create then
            container:Add(key, text)
        else
            table.insert(container, { value = key, text = text })
        end
        if container._seen then container._seen[key] = true end
    end

    local container = create and create() or {}
    container._seen = {}

    -- Always include FRIZQT__ first (stock default)
    add(container, "FRIZQT__", displayNames.FRIZQT__ or "FRIZQT__")

    -- Add stock fonts next (excluding FRIZQT__ which is already added)
    local stockFonts = { "ARIALN", "MORPHEUS", "SKURRI" }
    for _, k in ipairs(stockFonts) do
        add(container, k, displayNames[k] or k)
    end

    -- Collect and sort all registered fonts by their display names for alphabetical ordering
    local fontEntries = {}
    for k, _ in pairs(addon.Fonts or {}) do
        -- Skip stock fonts (already added above)
        if k ~= "FRIZQT__" and k ~= "ARIALN" and k ~= "MORPHEUS" and k ~= "SKURRI" then
            local display = displayNames[k] or k
            table.insert(fontEntries, { key = k, display = display })
        end
    end

    -- Sort by display name for cleaner grouping (Dosis, Exo 2, Lato, etc.)
    table.sort(fontEntries, function(a, b)
        return a.display < b.display
    end)

    -- Add all custom fonts
    for _, entry in ipairs(fontEntries) do
        add(container, entry.key, entry.display)
    end

    container._seen = nil
    return create and container:GetData() or container
end

-- Face of GameFontNormal: a locale-dependent game font (Friz Quadrata on
-- Latin locales), not a Scoot font. Cached on first probe.
local cachedGameFontNormalFace
function addon.GetGameFontNormalFace()
    if not cachedGameFontNormalFace then
        cachedGameFontNormalFace = select(1, _G.GameFontNormal:GetFont())
    end
    return cachedGameFontNormalFace
end

-- Resolve a font face name to a file path for SetFont.
-- Falls back to the face of GameFontNormal if unknown. Never returns nil.
function addon.ResolveFontFace(key)
    key = key or "FRIZQT__"
    -- LSM-sourced font
    if addon.IsLSMKey and addon.IsLSMKey(key) then
        local path = addon.LSMFetch and addon.LSMFetch("font", key)
        if path then return path end
        -- LSM font unavailable; fall through to GameFontNormal fallback
    end
    local face = (addon.Fonts and addon.Fonts[key])
                 or (select(1, _G.GameFontNormal:GetFont()))
    return face
end

--------------------------------------------------------------------------------
-- Font Style Catalog
--------------------------------------------------------------------------------
-- The one source of truth for the Font Style enum. Every dropdown reads these
-- tables (through aliases in the ui/v2 Helpers files) and ApplyFontStyle
-- decodes the keys. Keys are pseudo-styles, not engine flags: the
-- SHADOW*/HEAVY*/DEEPSHADOW* prefixes and the *SLUG suffix are decoded by
-- ApplyFontStyle below.

local slugSupported = false
local slugSeparator = " "
do
    -- The crisp styles need the vector text renderer. Two gates: the API
    -- surface must exist, and SetFont must accept a SLUG-bearing flag string.
    -- Invalid flags error instead of no-op as of 12.0.7, and the accepted
    -- separator form is undocumented, so probe the candidates.
    local probe = UIParent and UIParent:CreateFontString(nil, "ARTWORK")
    if probe and probe.SetSmoothScaling ~= nil then
        for _, sep in ipairs({ " ", ", ", "," }) do
            local ok, accepted = pcall(probe.SetFont, probe, FALLBACK_FONT_PATH, 12, "OUTLINE" .. sep .. "SLUG")
            if ok and accepted ~= false then
                local readOk, _, _, flags = pcall(probe.GetFont, probe)
                if readOk and type(flags) == "string" and flags:find("SLUG", 1, true) then
                    slugSupported = true
                    slugSeparator = sep
                    break
                end
            end
        end
    end
    if probe then probe:Hide() end
end

addon.FontStyles = {
    -- The master label table. Gated keys keep their labels here so a stored
    -- value still displays its name when hidden from the option list
    -- (Selector shows values[currentKey] even for keys absent from order).
    values = {
        NONE = "Regular",
        OUTLINE = "Outline",
        THICKOUTLINE = "Thick Outline",
        HEAVYTHICKOUTLINE = "Heavy Thick Outline",
        SHADOW = "Shadow",
        SHADOWOUTLINE = "Shadow Outline",
        SHADOWTHICKOUTLINE = "Shadow Thick Outline",
        OUTLINESLUG = "Crisp Outline",
        THICKOUTLINESLUG = "Crisp Thick Outline",
        SHADOWTHICKOUTLINESLUG = "Crisp Shadow Thick Outline",
        DEEPSHADOWOUTLINE = "Deep Shadow Outline",
        DEEPSHADOWTHICKOUTLINE = "Deep Shadow Thick Outline",
    },
    slugSupported = slugSupported,
    slugSeparator = slugSeparator,
}

do
    local BASE = { "NONE", "OUTLINE", "THICKOUTLINE", "HEAVYTHICKOUTLINE", "SHADOW", "SHADOWOUTLINE", "SHADOWTHICKOUTLINE" }
    -- The PRD dropdowns list OUTLINE first because it is their default.
    local OUTLINE_FIRST = { "OUTLINE", "NONE", "THICKOUTLINE", "HEAVYTHICKOUTLINE", "SHADOW", "SHADOWOUTLINE", "SHADOWTHICKOUTLINE" }
    local CRISP = { "OUTLINESLUG", "THICKOUTLINESLUG", "SHADOWTHICKOUTLINESLUG" }
    -- Deep Shadow draws a mirrored copy of the string, so it is offered only
    -- where every targeted FontString is Scoot-created with Scoot-fed text;
    -- those dropdowns opt in by using a *Paired order table.
    local PAIRED = { "DEEPSHADOWOUTLINE", "DEEPSHADOWTHICKOUTLINE" }

    local function buildOrder(base, includePaired)
        local order = {}
        for _, k in ipairs(base) do order[#order + 1] = k end
        if slugSupported then
            for _, k in ipairs(CRISP) do order[#order + 1] = k end
        end
        if includePaired then
            for _, k in ipairs(PAIRED) do order[#order + 1] = k end
        end
        return order
    end

    addon.FontStyles.order = buildOrder(BASE, false)
    addon.FontStyles.orderPaired = buildOrder(BASE, true)
    addon.FontStyles.orderOutlineFirst = buildOrder(OUTLINE_FIRST, false)
    addon.FontStyles.orderOutlineFirstPaired = buildOrder(OUTLINE_FIRST, true)
end

-- DEEPSHADOW* stripped back to its base style, which decodes to the same
-- engine flags without the companion copy. Two callers want this.
--
-- A FontString whose text arrives from anywhere but Lua SetText: the copy is
-- fed by hooks on the real string, so an engine-written string (an aura
-- container binding) leaves the copy permanently empty. A stored Deep Shadow
-- value on such a string renders as its base style rather than as nothing.
function addon.FontStyles.Unpaired(style)
    if type(style) == "string" and style:sub(1, 10) == "DEEPSHADOW" then
        return style:sub(11)
    end
    return style
end

-- And a measurement ruler, where a companion is permanent hooks and per-measure
-- mirroring for nothing. The metrics are identical either way.
addon.FontStyles.MetricStyle = addon.FontStyles.Unpaired

-- /scoot debug slug: ground truth for the SLUG flag on the live client. Shows
-- each candidate flag string rendered side by side and prints what SetFont
-- and GetFont report for it, plus the load-time probe verdict.
function addon.FontStyles.DebugSlugProbe()
    local candidates = { "OUTLINE", "OUTLINE SLUG", "OUTLINE, SLUG", "OUTLINE,SLUG", "SLUG" }
    local f = addon._slugProbeFrame
    if not f then
        f = CreateFrame("Frame", "ScootSlugProbe", UIParent)
        f:SetSize(460, 30 + #candidates * 36)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetScript("OnMouseDown", function(self, button)
            if button == "RightButton" then self:Hide() end
        end)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.75)
        f.rows = {}
        for i = 1, #candidates do
            local fs = f:CreateFontString(nil, "ARTWORK")
            fs:SetPoint("TOPLEFT", 16, -(16 + (i - 1) * 36))
            f.rows[i] = fs
        end
        addon._slugProbeFrame = f
    end
    addon:Print(string.format("slug probe: SetSmoothScaling %s; load verdict supported=%s separator=%q",
        f.rows[1].SetSmoothScaling ~= nil and "present" or "absent",
        tostring(addon.FontStyles.slugSupported), addon.FontStyles.slugSeparator))
    for i, flags in ipairs(candidates) do
        local fs = f.rows[i]
        local ok, accepted = pcall(fs.SetFont, fs, FALLBACK_FONT_PATH, 24, flags)
        local rejected = not (ok and accepted ~= false)
        if rejected then
            -- Keep the row readable: a failed SetFont can leave it unfonted.
            pcall(fs.SetFont, fs, FALLBACK_FONT_PATH, 24, "OUTLINE")
        end
        local _, _, _, readFlags = pcall(fs.GetFont, fs)
        fs:SetText(string.format("[%s]%s The quick brown fox 0123", flags, rejected and " REJECTED" or ""))
        addon:Print(string.format("slug[%d] %q -> ok=%s accepted=%s readback=%s",
            i, flags, tostring(ok), tostring(accepted), tostring(readFlags)))
    end
    f:Show()
    addon:Print("slug probe window shown (right-click to close)")
end

--------------------------------------------------------------------------------
-- Font Style Application Helper (supports SHADOW and HEAVY prefixes)
--------------------------------------------------------------------------------

-- Set a font file on a FontString. Returns true only when the REQUESTED file
-- was accepted; see the fallback rules inline below.
--
-- Scratch list for the fallback walk, reused so the common (successful) path
-- allocates nothing.
local fontCandidates = {}

local function applyFontFile(fs, font, size, style)
    local ok, accepted = pcall(fs.SetFont, fs, font, size, style)
    -- SetFont returns false (without raising) for a file the client has not
    -- loaded, so the pcall status alone proves nothing.
    if ok and accepted ~= false then
        return true
    end

    -- A SLUG flag the client rejects must not cost the face: retry once with
    -- SLUG stripped before starting the fallback walk.
    if type(style) == "string" and style:find("SLUG", 1, true) then
        local stripped = (style:gsub("%s*,?%s*SLUG", ""))
        ok, accepted = pcall(fs.SetFont, fs, font, size, stripped)
        if ok and accepted ~= false then
            return true
        end
    end

    -- The requested face would not load. If the string already carries a font,
    -- KEEP it -- an existing face is always a better answer than forcing Friz,
    -- and callers rely on that: unitframesz applies a base face and then an
    -- optional override precisely so a non-loadable override leaves the base
    -- showing (see applyOverrideFace in unitframesz/engine.lua).
    if fs.GetFont and fs:GetFont() ~= nil then
        return false
    end

    -- Nothing on the string at all. It MUST get a font here: SetText on an
    -- unfonted FontString raises "Font not set", so an invisible row would
    -- become an error. Walk to something the client will accept.
    for i = #fontCandidates, 1, -1 do
        fontCandidates[i] = nil
    end
    -- Built without nil holes: a hole stops ipairs at the first gap and the
    -- later fallbacks would never be tried.
    local gameFont = _G.GameFontNormal and select(1, _G.GameFontNormal:GetFont())
    if type(gameFont) == "string" and gameFont ~= "" and gameFont ~= font then
        fontCandidates[#fontCandidates + 1] = gameFont
    end
    if font ~= FALLBACK_FONT_PATH and gameFont ~= FALLBACK_FONT_PATH then
        fontCandidates[#fontCandidates + 1] = FALLBACK_FONT_PATH
    end

    for _, path in ipairs(fontCandidates) do
        local fallbackOk, fallbackAccepted = pcall(fs.SetFont, fs, path, size, style)
        if fallbackOk and fallbackAccepted ~= false then
            return false  -- readable, but not the face that was asked for
        end
    end

    return false
end

-- Shared with core/fontpair.lua so the paired copy gets the same face
-- resolution and fallback behavior as the string it mirrors.
addon.ApplyFontFile = applyFontFile

-- Apply font settings to a FontString. Style keys are pseudo-styles decoded
-- here, not raw engine flags. NONE, OUTLINE, and THICKOUTLINE pass through;
-- the rest compose:
--   SHADOW*: drop shadow, SetShadowColor(0,0,0,0.8) + SetShadowOffset(1,-1).
--   HEAVY*: upper-right shadow, SetShadowColor(0,0,0,0.9) + SetShadowOffset(1,1);
--     thickens the glyph opposite the drop-shadow direction.
--   *SLUG: appends the SLUG engine flag (vector text renderer) when the client
--     accepts it (addon.FontStyles.slugSupported); dropped silently otherwise,
--     so a stored crisp value renders its base style on incapable clients.
--   DEEPSHADOW*: draws a black offset copy of the string behind it via
--     addon.FontPair (core/fontpair.lua); the built-in shadow stays zeroed.
--
-- Returns true when the REQUESTED face was applied, false when the
-- client would not load it (the string is left with whatever readable font it
-- had, or given a fallback if it had none). Callers that care can surface the
-- "this face needs a full client restart" case -- see verifyAppliedFace in
-- unitframesz/engine.lua.
function addon.ApplyFontStyle(fs, font, size, style)
    if not fs then return end
    local applied = true
    style = style or ""

    -- Suffix first: the crisp variants wrap a base key.
    local wantSlug = false
    if style:sub(-4) == "SLUG" then
        wantSlug = true
        style = style:sub(1, -5)
    end

    -- Detect prefixes (check longer ones first to avoid partial matches)
    local heavy = false
    local shadow = false
    local paired = false

    if style:sub(1, 10) == "DEEPSHADOW" then
        paired = true
        style = style:sub(11) -- Strip DEEPSHADOW prefix
    elseif style:sub(1, 11) == "HEAVYSHADOW" then
        -- Backward compat: HEAVYSHADOW* saved settings render as regular SHADOW
        shadow = true
        style = style:sub(12) -- Strip HEAVYSHADOW prefix
    elseif style:sub(1, 5) == "HEAVY" then
        heavy = true
        style = style:sub(6) -- Strip HEAVY prefix
    elseif style:sub(1, 6) == "SHADOW" then
        shadow = true
        style = style:sub(7) -- Strip SHADOW prefix
    end

    -- Normalize "NONE" to empty string (Blizzard convention)
    if style == "NONE" or style == "" then
        style = ""
    end

    if wantSlug and addon.FontStyles.slugSupported then
        style = (style == "") and "SLUG"
            or (style .. addon.FontStyles.slugSeparator .. "SLUG")
    end

    -- Apply the font.
    --
    -- SetFont does not raise when the file is missing or the client has not
    -- loaded it this session -- it returns false and leaves the FontString
    -- UNFONTED, and a later SetText on an unfonted string errors with "Font not
    -- set". A bare pcall throws that signal away, which is why a bundled face
    -- that has not been loaded yet (the classic new-machine case: a font file
    -- added since the client started needs a full restart, not a /reload) shows
    -- up as blank or default-looking text with no error. So walk the fallbacks
    -- and confirm one took.
    if fs.SetFont then
        if not applyFontFile(fs, font, size, style) then
            applied = false
        end
    end

    -- Apply shadow settings
    if fs.SetShadowColor and fs.SetShadowOffset then
        if heavy then
            -- Heavy: thickens text with upper-right offset (opposite of drop shadow look)
            pcall(fs.SetShadowColor, fs, 0, 0, 0, 0.9)
            pcall(fs.SetShadowOffset, fs, 1, 1)
        elseif shadow then
            -- Regular shadow: dark color with subtle offset
            pcall(fs.SetShadowColor, fs, 0, 0, 0, 0.8)
            pcall(fs.SetShadowOffset, fs, 1, -1)
        else
            -- No shadow: transparent with no offset
            pcall(fs.SetShadowColor, fs, 0, 0, 0, 0)
            pcall(fs.SetShadowOffset, fs, 0, 0)
        end
    end

    -- Deep Shadow: the depth comes from a black copy behind the string, so
    -- keep the companion in sync, and hide it when the style moves away.
    if addon.FontPair then
        if paired then
            addon.FontPair.Apply(fs, font, size, style)
        elseif fs.__scootPair then
            addon.FontPair.Hide(fs)
        end
    end

    return applied
end

--------------------------------------------------------------------------------
-- Config-Table Font Resolution / Application
--------------------------------------------------------------------------------
-- The font half of a text-style config sub-table: cfg -> (face, size, style)
-- under the shared dialect rules. Color, alignment, and positioning stay
-- caller-side.
--
-- cfg keys read: fontFace, size, style -- or fontFace, fontSize, fontStyle
-- with opts.longKeys (the damage-meter spelling). Deliberately no or-chain
-- across the two spellings: each surface declares its schema, so a stray key
-- from the other dialect can never silently apply.
--
-- opts:
--   size            default point size when cfg carries none (default 12)
--   style           default pseudo-style key (default "OUTLINE")
--   longKeys        read fontSize/fontStyle instead of size/style
--   gameFontDefault when cfg.fontFace is nil, keep GameFontNormal's
--                   locale-correct face instead of resolving to the bundled
--                   Friz path (the Cooldown Manager dialect; a Blizzard-fed
--                   face on a non-Latin locale must not be forced onto
--                   FRIZQT__)
local EMPTY_OPTS = {}
function addon.ResolveTextFont(cfg, opts)
    cfg = cfg or EMPTY_OPTS
    opts = opts or EMPTY_OPTS
    local size, style
    if opts.longKeys then
        size, style = tonumber(cfg.fontSize), cfg.fontStyle
    else
        size, style = tonumber(cfg.size), cfg.style
    end
    size = size or opts.size or 12
    style = tostring(style or opts.style or "OUTLINE")
    local face
    if cfg.fontFace == nil and opts.gameFontDefault then
        face = addon.GetGameFontNormalFace()
    else
        face = addon.ResolveFontFace(cfg.fontFace)
    end
    return face, size, style
end

-- Apply the font half of a text-style config to a FontString. Returns
-- ApplyFontStyle's verdict (true only when the requested face applied).
-- No-ops on a nil fs or nil cfg: Zero-Touch callers gate on customization
-- above this, and a nil cfg must never stomp a Blizzard font with
-- Friz-at-default.
function addon.ApplyTextFont(fs, cfg, opts)
    if not fs or not cfg then return end
    return addon.ApplyFontStyle(fs, addon.ResolveTextFont(cfg, opts))
end

-- Does this text-style cfg sub-table carry any user customization?
-- NIL-COMPARE semantics: any stored value counts. This is the Zero-Touch
-- styling gate for Blizzard-owned strings. The VALUE-COMPARE predicate
-- (differs-from-structural-defaults) is addon.BarsUtils.hasCustomTextSettings
-- in unitframes/bars/utils.lua and gates overlay existence; the two are not
-- interchangeable.
--
-- Always counted: fontFace (stored, not "" and not "FRIZQT__"); size, style,
-- color stored at all; colorMode stored and not "" / "default"; offset stored
-- with a nonzero x or y.
-- opts: alignment, alignmentMode, colorModeDK -- opt-in extra keys
--       (colorModeDK counts when stored and not "default").
function addon.HasTextCustomization(cfg, opts)
    if not cfg then return false end
    if cfg.fontFace ~= nil and cfg.fontFace ~= "" and cfg.fontFace ~= "FRIZQT__" then return true end
    if cfg.size ~= nil or cfg.style ~= nil or cfg.color ~= nil then return true end
    if cfg.colorMode ~= nil and cfg.colorMode ~= "" and cfg.colorMode ~= "default" then return true end
    if opts then
        if opts.alignment and cfg.alignment ~= nil then return true end
        if opts.alignmentMode and cfg.alignmentMode ~= nil then return true end
        if opts.colorModeDK and cfg.colorModeDK ~= nil and cfg.colorModeDK ~= "default" then return true end
    end
    local off = cfg.offset
    if off and (off.x ~= nil or off.y ~= nil) then
        if (tonumber(off.x) or 0) ~= 0 or (tonumber(off.y) or 0) ~= 0 then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Shrink-to-Fit Text Helper
--------------------------------------------------------------------------------
-- Fit a string into a fixed box: wrap at spaces first, and only shrink the text
-- when wrapping is not enough. Truncates with "..." only after hitting minSize.
--
-- Does NOT work on secret strings, and cannot be made to. IsAnchoringSecret is
-- misnamed: its annotation is SecretReturnsForAspect = { ObjectSecrets }
-- (SimpleScriptRegionAPIDocumentation.lua:367), so it reports "does this object
-- hold any secret aspect", not "is it anchored to something secret". SetText
-- carries SecretArgumentsAddAspect = { Text }, so pouring a secret name into a
-- FontString stamps the aspect onto that FontString and flips the flag. By
-- extension SecretWhenAnchoringSecret means "secret when the OBJECT has secrets",
-- which takes GetStringWidth / GetUnboundedStringWidth / GetStringHeight /
-- GetWrappedWidth / GetNumLines / IsTruncated / GetWidth / GetHeight with it.
-- Measured live: fs:IsAnchoringSecret() true while its parent frame reads false.
--
-- There is no anchor-based escape hatch, because anchoring was never the
-- mechanism -- the UIParent-anchored ruler below goes secret the same way. A
-- caller that may be handed a secret string must pass opts.fallbackSize and use
-- the engine's own wrapping and ellipsis, both of which still work fine on text
-- nobody can read.
--
-- The gate cannot be folded into a pcall around the measurement: reading a
-- dimension on a dirty layout forces a layout flush that fires OnSizeChanged as
-- a side effect, so the error surfaces in the callback rather than in the call.
--
-- Addon-owned FontStrings only: "blizzard" mode writes baseLineHeight/minLineHeight
-- onto the FontString's Lua table, which would taint a Blizzard-owned one.
--
-- opts: width, height   -- box size; omit to read them off a two-point-anchored fs
--       maxLines        -- line budget, further clamped by height
--       maxSize         -- the ideal size, used when the text already fits
--       minSize         -- floor; below this "..." truncation is accepted
--       mode            -- "font" (step point size) | "scale" (SetTextScale)
--                          | "blizzard" (Blizzard's ScaleTextToFit verbatim)
--       face, style     -- as passed to addon.ApplyFontStyle
--       wordWrap, nonSpaceWrap
--       fallbackSize    -- size to apply when the geometry cannot be read at all
--                          (secret text, unsettled layout). Defaults to maxSize.
--
-- returns { size, scale, lines, maxLines, truncated, iterations, measurable,
--           fallback, reason }
--   measurable == false means the geometry could not be read. size/maxLines are
--   still populated -- from fallbackSize -- and have still been APPLIED to the
--   FontString, so the caller always knows what is on screen. fallback == true
--   marks that case explicitly: never treat an unmeasured fit as a measured one.

local FIT_DEFAULT_MIN_SIZE = 8

local function fitSafeNumber(obj, method, ...)
    local fn = obj and obj[method]
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, obj, ...)
    if not ok then return nil end
    if type(v) ~= "number" then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function fitSafeBool(obj, method, ...)
    local fn = obj and obj[method]
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, obj, ...)
    if not ok then return nil end
    if type(v) ~= "boolean" then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

addon.FitSafeNumber = fitSafeNumber
addon.FitSafeBool = fitSafeBool

function addon.FitTextToBox(fs, opts)
    opts = opts or {}
    local result = { scale = 1, iterations = 0, measurable = false }

    if not fs or type(fs.SetFont) ~= "function" then
        result.reason = "not a FontString"
        return result
    end

    local face    = opts.face or (select(1, _G.GameFontNormal:GetFont()))
    local style   = opts.style or ""
    local mode    = opts.mode or "font"
    local maxSize = tonumber(opts.maxSize) or 14
    local minSize = math.max(1, tonumber(opts.minSize) or FIT_DEFAULT_MIN_SIZE)
    if minSize > maxSize then minSize = maxSize end
    local maxLines = math.max(1, math.floor(tonumber(opts.maxLines) or 1))
    local fallbackSize = tonumber(opts.fallbackSize) or maxSize

    local function applyLayout()
        if fs.SetWordWrap then pcall(fs.SetWordWrap, fs, opts.wordWrap ~= false) end
        if fs.SetNonSpaceWrap then pcall(fs.SetNonSpaceWrap, fs, opts.nonSpaceWrap == true) end
        if fs.SetMaxLines then pcall(fs.SetMaxLines, fs, maxLines) end
        if opts.width then pcall(fs.SetWidth, fs, opts.width) end
        if opts.height then pcall(fs.SetHeight, fs, opts.height) end
        -- Reset to the unscaled base font before measuring anything.
        if fs.SetTextScale then pcall(fs.SetTextScale, fs, 1) end
        -- Smooth scaling stops line height snapping to whole numbers while scaled.
        if fs.SetSmoothScaling then pcall(fs.SetSmoothScaling, fs, mode ~= "font") end
    end

    -- Every exit that could not measure lands here. Leaving the FontString at
    -- whatever font it happened to be carrying is how a creation-default size and a
    -- caller's max size both end up on screen looking like deliberate behaviour --
    -- the fit reads as "worked" because something rendered. Apply a defined size
    -- instead and say so, so a bail is visible as a bail.
    local function bail(reason)
        result.reason = reason
        result.measurable = false
        result.fallback = true
        applyLayout()
        addon.ApplyFontStyle(fs, face, fallbackSize, style)
        result.size = fallbackSize
        result.scale = 1
        result.maxLines = maxLines
        return result
    end

    -- Gate 1: the FontString holds a secret aspect. Proceed only on a definitive
    -- false. A secret string poisons its own FontString via SetText, so this fires
    -- for every restricted unit name -- see the header above.
    if type(fs.IsAnchoringSecret) == "function" then
        local objSecret = fitSafeBool(fs, "IsAnchoringSecret")
        if objSecret ~= false then
            -- Distinguish "will never be measurable" from "not settled yet". Callers
            -- that retry an unsettled layout must not burn frames retrying this one.
            result.secretText = (objSecret == true) or nil
            return bail((objSecret == nil)
                and "IsAnchoringSecret unreadable"
                or "object holds a secret aspect (text is secret)")
        end
    end

    applyLayout()
    addon.ApplyFontStyle(fs, face, maxSize, style)
    result.maxLines = maxLines

    local boxW = tonumber(opts.width) or fitSafeNumber(fs, "GetWidth")
    local boxH = tonumber(opts.height) or fitSafeNumber(fs, "GetHeight")
    if not boxW or not boxH or boxW <= 0 or boxH <= 0 then
        return bail("box dimensions unreadable")
    end

    local unbounded = fitSafeNumber(fs, "GetUnboundedStringWidth")
    if not unbounded then
        return bail("GetUnboundedStringWidth unreadable")
    end

    -- Past this point the geometry is readable, which is the whole question.
    result.measurable = true

    -- Control case: run Blizzard's own shrink-to-fit verbatim.
    if mode == "blizzard" then
        local mixin = _G.AutoScalingFontStringMixin
        if not mixin or type(mixin.ScaleTextToFit) ~= "function" then
            return bail("AutoScalingFontStringMixin unavailable")
        end
        -- Blizzard's floor is a line height, not a point size. Convert minSize so
        -- all three modes bottom out at the same visual size.
        addon.ApplyFontStyle(fs, face, minSize, style)
        local minLineHeight = fitSafeNumber(fs, "GetLineHeight") or minSize
        addon.ApplyFontStyle(fs, face, maxSize, style)
        fs.baseLineHeight = nil -- force a re-cache against the current base font
        fs.minLineHeight = minLineHeight
        local ok, err = pcall(mixin.ScaleTextToFit, fs)
        if not ok then
            return bail("ScaleTextToFit error: " .. tostring(err))
        end
        result.scale = fitSafeNumber(fs, "GetTextScale") or 1
        result.size = maxSize * result.scale
        result.truncated = fitSafeBool(fs, "IsTruncated")
        result.lines = fitSafeNumber(fs, "GetNumLines")
        return result
    end

    local function applyCandidate(size)
        if mode == "scale" then
            pcall(fs.SetTextScale, fs, size / maxSize)
        else
            addon.ApplyFontStyle(fs, face, size, style)
        end
    end

    -- Analytic first guess. Unbounded width scales linearly with point size, so the
    -- largest size that could fit across maxLines lines is
    --   maxSize * boxW * maxLines / unboundedAtMaxSize
    -- That is an upper bound (wrapping wastes space at line ends), so walk down from
    -- it. In practice this lands within a couple of steps of the answer.
    --
    -- A zero unbounded width means either genuinely empty text or a layout that has
    -- not settled since the last SetText. Never accept maxSize on the strength of it:
    -- start there and let the descent loop decide. Empty text is never truncated so it
    -- exits on the first iteration, while a stale zero recovers instead of silently
    -- rendering at full size and spilling out of the box.
    local size
    if unbounded > 0 then
        size = math.floor(maxSize * boxW * maxLines / unbounded)
    else
        size = maxSize
        result.zeroWidth = true
    end
    if size > maxSize then size = maxSize end
    if size < minSize then size = minSize end

    while size >= minSize do
        result.iterations = result.iterations + 1
        applyCandidate(size)

        -- maxLines and a fixed height can disagree: n lines may not physically fit,
        -- in which case IsTruncated() would report false while text spills out of the
        -- box. Clamp the budget to what this size can show.
        local lineHeight = fitSafeNumber(fs, "GetLineHeight")
        if lineHeight and lineHeight > 0 and fs.SetMaxLines then
            local spacing = fitSafeNumber(fs, "GetSpacing") or 0
            local allowed = math.floor(boxH / (lineHeight + spacing))
            if allowed < 1 then allowed = 1 end
            local clamped = (allowed < maxLines) and allowed or maxLines
            pcall(fs.SetMaxLines, fs, clamped)
            -- Report the clamp rather than leaving callers to read it back off the
            -- FontString: GetMaxLines is plain today, but a caller replaying this fit
            -- onto copies should be told what was applied, not have to ask.
            result.maxLines = clamped
        end

        local truncated = fitSafeBool(fs, "IsTruncated")
        if truncated == nil then
            -- The descent validated nothing, so the size it happens to be sitting at
            -- is not a fit. Drop to the declared fallback like any other bail.
            return bail("IsTruncated unreadable")
        end
        if not truncated then
            result.truncated = false
            break
        end
        if size == minSize then
            -- Hit the floor: accept ellipsis truncation.
            result.truncated = true
            break
        end
        size = size - 1
    end

    result.size = size
    result.scale = (mode == "scale") and (size / maxSize) or 1
    result.lines = fitSafeNumber(fs, "GetNumLines")
    return result
end

--------------------------------------------------------------------------------
-- Off-Frame Text Measurement Ruler
--------------------------------------------------------------------------------
-- Measure a string's natural width without ever touching the FontString that will
-- display it.
--
-- The geometry getters are annotated SecretWhenAnchoringSecret (see the header on
-- FitTextToBox above), so measuring a FontString anchored into a Blizzard frame
-- returns a secret on exactly the tainted frames that matter. Anchoring is
-- secret-safe for *writing* geometry, never for *reading* it, and there is no
-- anchor-based escape hatch -- a proxy region anchored to the same frame inherits
-- the same secret chain.
--
-- The ruler sidesteps this entirely: it is parented and anchored only to UIParent,
-- a chain that can never be secret. SetText is AllowedWhenTainted, so a secret
-- string can be poured in and measured even though its content is unreadable.
--
-- Held permanently at SetTextScale(1), so GetUnboundedStringWidth() is the raw
-- natural width with no normalisation needed. That getter is scale-INCLUSIVE --
-- Blizzard's AutoScalingFontStringMixin divides by GetTextScale() precisely
-- because of that (Blizzard_SharedXML/SecureUtil.lua).

local measureRuler

local function ensureMeasureRuler()
    if measureRuler then return measureRuler end

    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(1, 1)
    holder:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    holder:Hide()

    local fs = holder:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER", holder, "CENTER", 0, 0)  -- single point => natural width
    fs:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    if fs.SetWidth then fs:SetWidth(0) end
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetTextScale then fs:SetTextScale(1) end

    -- Warm the layout once: a never-laid-out FontString under-reports its width.
    fs:SetText("The quick brown fox 0123456789")
    pcall(fs.GetUnboundedStringWidth, fs)
    fs:SetText("")

    measureRuler = fs
    return fs
end

-- Natural (unwrapped, untruncated, unscaled) pixel width of `text` rendered in the
-- given face/size/style. `text` may be a secret string. Returns nil when the
-- geometry could not be read, in which case the caller must not shrink anything.
function addon.MeasureTextWidth(text, face, size, style)
    -- A secret string never reaches the ruler.
    --
    -- SetText is AllowedWhenTainted, so pouring one in would SUCCEED -- and stamp
    -- Enum.SecretAspect.Text onto this FontString, which every caller in the addon
    -- shares. From then on the IsAnchoringSecret gate below answers true, this
    -- function returns nil forever, and every shrink-to-fit in Scoot silently stops
    -- working. No error, no stack, and the damage outlives the caller that caused
    -- it. nil is already the documented "unmeasurable, do not shrink" answer, so
    -- refusing here costs callers nothing.
    if issecretvalue and issecretvalue(text) then return nil end

    local fs = ensureMeasureRuler()
    if not fs then return nil end

    -- Same gate as FitTextToBox. Always false here (UIParent chain), so this is an
    -- assertion rather than a real branch -- but it documents why the ruler exists.
    if type(fs.IsAnchoringSecret) == "function" then
        if fitSafeBool(fs, "IsAnchoringSecret") ~= false then return nil end
    end

    addon.ApplyFontStyle(fs, face, size, addon.FontStyles.MetricStyle(style))
    if not pcall(fs.SetText, fs, text) then return nil end
    local w = fitSafeNumber(fs, "GetUnboundedStringWidth")

    -- ClearText, not SetText(""): only ClearText releases the Text aspect.
    -- SetText("") clears the glyphs and leaves the aspect in place, which is the
    -- difference between a reusable ruler and a permanently poisoned one. Belt and
    -- braces given the guard above -- this ruler is shared, so it exits clean.
    if fs.ClearText then
        pcall(fs.ClearText, fs)
    else
        pcall(fs.SetText, fs, "")
    end

    if not w or w <= 0 then return nil end
    return w
end

--------------------------------------------------------------------------------
-- Line Discovery
--------------------------------------------------------------------------------
-- Recover where a wrapped FontString broke its lines, so each line can be
-- treated independently (per-line color ramps, per-line alignment, etc.).
--
-- Primary path asks the engine: CalculateScreenAreaFromCharacterSpan returns one
-- uiBoundsRect { left, bottom, width, height } per wrapped row that a character span
-- covers. Blizzard uses it for selection highlighting in ScrollingMessageFrame for
-- exactly that reason. WoW's line-breaking is never reimplemented here, only asked for.
--
-- It is gated on RequiresFontStringTextAccess, which fails for tainted callers once
-- the FontString carries the Text secret aspect. Pushing one secret name through
-- SetText stamps that aspect on, so run this on plain text only and call ClearText()
-- between targets. WrapTextGreedy below is the fallback that never needs the engine.

local FIT_MAX_DISCOVERY_CHARS = 200

-- Byte offsets of each UTF-8 character start, plus each one's byte length.
local function utf8Offsets(s)
    local offsets, i, n = {}, 1, #s
    while i <= n do
        local b = s:byte(i)
        local len = 1
        if b >= 240 then len = 4
        elseif b >= 224 then len = 3
        elseif b >= 192 then len = 2 end
        if i + len - 1 > n then len = 1 end
        offsets[#offsets + 1] = { first = i, last = i + len - 1 }
        i = i + len
    end
    return offsets
end

local function spanRect(fs, first, last)
    local fn = fs.CalculateScreenAreaFromCharacterSpan
    if type(fn) ~= "function" then return nil end
    local ok, areas = pcall(fn, fs, first, last)
    if not ok or type(areas) ~= "table" then return nil end
    if issecretvalue and issecretvalue(areas) then return nil end
    return areas
end

-- Returns an array of { text, first, last, left, width } in reading order, or nil
-- when the lines could not be determined (secret text, secret anchoring, or the
-- span API returning nothing). `first`/`last` are byte offsets into `plainText`.
function addon.DiscoverTextLines(fs, plainText)
    if not fs or type(plainText) ~= "string" or plainText == "" then return nil end
    if issecretvalue and issecretvalue(plainText) then return nil end

    -- Same gate as FitTextToBox: the span API is SecretWhenAnchoringSecret too.
    if type(fs.IsAnchoringSecret) == "function" then
        if fitSafeBool(fs, "IsAnchoringSecret") ~= false then return nil end
    end

    local areas = spanRect(fs, 1, #plainText)
    if not areas or #areas == 0 then return nil end

    local function row(first, last, rect)
        local text = plainText:sub(first, last):match("^%s*(.-)%s*$")
        if text == "" then return nil end
        return {
            text  = text,
            first = first,
            last  = last,
            left  = rect and rect.left,
            width = rect and rect.width,
        }
    end

    -- Overwhelmingly the common case, and it costs exactly one engine call.
    if #areas == 1 then
        local only = row(1, #plainText, areas[1])
        return only and { only } or nil
    end

    local chars = utf8Offsets(plainText)
    if #chars > FIT_MAX_DISCOVERY_CHARS then return nil end

    -- Bucket every character onto the row whose baseline it sits closest to.
    -- Float coordinates, so never compare bottoms with ==.
    local buckets = {}
    for idx = 1, #areas do buckets[idx] = { rect = areas[idx] } end

    for _, c in ipairs(chars) do
        local r = spanRect(fs, c.first, c.last)
        local bottom = r and r[1] and r[1].bottom
        if type(bottom) == "number" and not (issecretvalue and issecretvalue(bottom)) then
            local best, bestDist
            for idx = 1, #areas do
                local ab = areas[idx].bottom
                if type(ab) == "number" then
                    local d = math.abs(ab - bottom)
                    if not bestDist or d < bestDist then best, bestDist = idx, d end
                end
            end
            local b = best and buckets[best]
            if b then
                if not b.first or c.first < b.first then b.first = c.first end
                if not b.last or c.last > b.last then b.last = c.last end
            end
        end
    end

    local lines = {}
    for idx = 1, #buckets do
        local b = buckets[idx]
        if b.first and b.last then
            local ln = row(b.first, b.last, b.rect)
            if ln then lines[#lines + 1] = ln end
        end
    end
    -- The engine already reported how many rows there are. If bucketing recovered a
    -- different number, the per-character probe disagreed with the row probe and the
    -- breaks can't be trusted -- report failure rather than a plausible wrong answer.
    if #lines ~= #areas then return nil end

    -- Reading order by byte offset -- independent of the coordinate convention.
    table.sort(lines, function(a, b) return a.first < b.first end)

    -- Coverage invariant: every character has to land on some line. A per-character
    -- probe that returns nothing for most characters still yields plausible-looking
    -- buckets -- one stray hit makes a whole line read as "C" instead of "Custodian"
    -- -- and nothing downstream can tell that apart from a genuinely short line. So
    -- rebuild the string from the lines and require it back, whitespace-normalised.
    local rebuilt = {}
    for i = 1, #lines do rebuilt[i] = lines[i].text end
    local normalized = plainText:gsub("%s+", " "):match("^%s*(.-)%s*$")
    if table.concat(rebuilt, " ") ~= normalized then return nil end

    return lines
end

-- Fallback wrap: greedy fill at spaces, measured on the off-frame ruler. Never
-- touches the display FontString and never needs the span API, so this is the
-- version to rely on unconditionally. Returns the same array shape as
-- DiscoverTextLines (no `left`), or nil.
--
-- opts: width (required), face, size, style
function addon.WrapTextGreedy(text, opts)
    opts = opts or {}
    if type(text) ~= "string" or text == "" then return nil end
    if issecretvalue and issecretvalue(text) then return nil end

    local width = tonumber(opts.width)
    if not width or width <= 0 then return nil end

    local face  = opts.face or (select(1, _G.GameFontNormal:GetFont()))
    local size  = tonumber(opts.size) or 12
    local style = opts.style or ""

    -- Measure through MeasureTextWidth rather than GetUnboundedStringWidthForText.
    -- That newer getter looks ideal (no SetText round trip) but has zero callers in
    -- Blizzard's source, and more importantly a raw getter can hand back 0 on a
    -- layout that has not settled. Zero is a number, so it sails past a type check
    -- and reads as "this line fits" -- which silently concatenates the entire name
    -- onto one line. MeasureTextWidth is the production-proven path and already
    -- rejects <= 0.
    local function widthOf(s)
        return addon.MeasureTextWidth(s, face, size, style)
    end

    local lines = {}
    local cur, curFirst, curLast

    for s, word in text:gmatch("()(%S+)") do
        local wordLast = s + #word - 1
        if not cur then
            cur, curFirst, curLast = word, s, wordLast
        else
            local candidate = cur .. " " .. word
            local w = widthOf(candidate)
            -- Unmeasurable: bail out entirely. Treating nil as "it fits" quietly
            -- concatenates the whole name onto one line, which then renders
            -- ellipsized -- worse than admitting the name could not be wrapped.
            if not w then return nil end
            if w <= width then
                cur, curLast = candidate, wordLast
            else
                lines[#lines + 1] = { text = cur, first = curFirst, last = curLast }
                cur, curFirst, curLast = word, s, wordLast
            end
        end
    end
    if cur then lines[#lines + 1] = { text = cur, first = curFirst, last = curLast } end
    if #lines == 0 then return nil end

    -- A single word wider than the box has nowhere to break; flag it so callers can
    -- report the "shrink to the floor, then ellipsize" case rather than guess.
    for _, ln in ipairs(lines) do
        ln.width = widthOf(ln.text)
        if ln.width and ln.width > width then ln.overflow = true end
    end

    -- No ruler cleanup needed: MeasureTextWidth clears it after every call.
    return lines
end

--------------------------------------------------------------------------------
-- Custom Font Picker Popup (Tabbed 3-Column Scrollable Grid)
--------------------------------------------------------------------------------

local fontPickerFrame = nil
local fontPickerSetting = nil
local fontPickerCallback = nil
local fontPickerAnchor = nil
local selectedFontTab = "default"

-- Grid layout constants
local FONTS_PER_ROW = 3
local FONT_BUTTON_WIDTH = 160
local FONT_BUTTON_HEIGHT = 26
local FONT_BUTTON_SPACING = 4
local PICKER_PADDING = 12
local PICKER_TITLE_HEIGHT = 30
local TAB_WIDTH = 90
local TAB_HEIGHT = 32

-- Scoot theme colors
local BRAND_R, BRAND_G, BRAND_B = 0.20, 0.90, 0.30

--------------------------------------------------------------------------------
-- Font Category Tables
--------------------------------------------------------------------------------

local DEFAULT_FONTS = { "FRIZQT__", "ARIALN", "MORPHEUS", "SKURRI" }

local GOOGLE_FONTS = {
    -- Dosis
    "DOSIS_REG", "DOSIS_BOLD", "DOSIS_LIGHT", "DOSIS_MED",
    -- Exo 2
    "EXO2_REG", "EXO2_BLACK", "EXO2_BOLD", "EXO2_LIGHT", "EXO2_MED",
    -- Fira Sans
    "FIRASANS_REG", "FIRASANS_BLACK", "FIRASANS_BOLD", "FIRASANS_LIGHT", "FIRASANS_MED",
    -- Lato
    "LATO_REG", "LATO_BLACK", "LATO_BOLD", "LATO_LIGHT",
    -- Montserrat
    "MONTSERRAT_REG", "MONTSERRAT_BLACK", "MONTSERRAT_BOLD", "MONTSERRAT_LIGHT", "MONTSERRAT_MED",
    -- Mukta
    "MUKTA_REG", "MUKTA_BOLD", "MUKTA_LIGHT", "MUKTA_MED",
    -- Poppins
    "POPPINS_REG", "POPPINS_BLACK", "POPPINS_BOLD", "POPPINS_LIGHT", "POPPINS_MED",
    -- Roboto
    "ROBOTO_REG", "ROBOTO_BLACK", "ROBOTO_LIGHT", "ROBOTO_MED",
    -- Roboto Condensed
    "ROBOTO_COND_REG", "ROBOTO_COND_BLACK", "ROBOTO_COND_BOLD", "ROBOTO_COND_LIGHT", "ROBOTO_COND_MED",
    -- Roboto SemiCondensed
    "ROBOTO_SEMICOND_REG", "ROBOTO_SEMICOND_BLACK", "ROBOTO_SEMICOND_BOLD", "ROBOTO_SEMICOND_LIGHT", "ROBOTO_SEMICOND_MED",
}

local PIXEL_FONTS = {
    "FONT_04B30",
    "DOGICA_REG", "DOGICA_BOLD", "DOGICA_PIXEL", "DOGICA_PIXELBOLD",
    "MINECRAFT",
    "PIXELOP_REG", "PIXELOP_BOLD", "PIXELOP_MONO", "PIXELOP_MONOBOLD",
    "PIXELOP_SC", "PIXELOP_SCBOLD",
    "PIXELLARI", "PRESS_START_2P", "RAINYHEARTS",
}

-- Heavy display faces (the font picker's "Display" tab).
local DISPLAY_FONTS = {
    "ANTON_WIDE_150", "RUBIK_MONO_ONE", "TOMORROW_BLACK", "BUNGEE",
}

local FONT_TABS = {
    { key = "default", label = "Default", fonts = DEFAULT_FONTS },
    { key = "google",  label = "Google",  fonts = GOOGLE_FONTS },
    { key = "pixel",   label = "Pixel",   fonts = PIXEL_FONTS },
    { key = "display", label = "Display", fonts = DISPLAY_FONTS },
}

-- Build a reverse lookup: font key -> tab key
local fontCategoryMap = {}
for _, tabData in ipairs(FONT_TABS) do
    for _, fontKey in ipairs(tabData.fonts) do
        fontCategoryMap[fontKey] = tabData.key
    end
end

local function GetCategoryForFont(key)
    if addon.IsLSMKey and addon.IsLSMKey(key) then return "shared" end
    return fontCategoryMap[key] or "default"
end

local function CloseFontPicker()
    if fontPickerFrame then
        fontPickerFrame:Hide()
    end
    fontPickerSetting = nil
    fontPickerCallback = nil
    fontPickerAnchor = nil
end

local function CreateFontPicker()
    if fontPickerFrame then return fontPickerFrame end

    local Theme = addon.UI and addon.UI.Theme
    local accentR, accentG, accentB = BRAND_R, BRAND_G, BRAND_B
    if Theme and Theme.GetAccentColor then
        accentR, accentG, accentB = Theme:GetAccentColor()
    end

    -- Calculate content area width (right of tabs)
    local contentWidth = (FONT_BUTTON_WIDTH * FONTS_PER_ROW) + (FONT_BUTTON_SPACING * (FONTS_PER_ROW - 1)) + (PICKER_PADDING * 2)
    local totalWidth = TAB_WIDTH + contentWidth + 24 -- tabs + content + scrollbar
    local popupHeight = 420

    local frame = CreateFrame("Frame", "ScootFontPickerFrame", UIParent)
    frame:SetSize(totalWidth, popupHeight)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- TUI-style background
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.04, 0.06, 0.96)
    frame._bg = bg

    -- TUI-style border (accent color)
    local borderWidth = 1
    local borders = {}

    local topBorder = frame:CreateTexture(nil, "BORDER", nil, -1)
    topBorder:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    topBorder:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    topBorder:SetHeight(borderWidth)
    topBorder:SetColorTexture(accentR, accentG, accentB, 0.8)
    borders.TOP = topBorder

    local bottomBorder = frame:CreateTexture(nil, "BORDER", nil, -1)
    bottomBorder:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottomBorder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bottomBorder:SetHeight(borderWidth)
    bottomBorder:SetColorTexture(accentR, accentG, accentB, 0.8)
    borders.BOTTOM = bottomBorder

    local leftBorder = frame:CreateTexture(nil, "BORDER", nil, -1)
    leftBorder:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -borderWidth)
    leftBorder:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, borderWidth)
    leftBorder:SetWidth(borderWidth)
    leftBorder:SetColorTexture(accentR, accentG, accentB, 0.8)
    borders.LEFT = leftBorder

    local rightBorder = frame:CreateTexture(nil, "BORDER", nil, -1)
    rightBorder:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -borderWidth)
    rightBorder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, borderWidth)
    rightBorder:SetWidth(borderWidth)
    rightBorder:SetColorTexture(accentR, accentG, accentB, 0.8)
    borders.RIGHT = rightBorder

    frame._borders = borders

    -- Title
    local titleFont = (Theme and Theme.GetFont and Theme:GetFont("HEADER")) or "Fonts\\FRIZQT__.TTF"
    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetFont(titleFont, 14, "")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", PICKER_PADDING, -10)
    title:SetText("Select Font")
    title:SetTextColor(1, 1, 1, 1)
    frame.Title = title

    -- Close button (X)
    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
    closeBtn:EnableMouse(true)
    closeBtn:RegisterForClicks("AnyUp")

    local closeBtnBg = closeBtn:CreateTexture(nil, "BACKGROUND", nil, -7)
    closeBtnBg:SetAllPoints()
    closeBtnBg:SetColorTexture(accentR, accentG, accentB, 1)
    closeBtnBg:Hide()
    closeBtn._bg = closeBtnBg

    local closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY")
    closeBtnText:SetFont(titleFont, 14, "")
    closeBtnText:SetPoint("CENTER", 0, 0)
    closeBtnText:SetText("X")
    closeBtnText:SetTextColor(accentR, accentG, accentB, 1)
    closeBtn._text = closeBtnText

    closeBtn:SetScript("OnEnter", function(self)
        self._bg:Show()
        self._text:SetTextColor(0, 0, 0, 1)
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self._bg:Hide()
        self._text:SetTextColor(accentR, accentG, accentB, 1)
    end)
    closeBtn:SetScript("OnClick", CloseFontPicker)
    frame.CloseButton = closeBtn

    -- Tab container (left side)
    local tabContainer = CreateFrame("Frame", nil, frame)
    tabContainer:SetSize(TAB_WIDTH, popupHeight - PICKER_TITLE_HEIGHT - PICKER_PADDING * 2)
    tabContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", PICKER_PADDING, -(PICKER_TITLE_HEIGHT + 4))
    frame.TabContainer = tabContainer

    -- Vertical separator between tabs and content
    local tabSep = frame:CreateTexture(nil, "BORDER", nil, 0)
    tabSep:SetWidth(1)
    tabSep:SetPoint("TOPLEFT", tabContainer, "TOPRIGHT", 4, 0)
    tabSep:SetPoint("BOTTOMLEFT", tabContainer, "BOTTOMRIGHT", 4, 0)
    tabSep:SetColorTexture(accentR, accentG, accentB, 0.4)
    frame._tabSep = tabSep

    -- Tab buttons (managed pool, rebuilt on each Show via UpdateTabs)
    frame.TabButtons = {}
    frame._tabLabelFont = (Theme and Theme.GetFont and Theme:GetFont("LABEL")) or "Fonts\\FRIZQT__.TTF"

    function frame:UpdateTabs()
        local tabs = self._workingTabs or FONT_TABS
        local tc = self.TabContainer
        local lf = self._tabLabelFont
        local ar, ag, ab = self._accentR, self._accentG, self._accentB

        for i, tabData in ipairs(tabs) do
            local tabBtn = self.TabButtons[i]
            if not tabBtn then
                tabBtn = CreateFrame("Button", nil, tc)
                tabBtn:SetSize(TAB_WIDTH, TAB_HEIGHT)
                tabBtn:EnableMouse(true)
                tabBtn:RegisterForClicks("AnyUp")

                local tabBg = tabBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
                tabBg:SetAllPoints()
                tabBg:SetColorTexture(0.06, 0.06, 0.08, 1)
                tabBtn._bg = tabBg

                local indicator = tabBtn:CreateTexture(nil, "OVERLAY", nil, 1)
                indicator:SetSize(2, TAB_HEIGHT)
                indicator:SetPoint("LEFT", tabBtn, "LEFT", 0, 0)
                indicator:SetColorTexture(ar, ag, ab, 1)
                indicator:Hide()
                tabBtn._indicator = indicator

                local tabLabel = tabBtn:CreateFontString(nil, "OVERLAY")
                tabLabel:SetFont(lf, 11, "")
                tabLabel:SetPoint("CENTER", tabBtn, "CENTER", 2, 0)
                tabLabel:SetTextColor(0.6, 0.6, 0.6, 1)
                tabBtn._label = tabLabel

                tabBtn:SetScript("OnEnter", function(self)
                    if selectedFontTab ~= self._key then
                        self._bg:SetColorTexture(ar, ag, ab, 0.15)
                    end
                end)
                tabBtn:SetScript("OnLeave", function(self)
                    if selectedFontTab ~= self._key then
                        self._bg:SetColorTexture(0.06, 0.06, 0.08, 1)
                    end
                end)
                tabBtn:SetScript("OnClick", function(self)
                    if selectedFontTab ~= self._key then
                        selectedFontTab = self._key
                        frame:UpdateTabVisuals()
                        frame:PopulateContent()
                        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
                    end
                end)

                self.TabButtons[i] = tabBtn
            end

            tabBtn._key = tabData.key
            tabBtn._label:SetText(tabData.label)
            tabBtn:ClearAllPoints()
            tabBtn:SetPoint("TOPLEFT", tc, "TOPLEFT", 0, -((i - 1) * TAB_HEIGHT))
            tabBtn:Show()
        end

        -- Hide extra buttons from previous Show
        for i = #tabs + 1, #self.TabButtons do
            self.TabButtons[i]:Hide()
        end
    end

    -- Content area (scroll frame, right of tabs)
    local scrollFrame = CreateFrame("ScrollFrame", "ScootFontPickerScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", tabContainer, "TOPRIGHT", 12, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(PICKER_PADDING + 20), PICKER_PADDING)
    frame.ScrollFrame = scrollFrame

    -- Style the scrollbar
    local scrollBar = scrollFrame.ScrollBar or _G[scrollFrame:GetName() .. "ScrollBar"]
    if scrollBar then
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 6, -16)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 6, 16)

        if scrollBar.Background then scrollBar.Background:Hide() end
        if scrollBar.Track then
            if scrollBar.Track.Begin then scrollBar.Track.Begin:Hide() end
            if scrollBar.Track.End then scrollBar.Track.End:Hide() end
            if scrollBar.Track.Middle then scrollBar.Track.Middle:Hide() end
        end

        local trackBg = scrollBar:CreateTexture(nil, "BACKGROUND", nil, -8)
        trackBg:SetPoint("TOPLEFT", 4, 0)
        trackBg:SetPoint("BOTTOMRIGHT", -4, 0)
        trackBg:SetColorTexture(accentR, accentG, accentB, 0.15)
        scrollBar._trackBg = trackBg

        local thumb = scrollBar.ThumbTexture or scrollBar:GetThumbTexture()
        if thumb then
            thumb:SetColorTexture(accentR, accentG, accentB, 0.6)
            thumb:SetSize(8, 40)
        end

        local upBtn = scrollBar.ScrollUpButton or scrollBar.Back or _G[scrollBar:GetName() .. "ScrollUpButton"]
        local downBtn = scrollBar.ScrollDownButton or scrollBar.Forward or _G[scrollBar:GetName() .. "ScrollDownButton"]
        if upBtn then upBtn:SetAlpha(0) upBtn:EnableMouse(false) end
        if downBtn then downBtn:SetAlpha(0) downBtn:EnableMouse(false) end

        frame._scrollBar = scrollBar
    end

    -- Content frame (scroll child)
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(contentWidth - PICKER_PADDING, 100)
    scrollFrame:SetScrollChild(content)
    frame.Content = content

    -- Button pool for font options
    frame.Buttons = {}

    -- Store accent colors
    frame._accentR = accentR
    frame._accentG = accentG
    frame._accentB = accentB

    -- Update tab visuals
    function frame:UpdateTabVisuals()
        for _, tabBtn in ipairs(self.TabButtons) do
            local isSelected = (selectedFontTab == tabBtn._key)
            if isSelected then
                tabBtn._indicator:Show()
                tabBtn._label:SetTextColor(1, 1, 1, 1)
                tabBtn._bg:SetColorTexture(self._accentR, self._accentG, self._accentB, 0.2)
            else
                tabBtn._indicator:Hide()
                tabBtn._label:SetTextColor(0.6, 0.6, 0.6, 1)
                tabBtn._bg:SetColorTexture(0.06, 0.06, 0.08, 1)
            end
        end
    end

    -- Populate content for selected tab
    function frame:PopulateContent()
        local currentTab = nil
        for _, tabData in ipairs(self._workingTabs or FONT_TABS) do
            if tabData.key == selectedFontTab then
                currentTab = tabData
                break
            end
        end
        if not currentTab then return end

        local fonts = currentTab.fonts
        local contentFrame = self.Content
        local displayNames = addon.FontDisplayNames or {}
        local defaultFont = select(1, _G.GameFontNormal:GetFont()) or "Fonts\\FRIZQT__.TTF"

        local accentR = self._accentR or BRAND_R
        local accentG = self._accentG or BRAND_G
        local accentB = self._accentB or BRAND_B

        -- Get current value
        local currentValue = nil
        if fontPickerSetting and fontPickerSetting.GetValue then
            currentValue = fontPickerSetting:GetValue()
        end

        -- Calculate content height
        local numRows = math.ceil(#fonts / FONTS_PER_ROW)
        local contentHeight = (numRows * FONT_BUTTON_HEIGHT) + ((numRows - 1) * FONT_BUTTON_SPACING) + PICKER_PADDING
        contentFrame:SetHeight(contentHeight)

        -- Show/hide scrollbar based on content size
        local scrollFrame = self.ScrollFrame
        local scrollBar = self._scrollBar
        if scrollBar and scrollFrame then
            local visibleHeight = scrollFrame:GetHeight()
            if contentHeight > visibleHeight then
                scrollBar:Show()
                if scrollBar._trackBg then scrollBar._trackBg:Show() end
            else
                scrollBar:Hide()
                if scrollBar._trackBg then scrollBar._trackBg:Hide() end
            end
        end

        -- Hide all existing buttons
        for _, btn in ipairs(self.Buttons) do
            btn:Hide()
        end

        -- Create/reuse buttons for each font
        for i, fontKey in ipairs(fonts) do
            local btn = self.Buttons[i]
            if not btn then
                btn = CreateFrame("Button", nil, contentFrame)
                btn:SetSize(FONT_BUTTON_WIDTH, FONT_BUTTON_HEIGHT)
                btn:EnableMouse(true)
                btn:RegisterForClicks("AnyUp")

                local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                label:SetPoint("LEFT", btn, "LEFT", 4, 0)
                label:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
                label:SetJustifyH("LEFT")
                label:SetWordWrap(false)
                btn.Label = label

                self.Buttons[i] = btn
            end

            -- Position in grid
            local col = (i - 1) % FONTS_PER_ROW
            local row = math.floor((i - 1) / FONTS_PER_ROW)
            local x = col * (FONT_BUTTON_WIDTH + FONT_BUTTON_SPACING)
            local y = -(row * (FONT_BUTTON_HEIGHT + FONT_BUTTON_SPACING))
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", x, y)

            -- Set font preview (render label in that font)
            local fontFace = addon.ResolveFontFace(fontKey)
            local fontSet = false
            if fontFace then
                fontSet = pcall(btn.Label.SetFont, btn.Label, fontFace, 12, "")
            end
            if not fontSet then
                pcall(btn.Label.SetFont, btn.Label, defaultFont, 12, "")
            end

            -- Set display name
            local displayText
            if addon.IsLSMKey and addon.IsLSMKey(fontKey) then
                displayText = addon.LSMKeyToName(fontKey)
            else
                displayText = displayNames[fontKey] or fontKey
            end
            btn.Label:SetText(displayText)

            -- Selection state
            local isSelected = (currentValue == fontKey)
            btn._fontValue = fontKey
            btn._isSelected = isSelected
            btn._accentR = accentR
            btn._accentG = accentG
            btn._accentB = accentB

            if isSelected then
                btn.Label:SetTextColor(accentR, accentG, accentB, 1)
            else
                btn.Label:SetTextColor(1, 1, 1, 0.9)
            end

            -- Click handler
            btn:SetScript("OnClick", function(self)
                local value = self._fontValue
                if fontPickerSetting and fontPickerSetting.SetValue then
                    fontPickerSetting:SetValue(value)
                end
                if fontPickerCallback then
                    fontPickerCallback(value)
                end
                if fontPickerAnchor and fontPickerAnchor.Text then
                    local dt
                    if addon.IsLSMKey and addon.IsLSMKey(value) then
                        dt = addon.LSMKeyToName(value)
                    else
                        dt = addon.FontDisplayNames and addon.FontDisplayNames[value] or value
                    end
                    fontPickerAnchor.Text:SetText(dt)
                end
                CloseFontPicker()
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            end)

            -- Hover effects
            btn:SetScript("OnEnter", function(self)
                if not self._isSelected then
                    self.Label:SetTextColor(self._accentR, self._accentG, self._accentB, 1)
                end
            end)
            btn:SetScript("OnLeave", function(self)
                if self._isSelected then
                    self.Label:SetTextColor(self._accentR, self._accentG, self._accentB, 1)
                else
                    self.Label:SetTextColor(1, 1, 1, 0.9)
                end
            end)

            btn:Show()
        end
    end

    -- Escape key to close
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            CloseFontPicker()
        end
    end)

    -- Click outside to close
    frame:SetScript("OnShow", function(self)
        self:SetScript("OnUpdate", function(self, elapsed)
            if not self:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                C_Timer.After(0.05, function()
                    if fontPickerFrame and fontPickerFrame:IsShown() and not fontPickerFrame:IsMouseOver() then
                        CloseFontPicker()
                    end
                end)
            end
        end)
    end)
    frame:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    fontPickerFrame = frame
    return frame
end

function addon.ShowFontPicker(anchor, setting, optionsProvider, callback)
    local frame = CreateFontPicker()

    fontPickerSetting = setting
    fontPickerCallback = callback
    fontPickerAnchor = anchor

    -- Get current value and determine which tab to show
    local currentValue = nil
    if setting and setting.GetValue then
        currentValue = setting:GetValue()
    end

    -- Build working tabs (static tabs + optional LSM "Shared" tab)
    local workingTabs = {}
    for i, tabData in ipairs(FONT_TABS) do
        workingTabs[i] = tabData
    end
    if addon.LSMAvailable then
        -- Build dedup set from Scoot-internal font paths
        local internalPaths = {}
        if addon.Fonts then
            for _, path in pairs(addon.Fonts) do
                internalPaths[path:lower()] = true
            end
        end
        -- Filter LSM entries
        local filteredKeys = {}
        local lsmNames = addon.LSM:List("font")
        for _, lsmName in ipairs(lsmNames) do
            local path = addon.LSM:Fetch("font", lsmName, true)
            if path and not internalPaths[path:lower()] then
                filteredKeys[#filteredKeys + 1] = addon.LSMNameToKey(lsmName)
            end
        end
        if #filteredKeys > 0 then
            workingTabs[#workingTabs + 1] = { key = "shared", label = "Shared", fonts = filteredKeys }
        end
    end
    frame._workingTabs = workingTabs

    -- Auto-select tab containing the currently selected font
    if currentValue then
        selectedFontTab = GetCategoryForFont(currentValue)
    else
        selectedFontTab = "default"
    end
    -- Fallback if selected category (e.g. "shared") has no tab
    local tabFound = false
    for _, tabData in ipairs(workingTabs) do
        if tabData.key == selectedFontTab then tabFound = true; break end
    end
    if not tabFound then selectedFontTab = "default" end

    -- Update tabs, visuals and populate
    frame:UpdateTabs()
    frame:UpdateTabVisuals()
    frame:PopulateContent()

    -- Position relative to anchor
    frame:ClearAllPoints()
    if anchor then
        local anchorBottom = anchor:GetBottom() or 0
        local frameHeight = frame:GetHeight()
        local screenHeight = GetScreenHeight() * UIParent:GetEffectiveScale()

        if anchorBottom - frameHeight < 50 then
            frame:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
        else
            frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        end
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    frame:Show()
    frame:Raise()

    -- Preload fonts for smooth rendering
    if addon.PreloadFonts then
        addon.PreloadFonts()
    end
end

function addon.CloseFontPicker()
    CloseFontPicker()
end

--------------------------------------------------------------------------------
-- Font Dropdown Integration
--------------------------------------------------------------------------------

-- Apply font preview to a Settings dropdown using the custom font picker popup
function addon.InitFontDropdown(dropdown, setting, optionsProvider)
    if not dropdown or dropdown._ScootFontPickerInit then return end

    -- Function to update dropdown display text
    local function updateDropdownText()
        if not setting or not setting.GetValue then return end
        local currentValue = setting:GetValue()
        local displayText = addon.FontDisplayNames and addon.FontDisplayNames[currentValue] or currentValue
        if dropdown.Text and dropdown.Text.SetText then
            dropdown.Text:SetText(displayText)
            -- Also render the dropdown text in the selected font
            local fontFace = addon.ResolveFontFace(currentValue)
            if fontFace then
                pcall(dropdown.Text.SetFont, dropdown.Text, fontFace, 12, "")
            end
        end
    end

    -- Intercept clicks to show the custom picker instead of Blizzard's menu
    local function showPicker()
        -- Close any open Blizzard menus first
        if _G.MenuUtil and _G.MenuUtil.HideAllMenus then
            pcall(_G.MenuUtil.HideAllMenus)
        end
        if _G.CloseDropDownMenus then
            pcall(_G.CloseDropDownMenus)
        end

        addon.ShowFontPicker(dropdown, setting, optionsProvider, function(selectedValue)
            -- Callback after selection - update display
            updateDropdownText()
        end)
    end

    -- Create an invisible overlay button that captures clicks before the dropdown
    local overlay = CreateFrame("Button", nil, dropdown)
    overlay:SetAllPoints(dropdown)
    overlay:SetFrameLevel(dropdown:GetFrameLevel() + 10)
    overlay:RegisterForClicks("LeftButtonUp", "LeftButtonDown")

    overlay:SetScript("OnClick", function(self, button, down)
        if not down then
            showPicker()
        end
    end)

    -- Make overlay transparent but clickable
    overlay:EnableMouse(true)

    -- Keep a reference for later access
    dropdown._ScootFontPickerOverlay = overlay

    -- Initial text update
    C_Timer.After(0, updateDropdownText)

    dropdown._ScootFontPickerInit = true
end

-- Register stock faces and bundled font variants (paths are relative to the WoW root)
do
    local f = addon.Fonts
    -- Blizzard stock font aliases
    f.FRIZQT__ = "Fonts\\FRIZQT__.TTF"
    f.ARIALN   = "Fonts\\ARIALN.TTF"
    f.MORPHEUS = "Fonts\\MORPHEUS.TTF"
    f.SKURRI   = "Fonts\\SKURRI.TTF"

    local base = "Interface\\AddOns\\Scoot\\media\\fonts\\"

    -- Fira Sans family
    f.FIRASANS_REG       = base .. "FiraSans-Regular.ttf"
    f.FIRASANS_LIGHT     = base .. "FiraSans-Light.ttf"
    f.FIRASANS_MED       = base .. "FiraSans-Medium.ttf"
    f.FIRASANS_BOLD      = base .. "FiraSans-Bold.ttf"
    f.FIRASANS_BLACK     = base .. "FiraSans-Black.ttf"

    -- Roboto family
    f.ROBOTO_REG       = base .. "Roboto-Regular.ttf"
    f.ROBOTO_LIGHT     = base .. "Roboto-Light.ttf"
    f.ROBOTO_MED       = base .. "Roboto-Medium.ttf"
    f.ROBOTO_BLACK     = base .. "Roboto-Black.ttf"

    -- Roboto Condensed family
    f.ROBOTO_COND_REG       = base .. "Roboto_Condensed-Regular.ttf"
    f.ROBOTO_COND_LIGHT     = base .. "Roboto_Condensed-Light.ttf"
    f.ROBOTO_COND_MED       = base .. "Roboto_Condensed-Medium.ttf"
    f.ROBOTO_COND_BOLD      = base .. "Roboto_Condensed-Bold.ttf"
    f.ROBOTO_COND_BLACK     = base .. "Roboto_Condensed-Black.ttf"

    -- Roboto SemiCondensed family
    f.ROBOTO_SEMICOND_REG       = base .. "Roboto_SemiCondensed-Regular.ttf"
    f.ROBOTO_SEMICOND_LIGHT     = base .. "Roboto_SemiCondensed-Light.ttf"
    f.ROBOTO_SEMICOND_MED       = base .. "Roboto_SemiCondensed-Medium.ttf"
    f.ROBOTO_SEMICOND_BOLD      = base .. "Roboto_SemiCondensed-Bold.ttf"
    f.ROBOTO_SEMICOND_BLACK     = base .. "Roboto_SemiCondensed-Black.ttf"

    -- Dosis family
    f.DOSIS_REG      = base .. "Dosis-Regular.ttf"
    f.DOSIS_LIGHT    = base .. "Dosis-Light.ttf"
    f.DOSIS_MED      = base .. "Dosis-Medium.ttf"
    f.DOSIS_BOLD     = base .. "Dosis-Bold.ttf"

    -- Exo 2 family
    f.EXO2_REG       = base .. "Exo2-Regular.ttf"
    f.EXO2_LIGHT     = base .. "Exo2-Light.ttf"
    f.EXO2_MED       = base .. "Exo2-Medium.ttf"
    f.EXO2_BOLD      = base .. "Exo2-Bold.ttf"
    f.EXO2_BLACK     = base .. "Exo2-Black.ttf"

    -- Lato family
    f.LATO_REG   = base .. "Lato-Regular.ttf"
    f.LATO_LIGHT = base .. "Lato-Light.ttf"
    f.LATO_BOLD  = base .. "Lato-Bold.ttf"
    f.LATO_BLACK = base .. "Lato-Black.ttf"

    -- Montserrat family
    f.MONTSERRAT_REG       = base .. "Montserrat-Regular.ttf"
    f.MONTSERRAT_LIGHT     = base .. "Montserrat-Light.ttf"
    f.MONTSERRAT_MED       = base .. "Montserrat-Medium.ttf"
    f.MONTSERRAT_BOLD      = base .. "Montserrat-Bold.ttf"
    f.MONTSERRAT_BLACK     = base .. "Montserrat-Black.ttf"

    -- Mukta family
    f.MUKTA_REG      = base .. "Mukta-Regular.ttf"
    f.MUKTA_LIGHT    = base .. "Mukta-Light.ttf"
    f.MUKTA_MED      = base .. "Mukta-Medium.ttf"
    f.MUKTA_BOLD     = base .. "Mukta-Bold.ttf"

    -- Poppins family
    f.POPPINS_REG       = base .. "Poppins-Regular.ttf"
    f.POPPINS_LIGHT     = base .. "Poppins-Light.ttf"
    f.POPPINS_MED       = base .. "Poppins-Medium.ttf"
    f.POPPINS_BOLD      = base .. "Poppins-Bold.ttf"
    f.POPPINS_BLACK     = base .. "Poppins-Black.ttf"

    -- Heavy display faces (the font picker's "Display" tab). Anton ships only
    -- the settled 1.5x-wide bake (fonttools x-only stretch, hints stripped);
    -- the others ship base form.
    f.ANTON_WIDE_150 = base .. "AntonWide150.ttf"
    f.RUBIK_MONO_ONE = base .. "RubikMonoOne-Regular.ttf"
    f.TOMORROW_BLACK = base .. "Tomorrow-Black.ttf"
    f.BUNGEE         = base .. "Bungee-Regular.ttf"

    -- Pixel fonts
    f.PIXELLARI        = base .. "Pixellari.ttf"
    f.DOGICA_REG       = base .. "dogica.ttf"
    f.DOGICA_BOLD      = base .. "dogicabold.ttf"
    f.DOGICA_PIXEL     = base .. "dogicapixel.ttf"
    f.DOGICA_PIXELBOLD = base .. "dogicapixelbold.ttf"
    f.PIXELOP_REG      = base .. "PixelOperator.ttf"
    f.PIXELOP_BOLD     = base .. "PixelOperator-Bold.ttf"
    f.PIXELOP_MONO     = base .. "PixelOperatorMono.ttf"
    f.PIXELOP_MONOBOLD = base .. "PixelOperatorMono-Bold.ttf"
    f.PIXELOP_SC       = base .. "PixelOperatorSC.ttf"
    f.PIXELOP_SCBOLD   = base .. "PixelOperatorSC-Bold.ttf"
    f.RAINYHEARTS      = base .. "rainyhearts.ttf"
    f.FONT_04B30       = base .. "04B_30__.TTF"
    f.MINECRAFT        = base .. "Minecraft.ttf"
    f.PRESS_START_2P   = base .. "PressStart2P-Regular.ttf"
end

-- Human-readable display names for the font dropdown
addon.FontDisplayNames = {
    -- Stock fonts
    FRIZQT__  = "Friz Quadrata (Default)",
    ARIALN    = "Arial Narrow",
    MORPHEUS  = "Morpheus",
    SKURRI    = "Skurri",
    -- Fira Sans
    FIRASANS_REG       = "Fira Sans",
    FIRASANS_LIGHT     = "Fira Sans Light",
    FIRASANS_MED       = "Fira Sans Medium",
    FIRASANS_BOLD      = "Fira Sans Bold",
    FIRASANS_BLACK     = "Fira Sans Black",
    -- Roboto
    ROBOTO_REG       = "Roboto",
    ROBOTO_LIGHT     = "Roboto Light",
    ROBOTO_MED       = "Roboto Medium",
    ROBOTO_BLACK     = "Roboto Black",
    -- Roboto Condensed
    ROBOTO_COND_REG       = "Roboto Cond",
    ROBOTO_COND_LIGHT     = "Roboto Cond Light",
    ROBOTO_COND_MED       = "Roboto Cond Medium",
    ROBOTO_COND_BOLD      = "Roboto Cond Bold",
    ROBOTO_COND_BLACK     = "Roboto Cond Black",
    -- Roboto SemiCondensed
    ROBOTO_SEMICOND_REG       = "Roboto SemiCond",
    ROBOTO_SEMICOND_LIGHT     = "Roboto SemiCond Light",
    ROBOTO_SEMICOND_MED       = "Roboto SemiCond Medium",
    ROBOTO_SEMICOND_BOLD      = "Roboto SemiCond Bold",
    ROBOTO_SEMICOND_BLACK     = "Roboto SemiCond Black",
    -- Dosis
    DOSIS_REG      = "Dosis",
    DOSIS_LIGHT    = "Dosis Light",
    DOSIS_MED      = "Dosis Medium",
    DOSIS_BOLD     = "Dosis Bold",
    -- Exo 2
    EXO2_REG       = "Exo 2",
    EXO2_LIGHT     = "Exo 2 Light",
    EXO2_MED       = "Exo 2 Medium",
    EXO2_BOLD      = "Exo 2 Bold",
    EXO2_BLACK     = "Exo 2 Black",
    -- Lato
    LATO_REG   = "Lato",
    LATO_LIGHT = "Lato Light",
    LATO_BOLD  = "Lato Bold",
    LATO_BLACK = "Lato Black",
    -- Montserrat
    MONTSERRAT_REG       = "Montserrat",
    MONTSERRAT_LIGHT     = "Montserrat Light",
    MONTSERRAT_MED       = "Montserrat Medium",
    MONTSERRAT_BOLD      = "Montserrat Bold",
    MONTSERRAT_BLACK     = "Montserrat Black",
    -- Mukta
    MUKTA_REG      = "Mukta",
    MUKTA_LIGHT    = "Mukta Light",
    MUKTA_MED      = "Mukta Medium",
    MUKTA_BOLD     = "Mukta Bold",
    -- Poppins
    POPPINS_REG       = "Poppins",
    POPPINS_LIGHT     = "Poppins Light",
    POPPINS_MED       = "Poppins Medium",
    POPPINS_BOLD      = "Poppins Bold",
    POPPINS_BLACK     = "Poppins Black",
    -- Heavy display faces ("Display" tab)
    ANTON_WIDE_150 = "Anton Wide 1.5x",
    RUBIK_MONO_ONE = "Rubik Mono One",
    TOMORROW_BLACK = "Tomorrow Black",
    BUNGEE         = "Bungee",
    -- Pixel fonts
    PIXELLARI        = "Pixellari",
    DOGICA_REG       = "Dogica",
    DOGICA_BOLD      = "Dogica Bold",
    DOGICA_PIXEL     = "Dogica Pixel",
    DOGICA_PIXELBOLD = "Dogica Pixel Bold",
    PIXELOP_REG      = "Pixel Operator",
    PIXELOP_BOLD     = "Pixel Operator Bold",
    PIXELOP_MONO     = "Pixel Operator Mono",
    PIXELOP_MONOBOLD = "Pixel Operator Mono Bold",
    PIXELOP_SC       = "Pixel Operator SC",
    PIXELOP_SCBOLD   = "Pixel Operator SC Bold",
    RAINYHEARTS      = "Rainy Hearts",
    FONT_04B30       = "04B_30",
    MINECRAFT        = "Minecraft",
    PRESS_START_2P   = "Press Start 2P",
}


-- Preload font faces once to ensure consistent first-use rendering after game launch.
-- Avoids cases where certain Roboto variants appear unstyled until a second open.
function addon.PreloadFonts()
    if addon._fontsPreloaded then return end
    addon._fontsPreloaded = true
    local holder = CreateFrame("Frame")
    holder:Hide()
    local fs = holder:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    local size = 14
    local warmup = "The quick brown fox jumps over the lazy dog 0123456789 !@#%^&*()[]{}"
    for _, path in pairs(addon.Fonts or {}) do
        if type(path) == "string" and path ~= "" then
            pcall(fs.SetFont, fs, path, size, "")
            fs:SetText(warmup)
            pcall(fs.GetStringWidth, fs)
            fs:SetText("")
        end
    end
end



