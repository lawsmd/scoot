--------------------------------------------------------------------------------
-- forever/castbars/painter.lua
-- The Classic cast bar's draw: the engine's painter (engine.lua,
-- PAINTER_CONTRACT).
--
-- A status bar inside UI-CastingBar-Border with the spell name above it. The
-- engine hands bar.progressBar the cast clock; the fill IS the bar, so nothing
-- here tracks progress. The spark is anchored to the fill texture's edge, which
-- places it without reading a value.
--
-- Secrets: the spell name is written with SetText and never read, measured or
-- reshaped. The interruptible flag goes through CBZ._PickColor. Nothing reads
-- the bar's own geometry; every dimension comes from the art spec or a setting.
--
-- Frame levels: bar +0 (background), progressBar +1, artFrame +2 (border, name,
-- spark, flash, cast time), so the border draws over the fill it frames.
--
-- The cast time readout is created here and owned by casttime.lua, which places,
-- styles and ticks it.
--------------------------------------------------------------------------------

local addonName, addon = ...

local CBZ = addon.CastBarZ
local Art = addon.CastBarArt
local BuildRegion = addon.UnitFrames.Art.BuildRegion

local COLORS = Art.Colors
local TIMING = Art.Timing

CBZ.HOLD_FAILED   = TIMING.holdFailed
CBZ.HOLD_COMPLETE = TIMING.holdComplete
CBZ.FADE_TIME     = TIMING.fade

local PREVIEW_SPELL_NAME = "Example Spell"
local PREVIEW_PROGRESS = 0.55

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function CBZ._CreateBar(row)
    local look = Art.Looks[row.look or "CLASSIC"]

    local bar = CreateFrame("Frame", row.frameName, UIParent)
    bar:SetSize(look.width, look.height)
    bar:SetPoint("CENTER")
    -- Reset Position applies the default in the bar's own units, which a scale
    -- above 100% can carry past the screen edge.
    bar:SetClampedToScreen(true)
    bar:Hide()
    addon.Strata.ApplyHUD(bar)

    bar.barKey = row.barKey
    bar.unitKey = row.unitKey
    bar.unit = row.token
    bar.look = look

    local level = bar:GetFrameLevel()

    local bg = bar:CreateTexture(nil, look.background.layer)
    bg:SetAllPoints(bar)
    local c = look.background.color
    bg:SetColorTexture(c[1], c[2], c[3], c[4])

    local progressBar = CreateFrame("StatusBar", nil, bar)
    progressBar:SetAllPoints(bar)
    progressBar:SetFrameLevel(level + 1)
    progressBar:SetStatusBarTexture(Art.Paths.fill)
    progressBar:SetStatusBarColor(COLORS.cast[1], COLORS.cast[2], COLORS.cast[3])
    progressBar:SetMinMaxValues(0, 1)
    progressBar:SetValue(0)
    bar.progressBar = progressBar

    local artFrame = CreateFrame("Frame", nil, bar)
    artFrame:SetAllPoints(bar)
    artFrame:SetFrameLevel(level + 2)
    bar.artFrame = artFrame

    bar.border = BuildRegion(artFrame, look.border)
    bar.borderLight = addon.Recolor.BuildLight(BuildRegion, artFrame, look.border)
    bar.flash = BuildRegion(artFrame, look.flash)

    -- The flash ramps in and stays: the engine's fade takes the whole bar down
    -- under it. Owned by the texture, so there is no OnUpdate.
    local flashIn = bar.flash:CreateAnimationGroup()
    flashIn:SetToFinalAlpha(true)
    local alpha = flashIn:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    alpha:SetDuration(TIMING.flashIn)
    bar.flashIn = flashIn

    -- CENTER on the fill's RIGHT edge. The fill is the elapsed part on a cast and
    -- the remaining part on a channel, so its right edge is the cast's position
    -- either way.
    local sparkDef = look.spark
    local spark = artFrame:CreateTexture(nil, sparkDef.layer, nil, sparkDef.sublevel)
    spark:SetTexture(sparkDef.path)
    spark:SetBlendMode(sparkDef.blend)
    spark:SetSize(sparkDef.w, sparkDef.h)
    spark:SetPoint("CENTER", progressBar:GetStatusBarTexture(), "RIGHT", 0, sparkDef.y)
    bar.spark = spark

    local textDef = look.text
    local text = artFrame:CreateFontString(nil, textDef.layer, textDef.fontObject)
    text:SetSize(textDef.w, textDef.h)
    text:SetPoint(textDef.point, bar, textDef.point, textDef.x, textDef.y)
    text:SetWordWrap(false)
    bar.text = text

    -- The cast time readout. Created even with the setting off: it is one region,
    -- and a conditional would have to be undone on every settings change, so
    -- casttime.lua hides it instead. It is placed and styled there too; the
    -- bootstrap font is not decoration, because SetText on a FontString that has
    -- no font raises. OVERLAY is the spark's layer, and the spark carries a
    -- sublevel, so a caret crossing an inside placement draws over the number.
    local castTimeText = artFrame:CreateFontString(nil, "OVERLAY")
    castTimeText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    castTimeText:SetWordWrap(false)
    castTimeText:Hide()
    bar.castTimeText = castTimeText

    return bar
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

-- The border art is one picture drawn for a 195 x 13 opening. Sliced, its end
-- caps and edge lines keep their drawn size and the opening alone grows.
local function SliceRegion(region, slice)
    if not (slice and region.SetTextureSliceMargins) then return end
    region:SetTextureSliceMargins(slice[1], slice[2], slice[3], slice[4])
    if Enum.UITextureSliceMode then
        region:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
    end
end

-- Idempotent, and computed from settings alone. The sliced regions grow by the
-- same units the bar does, so their TOP anchor holds at any size.
local function LayoutBar(bar)
    local look = bar.look
    local cfg = CBZ._GetUnitConfig(bar.unitKey)
    local barW = tonumber(cfg and cfg.barWidth) or look.width
    local barH = tonumber(cfg and cfg.barHeight) or look.height
    local growW, growH = barW - look.width, barH - look.height

    bar:SetScale(CBZ._GetBarScale(bar.unitKey))
    bar:SetSize(barW, barH)
    SliceRegion(bar.border, look.border.slice)
    SliceRegion(bar.borderLight, look.border.slice)
    SliceRegion(bar.flash, look.flash.slice)
    bar.border:SetSize(look.border.w + growW, look.border.h + growH)
    bar.borderLight:SetSize(look.border.w + growW, look.border.h + growH)
    bar.flash:SetSize(look.flash.w + growW, look.flash.h + growH)
    -- The text box is anchored at the bar's TOP, so it grows with the height
    -- as well: the name keeps its stock place against the bar's center.
    bar.text:SetSize(look.text.w + growW, look.text.h + growH)

    -- The spark is a glow across the bar's height, so it grows with the height
    -- and keeps its drawn width.
    local sparkRatio = barH / look.height
    bar.spark:SetHeight(look.spark.h * sparkRatio)
    bar.spark:ClearAllPoints()
    bar.spark:SetPoint("CENTER", bar.progressBar:GetStatusBarTexture(), "RIGHT", 0, look.spark.y * sparkRatio)
end

-- Frame Color. "forever" dresses the border in the Forever bronze; "classic"
-- leaves the file's own silver.
local function ApplyFrameColor(bar)
    local cfg = CBZ._GetUnitConfig(bar.unitKey)
    addon.Recolor.Apply(bar.border, bar.borderLight, (cfg and cfg.frameColor) ~= "classic", Art.BronzeLightAlpha)
end

-- A font setting left unset keeps the template's font object, which is what
-- makes the stock bar exact: GameFontHighlight carries its own shadow.
local function ApplyFont(bar)
    local face = CBZ._GetSetting("fontFace")
    local size = tonumber(CBZ._GetSetting("fontSize"))
    local style = CBZ._GetSetting("fontStyle")

    if face == nil and size == nil and style == nil then
        bar.text:SetFontObject(bar.look.text.fontObject)
        return
    end

    local _, stockSize = _G[bar.look.text.fontObject]:GetFont()
    addon.ApplyFontStyle(bar.text, addon.ResolveFontFace(face), size or stockSize or 12, style or "SHADOW")
end

function CBZ._ApplyBar(barKey)
    local bar = CBZ._bars[barKey]
    if not bar then return end

    if not CBZ._IsUnitEnabled(bar.unitKey) then
        CBZ._ResetBar(bar)
        return
    end

    LayoutBar(bar)
    ApplyFrameColor(bar)
    ApplyFont(bar)
    -- Anchors to the bar's own edges and reads no geometry, so it takes nothing
    -- from the layout pass above it.
    CBZ._LayoutCastTime(bar)
    CBZ._RefreshSparkVisibility(bar)
    CBZ._RestorePosition(bar)

    -- Edit Mode needs the frame visible to drag; otherwise the bar is shown only
    -- while a cast is in flight, which events.lua owns.
    if addon.EditMode.IsEditing() then
        CBZ._ShowEditModePreview(bar)
    elseif not bar.casting then
        bar:Hide()
    end
end

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

--- `text` may be a secret string. It is written and never read back.
function CBZ._SetText(bar, text)
    if type(text) == "nil" then
        CBZ._ClearText(bar)
        return
    end
    pcall(bar.text.SetText, bar.text, text)
end

-- ClearText, not SetText(""): it releases the FontString's secret text aspect.
function CBZ._ClearText(bar)
    if bar.text.ClearText then
        bar.text:ClearText()
    else
        bar.text:SetText("")
    end
end

--------------------------------------------------------------------------------
-- Spark
--------------------------------------------------------------------------------

function CBZ._SetSparkShown(bar, shown)
    bar.spark:SetShown(shown and true or false)
end

function CBZ._RefreshSparkVisibility(bar)
    CBZ._SetSparkShown(bar, CBZ._GetSetting("showSpark") ~= false)
end

--------------------------------------------------------------------------------
-- Cast-state looks
--------------------------------------------------------------------------------

-- pcall because _PickColor's components are secret on a restricted unit, and
-- whether SetStatusBarColor takes them is unmeasured. The player's own casts,
-- the only bar today, are always plain.
local function SetFill(bar, color)
    local pb = bar.progressBar
    if not pcall(pb.SetStatusBarColor, pb, color[1], color[2], color[3]) then
        local c = bar.startColor or COLORS.cast
        pb:SetStatusBarColor(c[1], c[2], c[3])
    end
end

--- The color this cast starts in. Cached so an interruptibility change mid-cast
--- has the right color to go back to.
function CBZ._BeginCastLook(bar)
    bar.startColor = bar.channelled and COLORS.channel or COLORS.cast
    SetFill(bar, bar.startColor)
end

--- Gray for a cast that cannot be interrupted. The flag may be secret, so the
--- engine's _PickColor chooses and hands back components the setter accepts.
function CBZ._ApplyInterruptLook(bar, notInterruptible)
    SetFill(bar, CBZ._PickColor(notInterruptible, COLORS.locked, bar.startColor or COLORS.cast))
end

--- The engine has already filled the bar and written the reason into the name.
function CBZ._ShowFailureLook(bar)
    SetFill(bar, COLORS.failed)
end

--- A finished cast goes green and flashes. The engine queues this after it has
--- bumped bar.hideToken; a token that has moved since means the cast was
--- superseded or turned out to be an interrupt.
function CBZ._QueueFinishFX(bar)
    local token = bar.hideToken
    C_Timer.After(0, function()
        if bar.hideToken ~= token then return end
        -- The engine also queues this for a cast that finished under a new one
        -- (spam-casting). The fill belongs to the new cast by then, and vanilla
        -- hid the flash at every cast start, so there is nothing to draw.
        if bar.casting then return end
        SetFill(bar, COLORS.finished)
        -- The flash is tinted with the color the cast STARTED in, as vanilla did
        -- (CastingBarFrame_SetUseStartColorForFlash).
        local c = bar.startColor or COLORS.cast
        bar.flash:SetVertexColor(c[1], c[2], c[3])
        bar.flash:SetAlpha(0)
        bar.flash:Show()
        bar.flashIn:Stop()
        bar.flashIn:Play()
    end)
end

function CBZ._StopFinishFX(bar)
    bar.flashIn:Stop()
    bar.flash:Hide()
end

-- The Classic bar has one flash and _StopFinishFX owns it; failure shows none.
function CBZ._StopFlash(bar) end

function CBZ._ResetCastLook(bar)
    bar.startColor = nil
    SetFill(bar, COLORS.cast)
end

--------------------------------------------------------------------------------
-- Edit Mode stand-in
--------------------------------------------------------------------------------

function CBZ._ShowEditModePreview(bar)
    CBZ._StopFinishFX(bar)
    CBZ._ResetCastLook(bar)
    CBZ._SetText(bar, PREVIEW_SPELL_NAME)
    CBZ._SetStaticProgress(bar, PREVIEW_PROGRESS)
    CBZ._RefreshSparkVisibility(bar)
    -- Nothing is casting in Edit Mode, so there is no duration to bind. Without a
    -- stand-in the readout is invisible at the moment you are placing the bar it
    -- sits beside. Blizzard hardcodes seconds = 10 for the same reason.
    CBZ._ShowCastTimePlaceholder(bar, CBZ.PREVIEW_CAST_TIME)
    bar:Show()
end
