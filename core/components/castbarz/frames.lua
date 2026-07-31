--------------------------------------------------------------------------------
-- castbarz/frames.lua
-- Cast Bar Z frame construction and layout.
--
-- The visual is a port of Cast Bar X's text-fill mode (unitframes/cast/textfill.lua):
-- same draw layers, same sublevels, same tick-style end caps, same 1px outlines.
-- What changes is ownership -- every frame here belongs to Scoot, so nothing is
-- guarded against a Blizzard repaint and nothing reads a secret.
--
-- Hard rule inherited from the plan: NEVER read this frame's own geometry.
-- Once a bar takes a secret-valued duration (any unit that is not player/pet),
-- GetWidth/GetHeight/GetPoint on it start answering with secrets. Every
-- dimension below comes from the DB.
--------------------------------------------------------------------------------

local addonName, addon = ...
local CBZ = addon.CastBarZ

-- Vertical clip overflow, so tall glyphs and outlines are not sliced by the band
-- frames. Matches textfill.lua:814. X's horizontal FIT_H_OVERFLOW is deliberately
-- NOT ported: it exists because X cannot know its own text width, and horizontal
-- overflow would break band boundaries here.
local TEXT_OVERFLOW = 20

-- Column count for the banded ramp. Higher looks smoother and costs 2 FontStrings
-- per band; 12 is the visual break-even against X's per-character gradient.
CBZ.NUM_BANDS = 12

-- Unfilled (not yet cast) portion. Solid gray, no alpha reduction -- matches
-- textfill.lua:745. Exported because empowered.lua has to put it back when a
-- cast's tier palette is torn down.
CBZ.TRACK_GRAY = { 0.5, 0.5, 0.5 }
local GRAY_R, GRAY_G, GRAY_B = CBZ.TRACK_GRAY[1], CBZ.TRACK_GRAY[2], CBZ.TRACK_GRAY[3]

-- The dim copy of the text sits behind the sweep at this alpha.
local DIM_TEXT_ALPHA = 0.4

-- Blizzard's interrupt glow art, reused verbatim (CastingBarFrame.xml:223). The
-- padding stretches it past the bar: the atlas is authored as an OUTER glow, so
-- its soft falloff is meant to land outside the thing it surrounds.
local GLOW_ATLAS = "cast_interrupt_outerglow"
local GLOW_PAD_X = 14
local GLOW_PAD_Y = 9

-- The line and end ticks sit directly behind the spell name, so their only job is
-- contrast -- and on player and pet that contrast is the CLASS color, matching what
-- Cast Bar X draws in its `class` color mode (textfill.lua:60-64, which likewise
-- resolves "player" for every unit rather than the unit being cast on).
--
-- This is not a free choice: the spec gradients the name is drawn in were authored
-- to read against their own class color. Elemental Shaman is the clearest case --
-- a red-orange gradient over Shaman blue. A static backdrop breaks that pairing for
-- every class whose spec hues were tuned away from it.
--
-- Corrected 2026-07-30. A 2026-07-29 check against X in-game reported white and the
-- constant was hardcoded to match; the character used for that check must have been
-- one whose class color IS near-white (Priest is exactly 1,1,1), so a class-colored
-- line was indistinguishable from a fixed one. Read the code, not the screen, when
-- the answer is a single color.
--
-- The remaining units keep gold, which was chosen against the flat red an NPC cast
-- draws (Phase 2).
CBZ.LINE_COLOR_DEFAULT = { 1.0, 0.70, 0.00 }   -- gold, interruptible
CBZ.LINE_COLOR_LOCKED  = { 1.0, 1.00, 1.00 }   -- white, uninterruptible
CBZ.LINE_COLOR_OWN_FALLBACK = { 1.0, 1.00, 1.00 }  -- class unresolvable

-- Units that render the PLAYER's own palette -- spec gradient for the name, class
-- color for the line -- regardless of what is actually being cast on them. Shared
-- with text.lua so the two halves of that palette can never disagree about which
-- units they cover.
CBZ.OWN_CAST_UNITS = { Player = true, Pet = true }
local OWN_CAST_UNITS = CBZ.OWN_CAST_UNITS

--- Base line color for a unit, before an uninterruptible cast overrides it.
---
--- Resolved per call rather than cached: it costs one table lookup, and the one
--- thing a cached class color cannot survive is being resolved before the class is
--- known. Callers treat the result as read-only.
---
--- On player and pet the uninterruptible override never fires -- you are never the
--- one kicking your own cast -- so a class-colored line is not competing with it.
function CBZ._ResolveLineColor(unitKey)
    if not OWN_CAST_UNITS[unitKey] then return CBZ.LINE_COLOR_DEFAULT end

    local r, g, b = addon.GetClassColorRGB("player")
    if not r then return CBZ.LINE_COLOR_OWN_FALLBACK end
    return { r, g, b }
end

-- Snap a layout offset to whole physical pixels.
--
-- Band edges at W * i / N land on fractional pixels for most widths. Unsnapped,
-- adjacent columns either overlap or leave a sub-pixel gap, and the gap reads as
-- a hairline straight through the spell name. Same mechanism as the row-to-row
-- outline weight differences documented in subpixel-font-outline.md.
--
-- Snapped against UIParent, never against the bar: reading the bar's own
-- effective scale would be a geometry read on a frame that may be secret. The bar
-- is parented to UIParent and is never re-parented or scaled, so UIParent's
-- effective scale is exactly the right divisor.
local function SnapToPixels(value)
    if not (PixelUtil and PixelUtil.GetNearestPixelSize) then return value end
    local es = UIParent and UIParent:GetEffectiveScale()
    if not es or es <= 0 then return value end
    return PixelUtil.GetNearestPixelSize(value, es)
end
CBZ._SnapToPixels = SnapToPixels

--------------------------------------------------------------------------------
-- Band construction
--------------------------------------------------------------------------------

-- One column of the banded ramp: a clipping frame holding a full copy of the
-- spell name, colored with that column's ramp stop.
--
-- The FontString is created directly on the band, matching textfill.lua:204 where
-- filledText is created directly on clipFrame and is clipped correctly. (Damage
-- Meters Y interposes an inner frame at frames.lua:419 on the theory that
-- ClipsChildren only reaches child frames; textfill disproves that. If a band
-- ever fails to clip, an inner frame is a one-line fix.)
local function CreateBand(parent)
    local band = CreateFrame("Frame", nil, parent)
    band:SetClipsChildren(true)

    local fs = band:CreateFontString(nil, "OVERLAY")
    -- Default font up front so the band can render before styling runs.
    fs:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    fs:SetWordWrap(false)
    fs:SetWidth(0)          -- natural width; shrink-to-fit uses SetTextScale
    fs:SetJustifyH("CENTER")

    return { frame = band, fs = fs }
end

local function CreateBandSet(parent, count)
    local bands = {}
    for i = 1, count do
        bands[i] = CreateBand(parent)
    end
    return bands
end

--------------------------------------------------------------------------------
-- Bar construction
--------------------------------------------------------------------------------

local function BuildBarFrame(name, parent, row)
    local bar = CreateFrame("Frame", name, parent)
    bar:SetSize(200, 16)                              -- real values from _LayoutBar
    bar:Hide()

    -- barKey indexes this bar, unitKey names its configuration, unit is what the
    -- API is asked about. They coincide for every unit except Boss.
    bar.barKey = row.barKey
    bar.unitKey = row.unitKey
    bar.unit = row.token

    -- Claim one free level underneath before anything else reads it: the
    -- interrupt glow sits BELOW the bar's own textures, matching where Blizzard
    -- layers InterruptGlow. Bumping the bar rather than dropping the glow to
    -- level - 1 keeps the glow's level positive whatever UIParent hands us.
    bar:SetFrameLevel(bar:GetFrameLevel() + 1)
    local level = bar:GetFrameLevel()

    -- Cached so later passes place things relative to the bar without re-reading
    -- it. Frame level is not one of the properties anchor secrecy propagates
    -- into, but the layout pass reads nothing else off the bar and there is no
    -- reason for this to be the exception.
    bar.baseLevel = level

    ----------------------------------------------------------------------------
    -- progressBar: the engine-driven clock
    ----------------------------------------------------------------------------
    -- Invisible, but ALPHA zero rather than Hide(): a hidden frame is never laid
    -- out, so its fill texture's rect would never update and the reveal would sit
    -- frozen at full width. That exact mistake cost a full Phase 0 test cycle.
    local progressBar = CreateFrame("StatusBar", nil, bar)
    progressBar:SetAllPoints(bar)
    progressBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    progressBar:SetMinMaxValues(0, 1)
    progressBar:SetValue(0)
    progressBar:SetAlpha(0)
    bar.progressBar = progressBar

    local fillTex = progressBar:GetStatusBarTexture()
    bar.fillTex = fillTex

    ----------------------------------------------------------------------------
    -- Unfilled track (bar level, below everything)
    ----------------------------------------------------------------------------
    bar.unfilledLineOL     = bar:CreateTexture(nil, "BACKGROUND", nil, 0)
    bar.unfilledLeftCapOL  = bar:CreateTexture(nil, "BACKGROUND", nil, 0)
    bar.unfilledRightCapOL = bar:CreateTexture(nil, "BACKGROUND", nil, 0)
    bar.unfilledLine       = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
    bar.unfilledLeftCap    = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    bar.unfilledRightCap   = bar:CreateTexture(nil, "ARTWORK", nil, 1)

    ----------------------------------------------------------------------------
    -- Filled line (bar level; its RIGHT edge tracks the fill texture)
    ----------------------------------------------------------------------------
    bar.filledLineOL = bar:CreateTexture(nil, "BACKGROUND", nil, 2)
    bar.filledLine   = bar:CreateTexture(nil, "BACKGROUND", nil, 3)

    ----------------------------------------------------------------------------
    -- Dim text layer
    ----------------------------------------------------------------------------
    local dimText = CreateFrame("Frame", nil, bar)
    dimText:SetAllPoints(bar)
    dimText:SetFrameLevel(level + 1)
    dimText:SetAlpha(DIM_TEXT_ALPHA)
    bar.dimText = dimText
    bar.dimBands = CreateBandSet(dimText, CBZ.NUM_BANDS)

    ----------------------------------------------------------------------------
    -- Reveal layer: everything inside is clipped to the swept portion
    ----------------------------------------------------------------------------
    local revealFrame = CreateFrame("Frame", nil, bar)
    revealFrame:SetClipsChildren(true)
    revealFrame:SetFrameLevel(level + 2)
    bar.revealFrame = revealFrame

    bar.filledLeftCapOL  = revealFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bar.filledRightCapOL = revealFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bar.filledLeftCap    = revealFrame:CreateTexture(nil, "ARTWORK", nil, 2)
    bar.filledRightCap   = revealFrame:CreateTexture(nil, "ARTWORK", nil, 2)

    bar.brightBands = CreateBandSet(revealFrame, CBZ.NUM_BANDS)

    ----------------------------------------------------------------------------
    -- Empowered pip dividers, above the reveal
    ----------------------------------------------------------------------------
    -- Its own frame, and above revealFrame, because a divider has to stay visible
    -- on BOTH sides of the sweep. Left on the bar it would be painted over by the
    -- bright tier segments the moment the fill passed it, which is precisely when
    -- it matters most. Contents belong to empowered.lua; nothing is built until an
    -- empowered cast actually starts.
    local pipFrame = CreateFrame("Frame", nil, bar)
    pipFrame:SetAllPoints(bar)
    pipFrame:SetFrameLevel(level + 3)
    bar.pipFrame = pipFrame

    ----------------------------------------------------------------------------
    -- Spark, above the reveal so it draws in front of the text
    ----------------------------------------------------------------------------
    -- The frame is built here; its contents are not. Which regions exist depends
    -- on the chosen spark style, so effects.lua owns them (CBZ._BuildSpark, run
    -- from the layout pass). One style -- the ember trail -- deliberately lives
    -- on revealFrame instead, to inherit the sweep clip.
    --
    -- Level + 4 rather than + 3: the spark is a cursor and must sit above the
    -- empowered pip dividers it slides across. Explicit levels rather than relying
    -- on sibling creation order, which is invisible and easy to disturb.
    local sparkFrame = CreateFrame("Frame", nil, bar)
    sparkFrame:SetAllPoints(bar)
    sparkFrame:SetFrameLevel(level + 4)
    bar.sparkFrame = sparkFrame

    ----------------------------------------------------------------------------
    -- Cast time readout, outside the bar
    ----------------------------------------------------------------------------
    -- On the bar rather than in a sub-frame, and deliberately OUTSIDE its rect:
    -- nothing here clips children, so a region may overflow. That is the whole
    -- point of the placement -- the spell name and its 12-band ramp keep spanning
    -- the full bar, and the readout is purely additive beside it.
    --
    -- Created unconditionally even when the setting is off. It is one region, and
    -- a conditional would have to be undone on every settings change; casttime.lua
    -- hides it instead.
    local castTimeText = bar:CreateFontString(nil, "OVERLAY")
    castTimeText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    castTimeText:SetWordWrap(false)
    castTimeText:Hide()
    bar.castTimeText = castTimeText

    ----------------------------------------------------------------------------
    -- Interrupt glow, behind the bar
    ----------------------------------------------------------------------------
    -- Blizzard's own interrupt visual, borrowed whole: cast_interrupt_outerglow,
    -- additive, at BACKGROUND behind the bar (CastingBarFrame.xml:223). Cast Bar X
    -- shows this texture untouched -- text-fill mode suppresses Flash but leaves
    -- InterruptGlow alone on purpose (textfill.lua:305) -- so reusing the atlas is
    -- what makes Z's interrupt read the same. A flat WHITE8X8 rectangle cannot:
    -- hard edges are precisely what this art is authored to avoid.
    --
    -- A Frame rather than a bare texture because UIFrameFadeOut writes fields to
    -- whatever it is handed, and only a Frame accepts them. Below the bar's level
    -- so the glow bleeds around the glyphs instead of washing them out -- additive
    -- light on top of white text at full strength erases the word.
    local flashFrame = CreateFrame("Frame", nil, bar)
    flashFrame:SetFrameLevel(level - 1)
    flashFrame:Hide()

    local flashTex = flashFrame:CreateTexture(nil, "ARTWORK")
    flashTex:SetBlendMode("ADD")

    local hasGlowAtlas = C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo(GLOW_ATLAS) ~= nil

    if hasGlowAtlas then
        flashTex:SetAtlas(GLOW_ATLAS, false)   -- false: our anchors set the size
        flashFrame:SetPoint("TOPLEFT", bar, "TOPLEFT", -GLOW_PAD_X, GLOW_PAD_Y)
        flashFrame:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", GLOW_PAD_X, -GLOW_PAD_Y)
    else
        -- Not expected on 12.0. One branch to keep the interrupt legible rather
        -- than invisible if the atlas is ever renamed out from under us.
        flashTex:SetTexture("Interface\\Buttons\\WHITE8X8")
        flashTex:SetVertexColor(1.00, 0.45, 0.40)
        flashFrame:SetAllPoints(bar)
    end
    flashTex:SetAllPoints(flashFrame)

    -- The atlas carries its own falloff and is meant to be shown outright, the way
    -- Blizzard's InterruptGlowAnim jumps it straight to 1. The flat fallback at
    -- that strength would be a solid slab, so it peaks far lower.
    flashFrame.peakAlpha = hasGlowAtlas and 1.0 or 0.30

    bar.flashFrame = flashFrame
    bar.flashTex = flashTex

    return bar
end

function CBZ._CreateBar(row, comp)
    local bar = BuildBarFrame("ScootCastBarZ_" .. row.barKey, UIParent, row)
    bar:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    return bar
end

--- A copy for the settings preview, parented into the panel instead of UIParent.
--- Deliberately the same construction and the same layout code as the live bar,
--- so the preview cannot drift away from what the HUD actually draws. `width`
--- overrides the DB width, since the pane sets its own.
---
--- Takes a unitKey, not a barKey: the settings page has one entry per
--- configuration, so a Boss preview models boss1 and stands for all five.
function CBZ._CreatePreviewBar(parent, unitKey, width)
    local row = CBZ._RowForUnitKey(unitKey)
    if not row then return nil end

    local bar = BuildBarFrame(nil, parent, row)
    bar.isPreview = true
    bar.widthOverride = width
    return bar
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

-- Position every element from DB numbers. Idempotent: safe to call on any
-- settings change, and always recomputed from scratch rather than adjusted.
function CBZ._LayoutBar(bar, comp)
    local cfg = CBZ._GetUnitConfig(bar.unitKey)

    local barW      = tonumber(bar.widthOverride) or tonumber(cfg and cfg.barWidth) or 200
    local capSize   = CBZ._GetCapSize()
    local fontSize  = tonumber(CBZ._GetSetting("fontSize")) or 14

    -- Snapped for the same reason band edges are (see _LayoutBands): capSize * 0.3
    -- is fractional for most cap sizes, and a fractional tick has to be rounded by
    -- the renderer. The filled caps live inside revealFrame while the gray unfilled
    -- ones live on the bar, so the two rects round independently and a rounding
    -- disagreement leaves a hairline of the gray showing beside the colored tick --
    -- which reads as a gap between the tick and the line.
    local lineH = SnapToPixels(CBZ._GetLineHeight())

    -- Tick-style end caps: narrow and tall, per textfill.lua:739-740.
    local capW = math.max(2, SnapToPixels(capSize * 0.3))
    local capH = SnapToPixels(capSize)

    local barH = math.max(capH, fontSize + 2)
    bar:SetSize(barW, barH)

    local fillTex = bar.fillTex

    ----------------------------------------------------------------------------
    -- Unfilled track
    ----------------------------------------------------------------------------
    local el = bar.unfilledLine
    el:ClearAllPoints()
    el:SetPoint("LEFT", bar, "LEFT", 0, 0)
    el:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    el:SetHeight(lineH)
    el:SetColorTexture(GRAY_R, GRAY_G, GRAY_B, 1)
    el:Show()

    el = bar.unfilledLineOL
    el:ClearAllPoints()
    el:SetPoint("TOPLEFT", bar.unfilledLine, "TOPLEFT", -1, 1)
    el:SetPoint("BOTTOMRIGHT", bar.unfilledLine, "BOTTOMRIGHT", 1, -1)
    el:SetColorTexture(0, 0, 0, 1)
    el:Show()

    el = bar.unfilledLeftCap
    el:ClearAllPoints()
    el:SetPoint("LEFT", bar, "LEFT", 0, 0)
    el:SetSize(capW, capH)
    el:SetColorTexture(GRAY_R, GRAY_G, GRAY_B, 1)
    el:Show()

    el = bar.unfilledLeftCapOL
    el:ClearAllPoints()
    el:SetPoint("TOPLEFT", bar.unfilledLeftCap, "TOPLEFT", -1, 1)
    el:SetPoint("BOTTOMRIGHT", bar.unfilledLeftCap, "BOTTOMRIGHT", 0, -1)
    el:SetColorTexture(0, 0, 0, 1)
    el:Show()

    el = bar.unfilledRightCap
    el:ClearAllPoints()
    el:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    el:SetSize(capW, capH)
    el:SetColorTexture(GRAY_R, GRAY_G, GRAY_B, 1)
    el:Show()

    el = bar.unfilledRightCapOL
    el:ClearAllPoints()
    el:SetPoint("TOPLEFT", bar.unfilledRightCap, "TOPLEFT", 0, 1)
    el:SetPoint("BOTTOMRIGHT", bar.unfilledRightCap, "BOTTOMRIGHT", 1, -1)
    el:SetColorTexture(0, 0, 0, 1)
    el:Show()

    ----------------------------------------------------------------------------
    -- Reveal frame: right edge tracks the fill texture, so progress needs no
    -- arithmetic and no GetValue(). Vertical overflow keeps tall glyphs whole.
    ----------------------------------------------------------------------------
    local revealFrame = bar.revealFrame
    revealFrame:ClearAllPoints()
    revealFrame:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, TEXT_OVERFLOW)
    revealFrame:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMRIGHT", 0, -TEXT_OVERFLOW)
    revealFrame:Show()

    ----------------------------------------------------------------------------
    -- Filled line: on the bar (not clipped), right edge on the fill texture
    ----------------------------------------------------------------------------
    el = bar.filledLine
    el:ClearAllPoints()
    el:SetPoint("LEFT", bar, "LEFT", 0, 0)
    el:SetPoint("RIGHT", fillTex, "RIGHT", 0, 0)
    el:SetHeight(lineH)
    el:Show()

    el = bar.filledLineOL
    el:ClearAllPoints()
    el:SetPoint("TOPLEFT", bar.filledLine, "TOPLEFT", -1, 1)
    el:SetPoint("BOTTOMRIGHT", bar.filledLine, "BOTTOMRIGHT", 1, -1)
    el:SetColorTexture(0, 0, 0, 1)
    el:Show()

    ----------------------------------------------------------------------------
    -- Filled caps, inside the reveal frame so they light up with the sweep
    ----------------------------------------------------------------------------
    el = bar.filledLeftCap
    el:ClearAllPoints()
    el:SetPoint("LEFT", bar, "LEFT", 0, 0)
    el:SetSize(capW, capH)
    el:Show()

    el = bar.filledLeftCapOL
    el:ClearAllPoints()
    el:SetPoint("TOPLEFT", bar.filledLeftCap, "TOPLEFT", -1, 1)
    el:SetPoint("BOTTOMRIGHT", bar.filledLeftCap, "BOTTOMRIGHT", 0, -1)
    el:SetColorTexture(0, 0, 0, 1)
    el:Show()

    el = bar.filledRightCap
    el:ClearAllPoints()
    el:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    el:SetSize(capW, capH)
    el:Show()

    el = bar.filledRightCapOL
    el:ClearAllPoints()
    el:SetPoint("TOPLEFT", bar.filledRightCap, "TOPLEFT", 0, 1)
    el:SetPoint("BOTTOMRIGHT", bar.filledRightCap, "BOTTOMRIGHT", 1, -1)
    el:SetColorTexture(0, 0, 0, 1)
    el:Show()

    ----------------------------------------------------------------------------
    -- Bands
    ----------------------------------------------------------------------------
    CBZ._LayoutBands(bar, barW)

    ----------------------------------------------------------------------------
    -- Spark and completion effect
    ----------------------------------------------------------------------------
    -- Both are style-driven and both need the same snapped numbers the track was
    -- just built from. Passing them rather than recomputing is what keeps a spark
    -- tick from disagreeing with the end caps about where a pixel boundary is.
    local geom = { barW = barW, lineH = lineH, capW = capW, capH = capH }
    CBZ._BuildSpark(bar, geom)
    CBZ._LayoutFinishFX(bar, geom)
    CBZ._RefreshSparkVisibility(bar)

    ----------------------------------------------------------------------------
    -- Cast time readout
    ----------------------------------------------------------------------------
    -- Takes no geom: it anchors to the bar's own edges, and the bar's RIGHT edge
    -- is already the outer edge of the right end tick, so the gap measures from
    -- past the tick without needing to know how wide one is.
    CBZ._LayoutCastTime(bar)

    ----------------------------------------------------------------------------
    -- Empowered tiers, if a cast is mid-charge
    ----------------------------------------------------------------------------
    -- Last, and unconditionally: everything above has just re-shown and re-colored
    -- the plain line, which is exactly what an empowered cast replaces. A settings
    -- change during a charge would otherwise drop the tiers on the floor.
    CBZ._RelayoutEmpowered(bar)
end

--- Bring the spark back, unless the user has turned it off.
---
--- The spark is hidden whenever a cast ends, so every path that puts the bar back
--- into a live or preview state has to restore it rather than assume it is up.
---
--- An empowered cast overrides the setting, matching what Cast Bar X does for the
--- same reason (styling.lua:750-751): on an empowered bar the spark's position
--- against the pip dividers IS the readout -- it is how you know which tier you
--- are about to release at. Hiding it does not simplify the bar, it removes the
--- only thing on it that answers the question the cast is asking.
function CBZ._RefreshSparkVisibility(bar)
    local shown = CBZ._GetSetting("showSpark") ~= false
    if bar.empowered then shown = true end
    CBZ._SetSparkShown(bar, shown)
end

--- Show or hide the spark, whichever style is active.
---
--- Not just sparkFrame:SetShown(): the ember trail lives on revealFrame so it can
--- inherit the sweep clip, which puts it outside sparkFrame's reach. Toggling the
--- frame alone would leave the trail lit with the spark switched off, and lit on a
--- bar whose cast has already ended.
function CBZ._SetSparkShown(bar, shown)
    bar.sparkFrame:SetShown(shown)
    CBZ._SetDetachedSparkShown(bar, shown)
end

-- Lay out both band sets on identical, pixel-snapped column boundaries.
--
-- Both sets anchor to the BAR, never to their own parent. The band decides only
-- which column of the name is visible; anchoring to the parent would make the
-- bright copy shift as revealFrame's width changes, and the two copies would
-- drift apart mid-cast.
function CBZ._LayoutBands(bar, barW)
    local n = CBZ.NUM_BANDS
    local prevEdge = 0

    for i = 1, n do
        local edge = SnapToPixels(barW * i / n)
        if i == n then edge = barW end          -- last column always closes on the bar edge
        if edge <= prevEdge then edge = prevEdge + 1 end

        for _, set in ipairs({ bar.dimBands, bar.brightBands }) do
            local band = set[i]
            band.frame:ClearAllPoints()
            band.frame:SetPoint("TOPLEFT", bar, "TOPLEFT", prevEdge, TEXT_OVERFLOW)
            band.frame:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", edge, -TEXT_OVERFLOW)

            band.fs:ClearAllPoints()
            band.fs:SetPoint("CENTER", bar, "CENTER", 0, 0)
        end

        prevEdge = edge
    end
end

--------------------------------------------------------------------------------
-- Colors (line and caps; band text colors live in text.lua)
--------------------------------------------------------------------------------

function CBZ._ApplyLineColor(bar, r, g, b)
    -- An empowered cast owns the line and both caps: they carry a tier palette,
    -- not one color. The guard lives here rather than at each call site so a
    -- future caller cannot quietly reintroduce the overwrite -- and because every
    -- caller genuinely means "set the line color", not "set it unless...".
    if CBZ._IsEmpoweredActive and CBZ._IsEmpoweredActive(bar) then return end

    for _, tex in ipairs({ bar.filledLine, bar.filledLeftCap, bar.filledRightCap }) do
        tex:SetColorTexture(r, g, b, 1)
    end
end

--- Put the unfilled track back to plain gray.
--- Only empowered casts ever move it, so this is the one-way door back.
function CBZ._ApplyTrackGray(bar)
    local c = CBZ.TRACK_GRAY
    for _, tex in ipairs({ bar.unfilledLine, bar.unfilledLeftCap, bar.unfilledRightCap }) do
        tex:SetColorTexture(c[1], c[2], c[3], 1)
    end
end

--------------------------------------------------------------------------------
-- Per-unit apply pass
--------------------------------------------------------------------------------

function CBZ._ApplyBar(barKey, comp)
    -- A disabled unit has no bar at all (see _EnsureBar), which is not an error --
    -- it is the zero-touch case and the common one.
    local bar = CBZ._bars[barKey]
    if not bar then return end

    local cfg = CBZ._GetUnitConfig(bar.unitKey)
    if not cfg or not cfg.enabled then
        CBZ._ResetBar(bar)
        return
    end

    CBZ._LayoutBar(bar, comp)
    CBZ._ApplyBandFonts(bar)

    local line = CBZ._GetLineColor(bar)
    CBZ._ApplyLineColor(bar, line[1], line[2], line[3])

    CBZ._RestorePosition(bar)

    -- Edit Mode needs the frame visible to drag; otherwise the bar is shown only
    -- while a cast is in flight, which events.lua owns.
    if CBZ._editModeActive then
        CBZ._ShowEditModePreview(bar)
    elseif not bar.casting then
        bar:Hide()
    end
end

--------------------------------------------------------------------------------
-- Progress
--------------------------------------------------------------------------------

--- Park the sweep at a fixed fraction. Used for the static Edit Mode preview and
--- for resetting between casts; live casts use SetTimerDuration instead.
function CBZ._SetStaticProgress(bar, frac)
    local pb = bar.progressBar
    pb:SetMinMaxValues(0, 1)
    pb:SetValue(math.max(0, math.min(1, frac or 0)))
end

--- Stop the sweep exactly where it stands, without knowing where that is.
---
--- SetTimerDuration hands the bar to C++ and nothing in Lua stops it again, so a
--- cast that ends before its duration expires keeps filling through the hold and
--- the fade. That describes EVERY empowered cast -- releasing early is the whole
--- mechanic -- and the Phase 1 alternative of parking at 0 or 1 is a lie either
--- way: release at tier 2 and the bar reports an emptied channel or a completed
--- one, never the tier you actually got.
---
--- The round trip is legal on a secret-valued bar in both directions and never
--- inspects what it moves: GetValue is SecretReturnsForAspect { BarValue }
--- (SimpleStatusBarAPIDocumentation.lua:149-161) and SetValue is
--- SecretArguments = "AllowedWhenTainted" (:331-341). The value is read and handed
--- straight back -- no comparison, no arithmetic, no type test, so there is
--- nothing for the secret system to object to.
---
--- Writing an explicit value also overrides the running timer, which is the same
--- property _FinishCast already relies on to stop an interrupted cast from
--- finishing its fill.
function CBZ._FreezeProgress(bar)
    local pb = bar.progressBar
    local ok, value = pcall(pb.GetValue, pb)
    if not ok then return false end
    return (pcall(pb.SetValue, pb, value))
end

--- Show a representative bar so Edit Mode has something to grab and position.
function CBZ._ShowEditModePreview(bar)
    -- An empowered cast that ended while Edit Mode was open takes the early exit
    -- in _FinishCast, so its segments are still up and its sweep is still frozen
    -- where the player released. Neither belongs on a positioning stand-in.
    if not bar.empowerPreview then
        CBZ._ClearEmpowered(bar)
    end
    CBZ._SetText(bar, CBZ.PREVIEW_SPELL_NAME)
    CBZ._SetStaticProgress(bar, 0.55)
    CBZ._RefreshSparkVisibility(bar)
    -- A number has to be on screen while the bar is being positioned, or the user
    -- is placing the bar without seeing the thing that has to fit beside it.
    -- Blizzard hardcodes `seconds = 10` in its own Edit Mode branch for the same
    -- reason (CastingBarFrame.lua:774-775).
    CBZ._ShowCastTimePlaceholder(bar, CBZ.PREVIEW_CAST_TIME)
    bar:Show()
end
