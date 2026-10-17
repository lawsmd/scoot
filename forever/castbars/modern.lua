--------------------------------------------------------------------------------
-- forever/castbars/modern.lua
-- The Modern look's painter: Blizzard's current cast bar, the one Forever
-- ships, drawn from its own atlases around the engine's fill (CBZ.Painters,
-- painter.lua). The names and geometry are Art.Looks.MODERN; the choreography
-- is here, each group a transcription of CastingBarFrameAnimsFXTemplate
-- (Blizzard_UIPanels_Game/Mainline/CastingBarFrame.xml:106-187) and
-- PlayInterruptAnims (Shared/CastingBarFrame.lua:721-739).
--
-- The fill is an atlas per cast state and white, never a tint: standard,
-- channel, crafting, uninterruptable, interrupted (CastingBarTypeInfo,
-- lua:16-84). A finished cast swaps to the state's `full` member, lights the
-- glow over the frame and plays the state's finish: the energy line and
-- flakes sweeping up through the bar on a cast, the wisp crossing it on a
-- channel, the shine wiping up through it on a profession's cast. A failed
-- cast snaps to the interrupted member, glows and shakes.
--
-- Every effect and the pip glows draw inside set.fxFrame, a frame clipping its
-- children to the bar mask's rect. Blizzard's masks carry CLAMPTOBLACKADDITIVE
-- in XML, so beyond their rect nothing shows; a mask made from Lua takes no
-- wrap mode for an atlas, so beyond its rect its edge pixels repeat, and the
-- bar mask's edge rows are the bar's bright rows, so the energy line showed
-- the whole way down the screen. The clip is the same cut as the clamp. The
-- two soft masks, the line's and the wisp's, keep the edge clamp; what that
-- shows is judged on screen.
--
-- Not carried: the icon and the shield, both off on Blizzard's own player bar;
-- the drop shadow, hidden there; the empowered pips and tiers; and the red
-- pip's beat before the fill snaps, since the engine fills at once.
--
-- The interruptible flag: a plain true picks the uninterruptable member. The
-- flag may be secret on another unit, and a texture cannot be chosen through
-- C_CurveUtil the way _PickColor chooses a color, so a secret flag draws as
-- interruptible: an uninterruptible cast shown as kickable wastes a kick,
-- which is a smaller failure than an error mid-cast. type() first,
-- issecretvalue() second (events.lua, PickColor).
--------------------------------------------------------------------------------

local addonName, addon = ...

local CBZ = addon.CastBarZ
local Util = CBZ.PainterUtil

local Modern = {}
CBZ.Painters.MODERN = Modern

-- The client shakes its own bar only while this CVar is above zero. Read
-- through pcall: a client without it shakes nothing.
local SHAKE_CVAR = "ShakeStrengthUI"
local DISABLED_FX_ALPHA = 0

--------------------------------------------------------------------------------
-- Regions
--------------------------------------------------------------------------------

-- A texture from a def. An edge-anchored def hugs the bar and stretches; a
-- point-anchored one is an FX member, drawn at its own size and scaled
-- (Blizzard's `useAtlasSize="true" scale="0.5"`), anchored to the bar as
-- Blizzard's are to theirs, whichever frame hosts it.
local function Tex(host, bar, def)
    local tex = host:CreateTexture(nil, def.layer, nil, def.sublevel)
    tex:SetAtlas(def.atlas, def.edges == nil)
    if def.scale then tex:SetScale(def.scale) end
    if def.blend then tex:SetBlendMode(def.blend) end
    if def.edges then
        Util.AnchorEdges(tex, bar, def.edges)
    else
        tex:SetPoint(def.point or "CENTER", bar, def.point or "CENTER", def.x or 0, def.y or 0)
    end
    if def.w and def.h then tex:SetSize(def.w, def.h) end
    if def.alpha then tex:SetAlpha(def.alpha) end
    if def.hidden then tex:Hide() end
    return tex
end

local function Mask(host, bar, def)
    local mask = host:CreateMaskTexture()
    mask:SetAtlas(def.atlas, true)
    if def.scale then mask:SetScale(def.scale) end
    mask:SetPoint(def.point or "CENTER", bar, def.point or "CENTER", def.x or 0, def.y or 0)
    return mask
end

--------------------------------------------------------------------------------
-- Animations
--------------------------------------------------------------------------------

local function Anim(group, kind, target, duration, order, delay)
    local a = group:CreateAnimation(kind)
    if target then a:SetTarget(target) end
    a:SetDuration(duration)
    if order then a:SetOrder(order) end
    if delay then a:SetStartDelay(delay) end
    return a
end

local function Translation(group, target, x, y, duration, order, delay, smoothing)
    local a = Anim(group, "Translation", target, duration, order, delay)
    a:SetOffset(x, y)
    if smoothing then a:SetSmoothing(smoothing) end
    return a
end

local function Alpha(group, target, from, to, duration, order, delay)
    local a = Anim(group, "Alpha", target, duration, order, delay)
    a:SetFromAlpha(from)
    a:SetToAlpha(to)
    return a
end

local function Rotation(group, target, degrees, duration, order, delay)
    local a = Anim(group, "Rotation", target, duration, order, delay)
    a:SetDegrees(degrees)
    return a
end

local function Scale(group, target, fromX, fromY, toX, toY, duration, order)
    local a = Anim(group, "Scale", target, duration, order)
    a:SetScaleFrom(fromX, fromY)
    a:SetScaleTo(toX, toY)
    return a
end

-- StandardFinish (xml:138-144): the energy line and three flakes sweep up
-- through the bar mask, looping while it plays and its targets shown only
-- then. One pass takes 0.5 s; the engine's hold and fade after a finished
-- cast are 0.5 s together, so the line crosses once.
local function BuildStandardFinish(bar, set, look)
    local host, fx = set.fxFrame, look.fx
    local line = Tex(host, bar, fx.energyGlow)
    line:AddMaskTexture(Mask(host, bar, fx.energyMask))
    line:AddMaskTexture(set.barMask)
    local targets = { line }
    for i, def in ipairs(fx.flakes) do
        local flake = Tex(host, bar, def)
        flake:AddMaskTexture(set.barMask)
        targets[i + 1] = flake
    end

    local group = host:CreateAnimationGroup()
    group:SetLooping("REPEAT")
    Translation(group, line, 0, 220, 0.5)
    Translation(group, targets[2], 0, 100, 0.5, nil, nil, "IN")
    Translation(group, targets[3], 0, 90, 0.5, nil, nil, "OUT")
    Translation(group, targets[4], 0, 25, 0.5, nil, 0.25, "IN")
    Alpha(group, line, 0, 1, 0)

    local function hide() for _, t in ipairs(targets) do t:Hide() end end
    group:SetScript("OnPlay", function() for _, t in ipairs(targets) do t:Show() end end)
    group:SetScript("OnStop", hide)
    group:SetScript("OnFinished", hide)
    hide()
    set.standardFinish = group
end

-- CraftingFinish (xml:145-148), once: a shine wipes 180 units up through the
-- bar, shaped by its own soft mask inside the bar mask. Blizzard's CraftingGlow
-- sparkFx names no region, so nothing trails the pip on a profession's cast.
local function BuildCraftingFinish(bar, set, look)
    local host, fx = set.fxFrame, look.fx
    local shine = Tex(host, bar, fx.shine)
    shine:AddMaskTexture(Mask(host, bar, fx.craftingMask))
    shine:AddMaskTexture(set.barMask)

    local group = host:CreateAnimationGroup()
    group:SetToFinalAlpha(true)
    Translation(group, shine, 0, 180, 0.5, 1)
    Alpha(group, shine, 0, 1, 0)
    set.craftingFinish = group
    set.craftingShine = shine
end

-- ChannelFinish (xml:149-168), once: a wisp and two sparkles cross the bar
-- left to right while the base glow stretches to four times its width and
-- fades. Every member starts at alpha 0 and ends there.
local function BuildChannelFinish(bar, set, look)
    local host, fx = set.fxFrame, look.fx
    local baseGlow = Tex(host, bar, fx.baseGlow)
    local wispGlow = Tex(host, bar, fx.wispGlow)
    local wispMask = Mask(host, bar, fx.wispMask)
    wispGlow:AddMaskTexture(wispMask)
    local sparkles01 = Tex(host, bar, fx.sparkles01)
    local sparkles02 = Tex(host, bar, fx.sparkles02)
    local targets = { baseGlow, wispGlow, sparkles01, sparkles02 }
    for _, t in ipairs(targets) do t:AddMaskTexture(set.barMask) end

    local group = host:CreateAnimationGroup()
    group:SetToFinalAlpha(true)
    Translation(group, wispMask, 50, 0, 0.5)
    Translation(group, sparkles01, 40, 0, 0.5, nil, nil, "IN")
    Translation(group, sparkles02, 20, 0, 0.5, nil, 0.1, "IN_OUT")
    Rotation(group, sparkles01, 45, 0.5)
    Rotation(group, sparkles02, -45, 0.5, nil, 0.1)
    Alpha(group, baseGlow, 0, 0.5, 0.3, 1)
    Alpha(group, wispGlow, 0, 1, 0, 1)
    Alpha(group, sparkles01, 0, 1, 0, 1)
    Alpha(group, sparkles02, 0, 1, 0, 1)
    Alpha(group, baseGlow, 0.5, 0, 0.2, 2)
    Alpha(group, wispGlow, 1, 0, 0.5, 2)
    Alpha(group, sparkles01, 1, 0, 0.5, 2)
    Alpha(group, sparkles02, 1, 0, 0.5, 2)
    Scale(group, baseGlow, 1, 1, 4, 1, 0.5)
    set.channelFinish = group
    set.channelFinishTargets = targets
end

-- InterruptGlowAnim (xml:169-172): the outer glow lit at once and gone over a
-- second. InterruptShakeAnim (:173-179): five translations on the whole bar,
-- the first a tenth of a second of rest, then four jolts a twentieth apart.
local function BuildInterrupt(bar, set, look)
    local glow = Tex(set.backFrame, bar, look.fx.interruptGlow)
    set.interruptGlow = glow
    local glowAnim = set.backFrame:CreateAnimationGroup()
    glowAnim:SetToFinalAlpha(true)
    Alpha(glowAnim, glow, 0, 1, 0, 1)
    Alpha(glowAnim, glow, 1, 0, 1.0, 2)
    set.interruptGlowAnim = glowAnim

    local shake = bar:CreateAnimationGroup()
    Translation(shake, nil, 0, 0, 0.1, 1)
    Translation(shake, nil, -1, 1, 0, 2, 0.05)
    Translation(shake, nil, 1, -2, 0, 3, 0.05)
    Translation(shake, nil, 1, 2, 0, 4, 0.05)
    Translation(shake, nil, -1, -1, 0, 5, 0.05)
    set.shake = shake
end

local function ShakeAllowed()
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    local ok, value = pcall(get, SHAKE_CVAR)
    return ok and (tonumber(value) or 0) > 0
end

--------------------------------------------------------------------------------
-- The painter
--------------------------------------------------------------------------------

function Modern.build(bar, set, look)
    local back, art = set.backFrame, set.artFrame

    -- Under the fill: the plate the name sits on, the background inside the
    -- frame; the interrupt glow between them.
    set.textPlate = Tex(back, bar, look.textPlate)
    set.background = Tex(back, bar, look.background)

    -- Over it: the frame, the flash the finish lights, the pip.
    set.border = Tex(art, bar, look.border)
    set.flash = Tex(art, bar, look.flash)
    set.flashIn = Util.BuildFadeIn(set.flash, look.flash.fadeIn)
    set.spark = Util.BuildSpark(art, look.spark, bar.progressBar)

    -- The clip the effects draw inside, the bar mask's rect (see the header):
    -- a line sweeping 220 units up is seen only as it crosses the bar. The
    -- mask shapes what the clip admits. Sized by layout.
    local fxFrame = CreateFrame("Frame", nil, art)
    fxFrame:SetPoint("CENTER", bar, "CENTER", 0, 0)
    fxFrame:SetClipsChildren(true)
    set.fxFrame = fxFrame
    local barMask = fxFrame:CreateMaskTexture()
    barMask:SetAtlas(look.barMask.atlas)
    barMask:SetAllPoints(fxFrame)
    set.barMask = barMask

    -- What trails the pip, inside the clip and over the pip, as Blizzard's
    -- sublevels order them.
    set.sparkFx = {}
    for kind, def in pairs(look.sparkFx) do
        local fx = fxFrame:CreateTexture(nil, def.layer, nil, def.sublevel)
        fx:SetAtlas(def.atlas)
        if def.blend then fx:SetBlendMode(def.blend) end
        fx:SetSize(def.w, def.h)
        fx:SetPoint("RIGHT", set.spark, "LEFT", def.x, 0)
        fx:AddMaskTexture(barMask)
        fx:Hide()
        set.sparkFx[kind] = fx
    end

    set.text = Util.BuildText(art, bar, look.text)

    BuildStandardFinish(bar, set, look)
    BuildCraftingFinish(bar, set, look)
    BuildChannelFinish(bar, set, look)
    BuildInterrupt(bar, set, look)
end

-- The pip spans the bar's height and keeps its drawn width; the clip, and the
-- mask filling it, grow with the bar; the edge-anchored atlases follow the bar
-- on their own.
function Modern.layout(bar, set, look, barW, barH, growW, growH)
    local ratio = barH / look.height
    set.spark:SetHeight(look.spark.h * ratio)
    Util.AnchorSpark(set.spark, bar.progressBar, look.spark.y * ratio)
    set.fxFrame:SetSize(look.barMask.w + growW, look.barMask.h + growH)
end

local function FillInfo(set, kind)
    return set.look.fill[kind] or set.look.fill.standard
end

-- The finish a kind plays (CastingBarTypeInfo's finishAnim).
local function FinishFor(set, kind)
    if kind == "channel" then return set.channelFinish end
    if kind == "crafting" then return set.craftingFinish end
    return set.standardFinish
end

local function SetFillAtlas(bar, atlas)
    local pb = bar.progressBar
    pb:SetStatusBarTexture(atlas)
    pb:SetStatusBarColor(1, 1, 1)
end

local function ShowSparkFx(set, kind)
    for k, fx in pairs(set.sparkFx) do
        fx:SetShown(k == kind)
    end
end

function Modern.setFill(bar, set)
    SetFillAtlas(bar, FillInfo(set, bar.castKind).filling)
end

-- What trails the pip follows the pip: the shown kind's glow while the spark
-- is up, nothing while it is down. Before a cast names its kind, the standard
-- glow, which is what the Edit Mode stand-in shows.
function Modern.sparkShown(bar, set, shown)
    ShowSparkFx(set, shown and (bar.castKind or "standard") or nil)
end

--- The kind this cast starts as, cached on the bar: a profession's cast ahead
--- of a channel ahead of a plain cast, GetEffectiveType's order (lua:334-350).
function Modern.beginCast(bar, set)
    bar.castKind = (bar.tradeSkill and "crafting") or (bar.channelled and "channel") or "standard"
    SetFillAtlas(bar, FillInfo(set, bar.castKind).filling)
    ShowSparkFx(set, set.spark:IsShown() and bar.castKind or nil)
end

--- A profession's cast keeps its member whatever the flag says, as
--- GetEffectiveType ranks it before the interrupt test.
function Modern.applyInterrupt(bar, set, notInterruptible)
    if bar.castKind == "crafting" then return end
    local locked = type(notInterruptible) == "boolean"
        and not (issecretvalue and issecretvalue(notInterruptible))
        and notInterruptible
    SetFillAtlas(bar, FillInfo(set, locked and "uninterruptable" or bar.castKind).filling)
end

--- The engine has snapped the fill to full and written the reason into the
--- name; the fill goes to the interrupted member, the glow lights, the bar
--- shakes where the client allows.
function Modern.showFailure(bar, set)
    SetFillAtlas(bar, set.look.fill.interrupted.full)
    ShowSparkFx(set, nil)
    set.interruptGlowAnim:Stop()
    set.interruptGlowAnim:Play()
    if ShakeAllowed() then
        set.shake:Stop()
        set.shake:Play()
    end
end

--- A finished cast: the kind's full member, the glow over the frame ramping
--- in, and the kind's finish playing until the engine's fade hides the bar.
function Modern.queueFinish(bar, set)
    local info = FillInfo(set, bar.castKind)
    SetFillAtlas(bar, info.full)
    ShowSparkFx(set, nil)
    if info.glow then
        set.flash:SetAtlas(info.glow)
        set.flash:SetAlpha(0)
        set.flash:Show()
        set.flashIn:Stop()
        set.flashIn:Play()
    end
    local finish = FinishFor(set, bar.castKind)
    finish:Stop()
    finish:Play()
end

function Modern.stopFinish(bar, set)
    set.flashIn:Stop()
    set.flash:Hide()
    set.standardFinish:Stop()
    set.craftingFinish:Stop()
    set.channelFinish:Stop()
    set.craftingShine:SetAlpha(DISABLED_FX_ALPHA)
    for _, t in ipairs(set.channelFinishTargets) do t:SetAlpha(DISABLED_FX_ALPHA) end
end

function Modern.stopFlash(bar, set)
    set.interruptGlowAnim:Stop()
    set.interruptGlow:SetAlpha(DISABLED_FX_ALPHA)
    set.shake:Stop()
end

function Modern.reset(bar, set)
    bar.castKind = nil
    SetFillAtlas(bar, set.look.fill.standard.filling)
    ShowSparkFx(set, nil)
end
