--------------------------------------------------------------------------------
-- forever/castbars/painter.lua
-- The cast bar's draw: the engine's painter (engine.lua, PAINTER_CONTRACT),
-- generic over the look the player picked.
--
-- One bar is one frame with the engine's StatusBar in it. The art around the
-- fill is a SET per look (Art.Looks.CLASSIC, Art.Looks.MODERN), built the
-- first time its style is picked and shown or hidden as Cast Bar Style
-- changes, so a swap costs no rebuild and no second bar. What each look draws
-- is a table of functions in CBZ.Painters, keyed by the look: CLASSIC is in
-- this file, MODERN is modern.lua. The engine hands bar.progressBar the cast
-- clock; the fill IS the bar, so nothing here tracks progress. The spark is
-- anchored to the fill texture's edge, which places it without reading a
-- value.
--
-- Secrets: the spell name is written with SetText and never read, measured or
-- reshaped; a swap under a cast carries it across through the same two calls.
-- The interruptible flag goes through CBZ._PickColor on Classic and a
-- plain-boolean guard on Modern. Nothing reads the bar's own geometry; every
-- dimension comes from the art spec or a setting.
--
-- Frame levels: a set's backFrame +0 (background, plate), progressBar +1, a
-- set's artFrame +2 (border, name, spark, flash, and the cast time readout,
-- which moves to the shown set), so the border draws over the fill it frames.
-- A look may hang a clipping child off artFrame (+3) for effects that must
-- stop at the bar's edge (Modern's fxFrame, modern.lua).
--
-- The cast time readout is created here and owned by casttime.lua, which
-- places, styles and ticks it.
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
-- The look painters
--------------------------------------------------------------------------------

-- One table per look key. Every function takes the bar and its set, the table
-- of regions the look built on set.backFrame and set.artFrame:
--   build(bar, set, look)             the regions; must set set.spark and set.text
--   layout(bar, set, look, barW, barH, growW, growH)
--                                     sizes, after the bar's own
--   setFill(bar, set)                 the StatusBar texture and color for a bar
--                                     in no cast state
--   applyFrameColor(bar, set, cfg)    optional; what the Frame Color row does
--   sparkShown(bar, set, shown)       optional; what follows the spark
--   beginCast, applyInterrupt(flag), showFailure, queueFinish, stopFinish,
--   stopFlash, reset                  the cast-state names of PAINTER_CONTRACT,
--                                     dispatched below
CBZ.Painters = {}
local Painters = CBZ.Painters

-- What the look painters share.
local Util = {}
CBZ.PainterUtil = Util

-- A border drawn for a fixed opening. Sliced, its end caps and edge lines keep
-- their drawn size and the opening alone grows.
function Util.SliceRegion(region, slice)
    if not (slice and region.SetTextureSliceMargins) then return end
    region:SetTextureSliceMargins(slice[1], slice[2], slice[3], slice[4])
    if Enum.UITextureSliceMode then
        region:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
    end
end

-- A region that hugs the bar: `edges` is left, top, right, bottom, each an
-- offset from the bar's own corner, Blizzard's TOPLEFT and BOTTOMRIGHT pairs.
-- Two-point anchored, so it follows the bar's size on its own.
function Util.AnchorEdges(region, bar, edges)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", bar, "TOPLEFT", edges[1], edges[2])
    region:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", edges[3], edges[4])
end

-- CENTER on the fill's RIGHT edge. The fill is the elapsed part on a cast and
-- the remaining part on a channel, so its right edge is the cast's position
-- either way. Blizzard computes value / maxValue * width, which a secret
-- value forbids.
function Util.AnchorSpark(spark, progressBar, y)
    spark:ClearAllPoints()
    spark:SetPoint("CENTER", progressBar:GetStatusBarTexture(), "RIGHT", 0, y or 0)
end

function Util.BuildSpark(host, def, progressBar)
    local spark = host:CreateTexture(nil, def.layer, nil, def.sublevel)
    if def.atlas then
        spark:SetAtlas(def.atlas)
    else
        spark:SetTexture(def.path)
    end
    if def.blend then spark:SetBlendMode(def.blend) end
    spark:SetSize(def.w, def.h)
    Util.AnchorSpark(spark, progressBar, def.y)
    return spark
end

-- The spell name. `relPoint` lets a look hang the box off another edge of the
-- bar than the one the box names: Modern's TOP sits on the bar's BOTTOM.
function Util.BuildText(host, bar, def)
    local text = host:CreateFontString(nil, def.layer, def.fontObject)
    text:SetSize(def.w, def.h)
    text:SetPoint(def.point, bar, def.relPoint or def.point, def.x or 0, def.y or 0)
    text:SetWordWrap(false)
    return text
end

-- The fill's color, under pcall because _PickColor's components are secret on
-- a restricted unit, and whether SetStatusBarColor takes them is unmeasured.
-- The player's own casts, every bar today, are always plain.
function Util.SetFill(bar, color)
    local pb = bar.progressBar
    if not pcall(pb.SetStatusBarColor, pb, color[1], color[2], color[3]) then
        local c = bar.startColor or COLORS.cast
        pb:SetStatusBarColor(c[1], c[2], c[3])
    end
end

-- An alpha ramp owned by the texture it lights, held at the end: the engine's
-- fade takes the whole bar down under it, so there is no OnUpdate.
function Util.BuildFadeIn(texture, duration)
    local group = texture:CreateAnimationGroup()
    group:SetToFinalAlpha(true)
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    alpha:SetDuration(duration)
    return group
end

local function Painter(bar)
    return Painters[bar.look.key]
end

local function ClearFontString(fs)
    -- ClearText, not SetText(""): it releases the FontString's secret text aspect.
    if fs.ClearText then
        fs:ClearText()
    else
        fs:SetText("")
    end
end

--------------------------------------------------------------------------------
-- Construction: the bar, and a set of art per look
--------------------------------------------------------------------------------

local function ResolveLook(unitKey)
    local cfg = CBZ._GetUnitConfig(unitKey)
    return Art.LookForStyle(cfg and cfg.frameStyle)
end

-- The look's regions, built once per bar and kept: a style the player leaves
-- and comes back to is shown again, never rebuilt.
local function EnsureSet(bar, look)
    local set = bar.sets[look.key]
    if set then return set end
    local level = bar:GetFrameLevel()

    set = { look = look }
    -- Under the fill: the background, and Modern's plate.
    local backFrame = CreateFrame("Frame", nil, bar)
    backFrame:SetAllPoints(bar)
    backFrame:SetFrameLevel(level)
    set.backFrame = backFrame
    -- Over it: the border, the name, the spark, the flash, the effects.
    local artFrame = CreateFrame("Frame", nil, bar)
    artFrame:SetAllPoints(bar)
    artFrame:SetFrameLevel(level + 2)
    set.artFrame = artFrame

    Painters[look.key].build(bar, set, look)
    backFrame:Hide()
    artFrame:Hide()
    bar.sets[look.key] = set
    return set
end

-- Show the look's set and put the bar in its terms. A swap under a cast carries
-- the name across and repaints the state the engine holds (bar.channelled,
-- bar.tradeSkill, bar.interruptFlag), so the new art shows the cast in
-- flight; the engine's clock keeps running in the shared StatusBar underneath.
local function ActivateLook(bar, look)
    local set = EnsureSet(bar, look)
    if bar.set == set then return end
    local previous = bar.set

    for _, other in pairs(bar.sets) do
        if other ~= set then
            other.backFrame:Hide()
            other.artFrame:Hide()
        end
    end
    set.backFrame:Show()
    set.artFrame:Show()
    bar.set = set
    bar.look = look
    -- The readout rides the shown set, under the spark as Blizzard's does.
    if bar.castTimeText then bar.castTimeText:SetParent(set.artFrame) end

    local painter = Painters[look.key]
    painter.setFill(bar, set)
    -- The selection box re-fits the new art; a no-op before the bar registers.
    addon.EditMode.UpdateReach(bar, look.reach)

    if previous then
        local before = Painters[previous.look.key]
        before.stopFinish(bar, previous)
        before.stopFlash(bar, previous)
        if bar.casting then
            -- Written and never read: a secret name passes through both calls.
            local ok, name = pcall(previous.text.GetText, previous.text)
            if ok and type(name) ~= "nil" then
                pcall(set.text.SetText, set.text, name)
            end
            painter.beginCast(bar, set)
            painter.applyInterrupt(bar, set, bar.interruptFlag)
        end
        ClearFontString(previous.text)
    end
end

function CBZ._CreateBar(row)
    local look = ResolveLook(row.unitKey)

    -- A hosted bar is a child of the frame that places it (engine.lua,
    -- "hosted"), so it inherits that frame's scale, alpha, shown state and
    -- strata; a free bar stands on UIParent at the HUD strata.
    local parent = row.hosted and row.parent and row.parent() or UIParent
    local bar = CreateFrame("Frame", row.frameName, parent)
    bar:SetSize(look.width, look.height)
    bar:SetPoint("CENTER")
    bar:Hide()
    if not row.hosted then
        -- Reset Position applies the default in the bar's own units, which a
        -- scale above 100% can carry past the screen edge.
        bar:SetClampedToScreen(true)
        addon.Strata.ApplyHUD(bar)
    end

    bar.barKey = row.barKey
    bar.unitKey = row.unitKey
    bar.unit = row.token
    bar.sets = {}

    local level = bar:GetFrameLevel()

    -- The engine's StatusBar. Its texture is the look's, set at activation.
    local progressBar = CreateFrame("StatusBar", nil, bar)
    progressBar:SetAllPoints(bar)
    progressBar:SetFrameLevel(level + 1)
    progressBar:SetMinMaxValues(0, 1)
    progressBar:SetValue(0)
    bar.progressBar = progressBar

    ActivateLook(bar, look)

    -- The cast time readout, one string per bar: casttime.lua binds the cast
    -- clock to it and anchors it to the bar, and a look swap re-parents it.
    -- Created even with the setting off: it is one region, and a conditional
    -- would have to be undone on every settings change, so casttime.lua hides
    -- it instead. It is placed and styled there too; the bootstrap font is not
    -- decoration, because SetText on a FontString that has no font raises.
    -- OVERLAY is the spark's layer, and the spark carries a sublevel, so a
    -- caret crossing an inside placement draws over the number.
    local castTimeText = bar.set.artFrame:CreateFontString(nil, "OVERLAY")
    castTimeText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    castTimeText:SetWordWrap(false)
    castTimeText:Hide()
    bar.castTimeText = castTimeText

    return bar
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

-- Idempotent, and computed from settings alone. A size left unset is the
-- look's own.
local function LayoutBar(bar)
    local set, look = bar.set, bar.look
    local cfg = CBZ._GetUnitConfig(bar.unitKey)
    local barW = tonumber(cfg and cfg.barWidth) or look.width
    local barH = tonumber(cfg and cfg.barHeight) or look.height
    local growW, growH = barW - look.width, barH - look.height

    bar:SetScale(CBZ._GetBarScale(bar.unitKey))
    bar:SetSize(barW, barH)
    -- The text box grows with the width, and with the height where the look
    -- lets it: Classic's name is anchored at the bar's TOP and keeps its stock
    -- place against the bar's center that way; Modern's hangs off the bar's
    -- BOTTOM onto the plate and keeps its height.
    local textDef = look.text
    set.text:SetSize(textDef.w + growW, textDef.h + (textDef.growH ~= false and growH or 0))
    Painters[look.key].layout(bar, set, look, barW, barH, growW, growH)
end

-- The look's `reach`: how far the art stands past the bar, which the Edit Mode
-- selection box covers (core/components/castbarz/editmode.lua) at the bar's
-- registration; a look swap re-fits it through addon.EditMode.UpdateReach.
function CBZ._SelectionReach(bar)
    return bar.look and bar.look.reach
end

-- Frame Color, for a look that takes it: Classic's border file goes bronze or
-- stays silver. Modern draws the client's own frame as shipped.
local function ApplyFrameColor(bar)
    local painter = Painter(bar)
    if painter.applyFrameColor then
        painter.applyFrameColor(bar, bar.set, CBZ._GetUnitConfig(bar.unitKey))
    end
end

-- A font setting left unset keeps the look's font object, which is what makes
-- the stock bar exact: GameFontHighlight carries its own shadow. The Resource
-- Display's row answers size and style from its own font object, so its text
-- always takes the lower path.
local function ApplyFont(bar)
    local text = bar.set.text

    local face = CBZ._GetSetting("fontFace", bar.unitKey)
    local size = tonumber(CBZ._GetSetting("fontSize", bar.unitKey))
    local style = CBZ._GetSetting("fontStyle", bar.unitKey)

    if face == nil and size == nil and style == nil then
        text:SetFontObject(bar.look.text.fontObject)
        return
    end

    local _, stockSize = _G[bar.look.text.fontObject]:GetFont()
    addon.ApplyFontStyle(text, addon.ResolveFontFace(face), size or stockSize or 12, style or "SHADOW")
end

function CBZ._ApplyBar(barKey)
    local bar = CBZ._bars[barKey]
    if not bar then return end

    if not CBZ._IsUnitEnabled(bar.unitKey) then
        CBZ._ResetBar(bar)
        return
    end

    -- Cast Bar Style first: everything after lays out the set it names.
    ActivateLook(bar, ResolveLook(bar.unitKey))
    LayoutBar(bar)
    ApplyFrameColor(bar)
    ApplyFont(bar)
    -- Anchors to the bar's own edges and reads no geometry, so it takes nothing
    -- from the layout pass above it.
    CBZ._LayoutCastTime(bar)
    CBZ._RefreshSparkVisibility(bar)
    CBZ._RestorePosition(bar)
    -- The base layout and position are down; the Dynamic Layouts adapter puts
    -- its state back on top (forever/castbars/dynamic.lua).
    if CBZ.Dynamic then CBZ.Dynamic.Sync(bar) end

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
    local fs = bar.set.text
    pcall(fs.SetText, fs, text)
end

function CBZ._ClearText(bar)
    ClearFontString(bar.set.text)
end

--------------------------------------------------------------------------------
-- Spark
--------------------------------------------------------------------------------

function CBZ._SetSparkShown(bar, shown)
    shown = shown and true or false
    bar.set.spark:SetShown(shown)
    local painter = Painter(bar)
    if painter.sparkShown then painter.sparkShown(bar, bar.set, shown) end
end

-- A look whose spark is part of its art (the Resource Display's pip) keeps it
-- on whatever the Show Spark row says.
function CBZ._RefreshSparkVisibility(bar)
    local shown = bar.look.sparkAlways == true or CBZ._GetSetting("showSpark", bar.unitKey) ~= false
    CBZ._SetSparkShown(bar, shown)
end

--------------------------------------------------------------------------------
-- Cast-state looks, dispatched to the shown look's painter
--------------------------------------------------------------------------------

--- The look this cast starts in. Resolved once and cached on the bar, so an
--- interruptibility change mid-cast has the right one to go back to.
function CBZ._BeginCastLook(bar)
    Painter(bar).beginCast(bar, bar.set)
end

--- The flag may be secret; each painter digests it its own way.
function CBZ._ApplyInterruptLook(bar, notInterruptible)
    Painter(bar).applyInterrupt(bar, bar.set, notInterruptible)
end

--- The engine has already filled the bar and written the reason into the name.
function CBZ._ShowFailureLook(bar)
    Painter(bar).showFailure(bar, bar.set)
end

--- The engine queues this after it has bumped bar.hideToken; a token that has
--- moved since means the cast was superseded or turned out to be an interrupt.
function CBZ._QueueFinishFX(bar)
    local token = bar.hideToken
    C_Timer.After(0, function()
        if bar.hideToken ~= token then return end
        -- The engine also queues this for a cast that finished under a new one
        -- (spam-casting). The fill belongs to the new cast by then, and vanilla
        -- hid the flash at every cast start, so there is nothing to draw.
        if bar.casting then return end
        Painter(bar).queueFinish(bar, bar.set)
    end)
end

function CBZ._StopFinishFX(bar)
    Painter(bar).stopFinish(bar, bar.set)
end

function CBZ._StopFlash(bar)
    Painter(bar).stopFlash(bar, bar.set)
end

function CBZ._ResetCastLook(bar)
    Painter(bar).reset(bar, bar.set)
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

--------------------------------------------------------------------------------
-- The Classic look: a tinted fill inside the vanilla border
--------------------------------------------------------------------------------

local Classic = {}
Painters.CLASSIC = Classic

function Classic.build(bar, set, look)
    local bg = set.backFrame:CreateTexture(nil, look.background.layer)
    bg:SetAllPoints(bar)
    local c = look.background.color
    bg:SetColorTexture(c[1], c[2], c[3], c[4])
    set.background = bg

    local art = set.artFrame
    set.border = BuildRegion(art, look.border)
    set.borderLight = addon.Recolor.BuildLight(BuildRegion, art, look.border)
    set.flash = BuildRegion(art, look.flash)
    -- The flash ramps in and stays: the engine's fade takes the whole bar down
    -- under it.
    set.flashIn = Util.BuildFadeIn(set.flash, TIMING.flashIn)
    set.spark = Util.BuildSpark(art, look.spark, bar.progressBar)
    set.text = Util.BuildText(art, bar, look.text)
end

-- The sliced regions grow by the same units the bar does, so their TOP anchor
-- holds at any size.
function Classic.layout(bar, set, look, barW, barH, growW, growH)
    Util.SliceRegion(set.border, look.border.slice)
    Util.SliceRegion(set.borderLight, look.border.slice)
    Util.SliceRegion(set.flash, look.flash.slice)
    set.border:SetSize(look.border.w + growW, look.border.h + growH)
    set.borderLight:SetSize(look.border.w + growW, look.border.h + growH)
    set.flash:SetSize(look.flash.w + growW, look.flash.h + growH)

    -- The spark is a glow across the bar's height, so it grows with the height
    -- and keeps its drawn width.
    local sparkRatio = barH / look.height
    set.spark:SetHeight(look.spark.h * sparkRatio)
    Util.AnchorSpark(set.spark, bar.progressBar, look.spark.y * sparkRatio)
end

local SetFill = Util.SetFill

function Classic.setFill(bar, set)
    bar.progressBar:SetStatusBarTexture(Art.Paths.fill)
    SetFill(bar, bar.startColor or COLORS.cast)
end

-- "forever" dresses the border in the Forever bronze; "classic" leaves the
-- file's own silver.
function Classic.applyFrameColor(bar, set, cfg)
    addon.Recolor.Apply(set.border, set.borderLight, (cfg and cfg.frameColor) ~= "classic", Art.BronzeLightAlpha)
end

--- The color this cast starts in, cached on the bar.
function Classic.beginCast(bar, set)
    bar.startColor = bar.channelled and COLORS.channel or COLORS.cast
    SetFill(bar, bar.startColor)
end

--- Gray for a cast that cannot be interrupted. The flag may be secret, so the
--- engine's _PickColor chooses and hands back components the setter accepts.
function Classic.applyInterrupt(bar, set, notInterruptible)
    SetFill(bar, CBZ._PickColor(notInterruptible, COLORS.locked, bar.startColor or COLORS.cast))
end

function Classic.showFailure(bar, set)
    SetFill(bar, COLORS.failed)
end

--- A finished cast goes green and flashes. The flash is tinted with the color
--- the cast STARTED in, as vanilla did (CastingBarFrame_SetUseStartColorForFlash).
function Classic.queueFinish(bar, set)
    SetFill(bar, COLORS.finished)
    local c = bar.startColor or COLORS.cast
    set.flash:SetVertexColor(c[1], c[2], c[3])
    set.flash:SetAlpha(0)
    set.flash:Show()
    set.flashIn:Stop()
    set.flashIn:Play()
end

function Classic.stopFinish(bar, set)
    set.flashIn:Stop()
    set.flash:Hide()
end

-- The Classic bar has one flash and stopFinish owns it; failure shows none.
function Classic.stopFlash(bar, set) end

function Classic.reset(bar, set)
    bar.startColor = nil
    SetFill(bar, COLORS.cast)
end
