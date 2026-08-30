-- fontpair.lua - Deep Shadow rendering: a black copy drawn behind a FontString.
--
-- ApplyFontStyle (core/fonts.lua) calls in here for DEEPSHADOW* styles. The
-- copy is drawn one layer below the real string (see Apply for why a layer and
-- not a sublevel) and shares its font file, size, and engine flags, so an
-- OUTLINE/THICKOUTLINE flag dilates the copy the same way; offset (+2, -2) at
-- 0.8 alpha then reads as a fattened silhouette, which the native shadow
-- (never dilated by the engine) cannot produce.
--
-- Only styles applied to Scoot-created FontStrings offer DEEPSHADOW* keys
-- (see the *Paired order tables in core/fonts.lua): mirroring text into the
-- copy needs SetText hooks, and those are cheap and safe on our own strings.
-- Secret text (12.x) cannot be read or escape-stripped, so it is passed to the
-- copy untouched; inline escapes in secret strings would tint the copy, an
-- accepted degradation.
local addonName, addon = ...

addon.FontPair = {}

-- Every live pair, for /scoot debug fontpair. Weak on both sides so a retired
-- FontString and its copy still collect.
addon.FontPair.registry = setmetatable({}, { __mode = "kv" })

local OFFSET_X, OFFSET_Y = 2, -2

-- The engine draws layers in this order, so the copy sits one rung down from
-- whatever the real string is on. BACKGROUND has nothing below it.
local LAYER_BELOW = {
    HIGHLIGHT = "OVERLAY",
    OVERLAY   = "ARTWORK",
    ARTWORK   = "BORDER",
    BORDER    = "BACKGROUND",
}

-- Copy alpha at full opacity.
local COPY_ALPHA = 0.8

-- type() reports "number" for a secret number, so it is not a sufficient gate:
-- the arithmetic in luminanceOf and the compares in clamp01 both run outside
-- their pcall, and a secret would raise there. Deep Shadow is only offered on
-- strings Scoot writes, whose colors are plain, so this never fires in practice
-- and exists so a future surface cannot repeat the boolean-test crash this file
-- already had.
local function plainNumber(v)
    if type(v) ~= "number" then return false end
    if type(issecretvalue) == "function" and issecretvalue(v) then return false end
    return true
end

-- Rec. 709 relative luminance of the real string's text color. A color that
-- does not read reports 1 (bright), which holds the copy at COPY_ALPHA and so
-- keeps the pre-taper behavior.
local function luminanceOf(fs)
    if not fs.GetTextColor then return 1 end
    local ok, r, g, b = pcall(fs.GetTextColor, fs)
    if not ok or not plainNumber(r) or not plainNumber(g) or not plainNumber(b) then
        return 1
    end
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
end

local function clamp01(v)
    if not plainNumber(v) then return 1 end
    if v < 0 then return 0 elseif v > 1 then return 1 end
    return v
end

-- The alpha the real string is actually drawn at: its own, times everything it
-- inherits. GetEffectiveAlpha is a Frame method (SimpleFrameAPIDocumentation
-- .lua:366) and a FontString's parent is always a Frame, so the parent carries
-- the inherited half.
local function effectiveAlphaOf(fs)
    local own = 1
    if fs.GetAlpha then
        local ok, a = pcall(fs.GetAlpha, fs)
        if ok then own = clamp01(a) end
    end

    local okP, parent = pcall(fs.GetParent, fs)
    if not okP or not parent or not parent.GetEffectiveAlpha then return own end
    local okA, inherited = pcall(parent.GetEffectiveAlpha, parent)
    if not okA then return own end
    return own * clamp01(inherited)
end

-- How dark the copy may be at a given drawn alpha.
--
-- At full alpha the real string is opaque and hides the copy everywhere except
-- the protruding fringe, so a stroke crosses two values: fill, then black. Below
-- full alpha the copy shows THROUGH the fill and through the outline, and the
-- same stroke crosses four: fill+copy, fill, outline+copy, outline. The
-- letterform stops resolving once a fill band goes darker than an outline band,
-- which happens when
--
--     copyAlpha > textLuminance / ((1 - drawnAlpha) * backgroundLuminance)
--
-- The ceiling falls as the frame fades and rises with the brightness of the
-- text. Measured 2026-08-30 against a PRD power number in Insanity purple
-- (0.40, 0, 0.80, luminance 0.14, PowerBarColorUtil.lua:29): at half opacity the
-- four bands interleaved and the glyph read as a blurred lump, while a white
-- name at the same opacity stayed clean because white never reaches the ceiling.
--
-- So taper on both terms. lum = 1 returns COPY_ALPHA at every alpha, which is
-- what keeps white and light text identical to before this existed.
local function copyAlphaFor(lum, drawn)
    local fade = drawn * drawn
    return COPY_ALPHA * (fade + (1 - fade) * lum)
end

local function refreshCopyAlpha(fs)
    local companion = fs.__scootPair
    if not companion or not fs.__scootPairActive then return end
    pcall(companion.SetTextColor, companion, 0, 0, 0,
        copyAlphaFor(luminanceOf(fs), effectiveAlphaOf(fs)))
end

-- Nothing tells a FontString that an ancestor's alpha moved, so the components
-- that fade a frame call this after they do (personal_resource_display/
-- opacity.lua, unitframesz/engine.lua applyOpacity). Coalesced to one pass per
-- frame, which collapses a whole party fading at once into a single walk and
-- lets the SetAlpha that triggered it settle before the read.
local refreshPending = false
function addon.FontPair.RefreshInheritedAlpha()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0, function()
        refreshPending = false
        for fs in pairs(addon.FontPair.registry) do
            refreshCopyAlpha(fs)
        end
    end)
end

-- Strip inline escape sequences so colors, textures, and hyperlinks cannot
-- leak into the black copy. Hyperlinks keep their visible text.
function addon.FontPair.StripEscapes(text)
    local s = text
    s = s:gsub("|H.-|h(.-)|h", "%1")      -- hyperlinks: keep the display text
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")  -- |cffRRGGBB / |cAARRGGBB color starts
    s = s:gsub("|r", "")                  -- color ends
    s = s:gsub("|T.-|t", "")              -- texture escapes
    s = s:gsub("|A.-|a", "")              -- atlas escapes
    return s
end

local function mirrorValue(fs, text)
    local companion = fs.__scootPair
    if not companion or not fs.__scootPairActive then return end
    if text == nil then
        companion:SetText("")
    elseif type(issecretvalue) == "function" and issecretvalue(text) then
        pcall(companion.SetText, companion, text)
    else
        companion:SetText(addon.FontPair.StripEscapes(tostring(text)))
    end
end

-- For paths where the final text is not an argument (SetFormattedText, the
-- initial sync). GetText can raise on secret-stamped strings; a failed read
-- leaves the companion as it was.
local function mirrorFromGetText(fs)
    if not fs.__scootPair or not fs.__scootPairActive then return end
    local ok, text = pcall(fs.GetText, fs)
    if ok then mirrorValue(fs, text) end
end

local function onClearText(fs)
    local companion = fs.__scootPair
    if companion then companion:SetText("") end
end

local function onShow(fs)
    local companion = fs.__scootPair
    if companion and fs.__scootPairActive then companion:Show() end
end

local function onHide(fs)
    local companion = fs.__scootPair
    if companion then companion:Hide() end
end

-- Alpha rides along too: holds and fades that hide a string by SetAlpha(0)
-- instead of Hide() must take the copy with them, or the black copy shows
-- alone. Region alpha multiplies the copy's 0.8 text alpha, so the copy is
-- never more visible than its original.
local function onSetAlpha(fs, alpha)
    local companion = fs.__scootPair
    if companion and fs.__scootPairActive then
        pcall(companion.SetAlpha, companion, alpha)
        addon.FontPair.RefreshInheritedAlpha()
    end
end

-- The taper reads the real string's color, and callers set it AFTER
-- ApplyFontStyle returns (personal_resource_display/text.lua:286), so the first
-- Apply always computes from a stale color. This is what corrects it.
local function onSetTextColor(fs)
    if fs.__scootPairActive then addon.FontPair.RefreshInheritedAlpha() end
end

-- hooksecurefunc is permanent, so install once per FontString and gate the
-- mirror on __scootPairActive; switching the style away disables mirroring
-- without needing to unhook.
local function installHooks(fs)
    if fs.__scootPairHooked then return end
    fs.__scootPairHooked = true
    hooksecurefunc(fs, "SetText", mirrorValue)
    hooksecurefunc(fs, "SetFormattedText", mirrorFromGetText)
    -- ClearText empties the string without going through SetText, so without
    -- this the copy keeps the old text: a black ghost name after the target
    -- goes away (unitframesz/engine.lua's "no unit" / "no name" paths).
    if fs.ClearText then hooksecurefunc(fs, "ClearText", onClearText) end
    hooksecurefunc(fs, "Show", onShow)
    hooksecurefunc(fs, "Hide", onHide)
    hooksecurefunc(fs, "SetAlpha", onSetAlpha)
    if fs.SetTextColor then hooksecurefunc(fs, "SetTextColor", onSetTextColor) end
end

-- Create or refresh the companion for fs. engineFlags is the decoded flag
-- string ApplyFontStyle is about to render the real string with.
function addon.FontPair.Apply(fs, face, size, engineFlags)
    local companion = fs.__scootPair
    if not companion then
        local parent = fs.GetParent and fs:GetParent()
        if not parent or not parent.CreateFontString then
            return -- nowhere to draw the copy; the base style still renders
        end
        companion = parent:CreateFontString(nil)
        fs.__scootPair = companion
        addon.FontPair.registry[fs] = companion
    end

    fs.__scootPairActive = true

    -- Depth, re-asserted every apply: the real string can move layers between
    -- applies, and a companion left on the old one would surface.
    --
    -- The copy goes on the LAYER BELOW the real string, not one sublevel below
    -- it. Two things ruled out the sublevel route:
    --
    --   CreateFontString takes (name, drawLayer, templateName) and nothing
    --   else -- unlike CreateTexture / CreateLine / CreateMaskTexture it has no
    --   subLevel argument (SimpleFrameAPIDocumentation.lua:78), so a fourth
    --   argument is swallowed and the copy lands at sublevel 0 beside the real
    --   string, where creation order decides and the copy always wins.
    --
    --   Fixing that with SetDrawLayer(layer, sublevel - 1) still drew the copy
    --   in front (measured 2026-08-30 on the UFZ name). Blizzard only ever uses
    --   a FontString sublevel to sort a string against a TEXTURE
    --   (Blizzard_PartyPoseUI.lua:309-310); nothing sorts two strings that way.
    --   Layers do sort, so use a layer.
    --
    -- Sublevel 7 within that lower layer keeps the copy above the art there --
    -- a bar fill, a backdrop -- so it still reads as a shadow on the text and
    -- not something buried under the frame.
    local layer, sublevel = "ARTWORK", 0
    if fs.GetDrawLayer then
        local ok, l, sl = pcall(fs.GetDrawLayer, fs)
        if ok then
            if l then layer = l end
            if type(sl) == "number" then sublevel = sl end
        end
    end
    local below = LAYER_BELOW[layer]
    if below then
        pcall(companion.SetDrawLayer, companion, below, 7)
    else
        -- Already on the bottom layer: sublevel is all that is left.
        pcall(companion.SetDrawLayer, companion, layer, math.max(sublevel - 1, -8))
    end

    if addon.ApplyFontFile then
        addon.ApplyFontFile(companion, face, size, engineFlags)
    end
    refreshCopyAlpha(fs)
    pcall(companion.SetShadowColor, companion, 0, 0, 0, 0)
    pcall(companion.SetShadowOffset, companion, 0, 0)

    -- Box-anchor so justified fixed-width strings mirror correctly.
    companion:ClearAllPoints()
    companion:SetPoint("TOPLEFT", fs, "TOPLEFT", OFFSET_X, OFFSET_Y)
    companion:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", OFFSET_X, OFFSET_Y)
    if fs.GetJustifyH then pcall(companion.SetJustifyH, companion, fs:GetJustifyH()) end
    if fs.GetJustifyV then pcall(companion.SetJustifyV, companion, fs:GetJustifyV()) end
    if fs.GetWordWrap and companion.SetWordWrap then
        pcall(companion.SetWordWrap, companion, fs:GetWordWrap())
    end

    installHooks(fs)
    mirrorFromGetText(fs)

    -- Alpha and Shown are secret aspects on any string an engine binding has
    -- claimed (SetDurationText adds Alpha, SetSpellName adds Shown), and a
    -- boolean test on a secret value is a hard error -- so read both without
    -- testing them. SetAlpha takes a secret argument from addon context;
    -- SetShown does not (AllowedWhenUntainted), and SetAlphaFromBoolean is the
    -- one that does, so a secret shown state rides on alpha instead.
    local okAlpha, alpha = pcall(fs.GetAlpha, fs)
    local okShown, shown = pcall(fs.IsShown, fs)
    local isSecret = type(issecretvalue) == "function" and issecretvalue
    if okShown and isSecret and isSecret(shown) then
        companion:Show()
        pcall(companion.SetAlphaFromBoolean, companion, shown, 1, 0)
    else
        if okAlpha then pcall(companion.SetAlpha, companion, alpha) end
        if okShown then pcall(companion.SetShown, companion, shown) end
    end
end

-- Called from ApplyFontStyle's non-paired path when a companion exists.
function addon.FontPair.Hide(fs)
    fs.__scootPairActive = nil
    local companion = fs.__scootPair
    if companion then
        companion:Hide()
        companion:SetText("")
    end
end
