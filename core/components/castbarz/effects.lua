--------------------------------------------------------------------------------
-- castbarz/effects.lua
-- Spark styles and cast-completion effects.
--
-- Both are "extra art anchored to the bar", both are user-selectable, and both
-- would have doubled the length of frames.lua. They share this file because they
-- share a rule: everything here is decoration, so every one of them has to be
-- safe to skip. A missing atlas, an unknown style name or a failed build leaves
-- the bar rendering exactly as it would with the feature turned off.
--
-- The no-geometry rule from frames.lua applies verbatim: nothing below reads the
-- bar's width, height or points. Sizes come from the DB via the same helpers the
-- layout pass uses, and positions come from anchoring to the fill texture.
--------------------------------------------------------------------------------

local addonName, addon = ...
local CBZ = addon.CastBarZ
local Anim = addon.Animations

local W8 = "Interface\\Buttons\\WHITE8X8"

--------------------------------------------------------------------------------
-- Shared helpers
--------------------------------------------------------------------------------

--- True if an atlas exists. SetAtlas fails silently on an unknown name, leaving
--- an untextured (invisible, or white) region, so every atlas below is gated.
local function HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end
CBZ._HasAtlas = HasAtlas

--- Desaturate a region, then tint it.
---
--- SetDesaturated collapses the source texels to luminance and SetVertexColor
--- modulates what is left, so together they turn any piece of borrowed art into a
--- tintable mask -- which is the only way Blizzard's green wisp and gold ember can
--- both come out in a Priest's white. Order matters: vertex color modulates
--- whatever the texture currently is, so desaturation has to be set first.
---
--- The support boolean SetDesaturated returns is deliberately ignored. On hardware
--- that cannot desaturate the tint still lands, just over the atlas's own hue --
--- a wrong color rather than a missing spark, which is the failure this whole file
--- is written to prefer.
local function Tint(tex, r, g, b, a)
    if tex.SetDesaturated then tex:SetDesaturated(true) end
    tex:SetVertexColor(r, g, b, a or 1)
end
CBZ._TintRegion = Tint

--- Read a { r, g, b } custom color setting, or nil if it has never been set.
---
--- Guarded type()-first for the same reason _GetCastTimeColor is: the value is
--- whatever the DB holds, and a profile edited by hand can hold anything.
local function CustomColor(key)
    local c = CBZ._GetSetting(key)
    if type(c) ~= "table" or type(c[1]) ~= "number" then return nil end
    return c[1], c[2], c[3]
end

--- Resolve one of the two flourish colors.
---
--- "spellName" (the default) takes the bright end of the unit's cast ramp -- the
--- same stop the last band of the spell name is drawn in -- which ties the moving
--- head and the finish flourish to the text they belong to instead of leaving
--- Blizzard's gold sitting on a colored bar. On your own bar that is your spec
--- color; on a target's it is that unit's class color, and flat red on an NPC.
---
--- Reads the cast's cached palette via _GetRamp, so a spark colored mid-cast
--- matches the name it is chasing rather than re-resolving against whatever the
--- unit is now -- and _GetRamp honours bar.rampOverride, which is what keeps the
--- settings-page preview deterministic without this function knowing it exists.
local function ResolveFlourishColor(bar, modeKey, colorKey)
    if CBZ._GetSetting(modeKey) == "custom" then
        local r, g, b = CustomColor(colorKey)
        if r then return r, g, b end
    end
    local ramp = CBZ._GetRamp(bar)
    local c = ramp and ramp[CBZ.NUM_BANDS]
    if not c then return 1, 1, 1 end
    return c[1], c[2], c[3]
end

function CBZ._ResolveSparkColor(bar)
    return ResolveFlourishColor(bar, "sparkColorMode", "sparkColor")
end

function CBZ._ResolveFinishColor(bar)
    return ResolveFlourishColor(bar, "completionColorMode", "completionColor")
end

--------------------------------------------------------------------------------
-- Spark styles
--------------------------------------------------------------------------------
-- Each builder receives (bar, geom) and creates its regions on bar.sparkFrame
-- (or, for `trail`, on bar.revealFrame -- see below). geom carries the layout
-- numbers already snapped by _LayoutBar, so no builder recomputes them and no
-- builder can disagree with the caps about what a pixel is.
--
-- Builders are called on every layout pass. They must therefore be idempotent:
-- each one keeps its regions in bar._sparkParts and reuses them rather than
-- creating a new texture per pass. Textures cannot be destroyed in this API, so
-- a builder that allocated per call would leak one region per settings change.

-- Ember trail geometry. The trail is a fraction of the bar so it scales with
-- width, but capped: on a GCD-length cast an uncapped fraction is most of the
-- bar, and a trail that long stops reading as a leading edge and starts reading
-- as a second fill.
local TRAIL_FRAC = 0.16
local TRAIL_MAX_PX = 32
local TRAIL_MIN_PX = 12

-- The trail's halo. NOT a radial glow, despite the name: Cast_Channel_WispGlow is
-- a light COLUMN, hard-edged top and bottom because Blizzard only ever shows it
-- through Cast_Channel_WispMask, and soft on the left and right where the wisp
-- tapers. Stretched wide and short that is exactly what a trail wants -- soft
-- ends, a flat top and bottom flush with the line. It is the wrong shape for
-- anything that needs to look round; see WIPE_GLOW_ATLAS.
local SOFT_GLOW_ATLAS = "Cast_Channel_WispGlow"

--- Mix a color toward white. The trail's core has to out-brighten the filled line
--- it sits on, and adding a color to itself only saturates it -- the hue is
--- already at full strength, so the sum clips back to nearly the same pixel.
--- Pushing toward white is the only headroom an additive layer has left.
local function Brighten(r, g, b, t)
    return r + (1 - r) * t, g + (1 - g) * t, b + (1 - b) * t
end

--- Fade a region out toward its trailing (left) edge.
---
--- SetGradient modulates whatever texture is already set, so it has to come after
--- SetAtlas / SetColorTexture -- a gradient applied first is silently dropped.
--- That is why callers re-set the texture on every layout pass rather than only
--- at creation.
local function ApplyLeftFade(tex, r, g, b, peak)
    if tex.SetGradient and CreateColor then
        tex:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, peak))
    else
        tex:SetVertexColor(r, g, b, peak)
    end
end

-- Caret geometry, as a fraction of cap height.
local CARET_SIZE_FRAC = 0.55

-- Scoot's own triangle, already used by the flyout control (ui/v2/controls/Flyout.lua:34).
-- The source points UP; SetRotation turns it.
--
-- It has to be a genuinely triangular source. Rotating a SetColorTexture region
-- does nothing visible -- every texel of a solid fill is the same color, so the
-- rotated result is pixel-identical to the unrotated one. A shaped texture is the
-- only way to get a triangle out of this API without shipping new art.
local CARET_TEXTURE = "Interface\\AddOns\\Scoot\\media\\textures\\flyout-nub"

local SparkBuilders = {}

--- Blizzard's pip. The one spark whose art carries its own hue -- the other three
--- are a solid fill or a white triangle, so they have always drawn in the cast's
--- color and there is nothing in them to desaturate. Tint() is what brings this
--- one into line with them.
function SparkBuilders.blizzard(bar, geom)
    local parts = bar._sparkParts
    local tex = parts.blizzardTex
    if not tex then
        tex = bar.sparkFrame:CreateTexture(nil, "OVERLAY", nil, 3)
        parts.blizzardTex = tex
    end
    if not HasAtlas("ui-castingbar-pip") then return false end

    tex:SetAtlas("ui-castingbar-pip")
    Tint(tex, CBZ._ResolveSparkColor(bar))
    tex:ClearAllPoints()
    tex:SetSize(8, math.max(geom.capH, geom.lineH * 4))
    tex:SetPoint("CENTER", bar.fillTex, "RIGHT", 0, 0)
    tex:Show()
    return true
end

--- A third end cap. The bar already says "a mark here, a mark there"; this makes
--- the cast head the same mark, moving. Sized a hair above the end caps so it
--- reads as the live one rather than as a cap that has come loose.
function SparkBuilders.tick(bar, geom)
    local parts = bar._sparkParts
    local outline = parts.tickOutline
    local tex = parts.tickTex
    if not tex then
        -- Outline first: same layer ordering as the caps, black under color.
        outline = bar.sparkFrame:CreateTexture(nil, "OVERLAY", nil, 2)
        tex = bar.sparkFrame:CreateTexture(nil, "OVERLAY", nil, 3)
        parts.tickOutline, parts.tickTex = outline, tex
    end

    local w = math.max(2, geom.capW + 1)
    local h = geom.capH + 2

    local r, g, b = CBZ._ResolveSparkColor(bar)
    tex:SetColorTexture(r, g, b, 1)
    tex:ClearAllPoints()
    tex:SetSize(w, h)
    tex:SetPoint("CENTER", bar.fillTex, "RIGHT", 0, 0)
    tex:Show()

    outline:SetColorTexture(0, 0, 0, 1)
    outline:ClearAllPoints()
    outline:SetPoint("TOPLEFT", tex, "TOPLEFT", -1, 1)
    outline:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 1, -1)
    outline:Show()
    return true
end

--- No head marker at all: the last stretch of the filled line runs hot and cools
--- back to the line color behind it.
---
--- Built on revealFrame rather than sparkFrame. revealFrame already clips to the
--- swept portion, which solves the left-edge overhang at low fill for free -- at
--- 5% progress a 32px trail would otherwise hang off the front of the bar. It
--- also puts the glow under the text instead of over it.
---
--- Two regions, not one. The first build was a single line-height rectangle in the
--- ramp color, and it was invisible in play: additive light of the same hue on top
--- of an already-saturated line clips straight back to the line, and the two pixels
--- it did change sat behind the spell name. So the halo is taller than the line to
--- clear the glyphs, and the core is pushed toward white to have somewhere to go.
function SparkBuilders.trail(bar, geom)
    local parts = bar._sparkParts
    local trail = parts.trailParts
    if not trail then
        -- ARTWORK 3/4: above the filled caps (2), below the bands (OVERLAY, on
        -- child frames). Halo created first so the core draws over it.
        local halo = bar.revealFrame:CreateTexture(nil, "ARTWORK", nil, 3)
        local core = bar.revealFrame:CreateTexture(nil, "ARTWORK", nil, 4)
        halo:SetBlendMode("ADD")
        core:SetBlendMode("ADD")
        trail = { halo, core }
        parts.trailParts = trail
    end

    local halo, core = trail[1], trail[2]
    local width = math.min(TRAIL_MAX_PX, math.max(TRAIL_MIN_PX, geom.barW * TRAIL_FRAC))
    local r, g, b = CBZ._ResolveSparkColor(bar)

    -- Halo: taller than the line so it reads past the glyphs sitting on top of it.
    if HasAtlas(SOFT_GLOW_ATLAS) then
        halo:SetAtlas(SOFT_GLOW_ATLAS, false)   -- false: our size wins
    else
        halo:SetColorTexture(r, g, b, 1)
    end
    ApplyLeftFade(halo, r, g, b, 0.75)
    halo:ClearAllPoints()
    halo:SetSize(width * 1.15, math.max(7, geom.capH * 0.8))
    halo:SetPoint("RIGHT", bar.fillTex, "RIGHT", 0, 0)
    halo:Show()

    -- Core: the line itself running hot, one pixel proud either side.
    local hr, hg, hb = Brighten(r, g, b, 0.6)
    core:SetColorTexture(hr, hg, hb, 1)
    ApplyLeftFade(core, hr, hg, hb, 1)
    core:ClearAllPoints()
    core:SetSize(width, geom.lineH + 2)
    core:SetPoint("RIGHT", bar.fillTex, "RIGHT", 0, 0)
    core:Show()
    return true
end

--- Two triangles bracketing the line and pointing at the fill position, the way a
--- video editor's playhead does. Sits entirely outside the line, so it is the only
--- style besides the trail that can never overlap a glyph.
function SparkBuilders.caret(bar, geom)
    local parts = bar._sparkParts
    local marks = parts.caretMarks
    if not marks then
        marks = {}
        for i = 1, 4 do
            -- 1,2 = outlines (sublevel 2); 3,4 = fills (sublevel 3).
            local mark = bar.sparkFrame:CreateTexture(nil, "OVERLAY", nil, i <= 2 and 2 or 3)
            mark:SetTexture(CARET_TEXTURE)
            -- Top marks point DOWN at the line, bottom marks point UP at it. A
            -- 180-degree turn maps the rect onto itself, so nothing is clipped.
            mark:SetRotation((i == 1 or i == 3) and math.pi or 0)
            marks[i] = mark
        end
        parts.caretMarks = marks
    end

    local size = math.max(4, geom.capH * CARET_SIZE_FRAC)
    -- Centre each triangle one half-height clear of the line's outer outline, so
    -- its inner tip lands just shy of the line without touching it.
    local gap = geom.lineH * 0.5 + 1 + size * 0.5

    local r, g, b = CBZ._ResolveSparkColor(bar)

    for i = 1, 4 do
        local mark = marks[i]
        local isOutline = i <= 2
        local isTop = (i == 1) or (i == 3)

        -- The outline is the same triangle drawn larger and black behind the
        -- fill. Scaling a shape is how you outline it when the API has no stroke.
        if isOutline then
            mark:SetVertexColor(0, 0, 0, 1)
            mark:SetSize(size + 2, size + 2)
        else
            mark:SetVertexColor(r, g, b, 1)
            mark:SetSize(size, size)
        end

        mark:ClearAllPoints()
        mark:SetPoint("CENTER", bar.fillTex, "RIGHT", 0, isTop and gap or -gap)
        mark:Show()
    end
    return true
end

CBZ.SPARK_STYLES = { "blizzard", "tick", "trail", "caret" }
table.freeze(CBZ.SPARK_STYLES)

--- Build (or rebuild) the spark for the bar's current style.
---
--- Every style's regions are hidden first, so switching styles cannot leave the
--- previous one's art on screen. Hiding rather than destroying is deliberate:
--- textures have no destructor, and a user flipping between styles in the
--- settings panel would otherwise leak a region per flip.
function CBZ._BuildSpark(bar, geom)
    bar._sparkParts = bar._sparkParts or {}
    -- Kept so _RecolorSpark can replay the same geometry at cast start without
    -- the layout pass having to run again.
    bar._sparkGeom = geom

    for _, part in pairs(bar._sparkParts) do
        if type(part) == "table" and not part.Hide then
            for _, sub in ipairs(part) do sub:Hide() end
        else
            part:Hide()
        end
    end

    local style = tostring(CBZ._GetSetting("sparkStyle") or "caret")
    if not SparkBuilders[style] then style = "caret" end

    -- Only `blizzard` can fail to build, and only if Blizzard renames the pip
    -- atlas out from under us. Fall back to `tick` rather than to nothing: an
    -- invisible spark is indistinguishable from showSpark being off, which sends
    -- anyone debugging it to the wrong setting. `tick` is pure geometry, so it is
    -- the one style that cannot fail for the same reason.
    if not SparkBuilders[style](bar, geom) then
        style = "tick"
        SparkBuilders.tick(bar, geom)
    end

    bar._sparkStyle = style
end

--- Re-apply the spark's color for the cast that is starting now.
---
--- The layout pass is the only thing that used to color the spark, and it runs on
--- settings changes -- so on a Target bar the color was resolved against whoever
--- the target happened to be when the panel was last touched, and never refreshed.
--- Under "spellName" that is visibly wrong: the name would take the new unit's
--- class color and the spark chasing it would keep the old one.
---
--- Replays _BuildSpark rather than duplicating each style's coloring. Builders are
--- already required to be idempotent and to reuse their regions (see the note
--- above SparkBuilders), so this allocates nothing -- it is the same call the
--- layout pass makes, with the geometry it was last given.
function CBZ._RecolorSpark(bar)
    if not bar._sparkGeom then return end
    CBZ._BuildSpark(bar, bar._sparkGeom)
end

--- Show or hide the spark regions that do not live on bar.sparkFrame.
---
--- Only the trail qualifies: it is built on revealFrame so it inherits the sweep
--- clip, which also puts it outside the reach of sparkFrame:SetShown(). Without
--- this it would stay lit with the spark switched off, and stay lit on a bar whose
--- cast has already ended. frames.lua calls this from _SetSparkShown rather than
--- reaching into _sparkParts itself.
function CBZ._SetDetachedSparkShown(bar, shown)
    local trail = bar._sparkParts and bar._sparkParts.trailParts
    if not trail then return end
    local on = shown and bar._sparkStyle == "trail"
    for _, tex in ipairs(trail) do
        tex:SetShown(on)
    end
end

--------------------------------------------------------------------------------
-- Completion effects
--------------------------------------------------------------------------------
-- All four borrow Blizzard's own cast-finish art (CastingBarFrame.xml). Their
-- offsets there are authored against a ~200x20 bar with chrome around it; Z
-- draws a 2px line, so every translation distance below is scaled down from
-- Blizzard's. The atlas choice is the cheap part -- the travel distances are
-- what needs tuning by eye.
--
-- Registered with addon.Animations under category "alert", which already gives
-- show-on-Play and hide-on-finish. Anim.Create returns a controller exposing
-- Play/Stop/SetSize/SetPoint/SetFrameLevel/Destroy (animations.lua).

local FX_PREFIX = "castBarZFinish"

-- Success glow: the direct sibling of the interrupt glow in frames.lua. Same
-- authoring (soft outer falloff, centred, additive, meant to bleed past the bar
-- it surrounds), so the padding tuned for the interrupt transfers here. The
-- deliberate rhyme is the point: red fuzz means it failed, warm fuzz means it
-- landed, and the shape says "the cast ended" either way.
local GLOW_ATLAS = "cast_empowered_outerglow"

Anim.Register({
    id = FX_PREFIX .. "Glow",
    category = "alert",
    buildAnimGroup = function(tex)
        if HasAtlas(GLOW_ATLAS) then
            tex:SetAtlas(GLOW_ATLAS, false)
        else
            tex:SetTexture(W8)
            tex:SetVertexColor(1.0, 0.88, 0.55)
        end
        tex:SetBlendMode("ADD")
        tex:SetAlpha(0)

        local ag = tex:CreateAnimationGroup()

        -- Straight to full, then fade -- the same shape as Blizzard's
        -- InterruptGlowAnim (CastingBarFrame.xml:186-189). A glow that ramps up
        -- reads as something starting; the cast has already ended.
        local pop = ag:CreateAnimation("Alpha")
        pop:SetFromAlpha(0)
        pop:SetToAlpha(1)
        pop:SetDuration(0.0)
        pop:SetOrder(1)

        local fade = ag:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        fade:SetDuration(0.40)
        fade:SetOrder(2)

        ag:SetToFinalAlpha(true)
        return ag
    end,
})

-- Shine wipe: CraftingFinish (CastingBarFrame.xml:162-165). One clean band of
-- light passing through. Blizzard reserves it for crafting and talent casts, so
-- it is unfamiliar on a combat cast -- which is an argument for it.
--
-- Blizzard translates it +180px, sized for a bar with a tall filled body to hide
-- the entry and exit. Ours travels the bar's own width instead, set at build
-- time by _LayoutFinishFX.
--
-- Two regions, like the ember trail and for a related reason: the shine alone is
-- a hard-edged band, and a hard-edged band crossing a 2px line has almost no area
-- to be bright in. The halo behind it is what gives the wipe something to light
-- up, and it blooms as it travels so the pass has a shape rather than a constant.
--
-- The halo is the interrupt glow's sibling, not the wisp the trail uses. The wisp
-- is a hard-topped column: at halo size it towered over the bar as a flat-ended
-- green slab, which is what the first screenshot of this effect caught. This atlas
-- is authored as an outer glow, so it is soft on every side, and frames.lua has
-- already proven it reads correctly against a bare line.
local WIPE_GLOW_ATLAS = "cast_empowered_outerglow"

Anim.Register({
    id = FX_PREFIX .. "Wipe",
    category = "alert",
    buildController = function(frame)
        return Anim.BuildMultiTextureController(frame, function(f, textures, animGroups)
            -- Halo first so the shine draws over it.
            local glow = f:CreateTexture(nil, "OVERLAY")
            if HasAtlas(WIPE_GLOW_ATLAS) then
                glow:SetAtlas(WIPE_GLOW_ATLAS, false)
            else
                glow:SetTexture(W8)
            end
            glow:SetBlendMode("ADD")
            glow:SetAlpha(0)
            glow:SetPoint("CENTER", f, "LEFT", 0, 0)
            textures[1] = glow

            local tex = f:CreateTexture(nil, "OVERLAY")
            if HasAtlas("Cast_Crafting_ShineWipe") then
                tex:SetAtlas("Cast_Crafting_ShineWipe", false)
            else
                tex:SetTexture(W8)
            end
            tex:SetBlendMode("ADD")
            tex:SetAlpha(0)
            tex:SetPoint("CENTER", f, "LEFT", 0, 0)
            textures[2] = tex

            -- Shine: the leading edge of the wipe. Its group is the lead one, so
            -- it is what decides the effect is over.
            local ag = tex:CreateAnimationGroup()

            local move = ag:CreateAnimation("Translation")
            move:SetDuration(0.45)
            move:SetSmoothing("NONE")
            move:SetOrder(1)

            local show = ag:CreateAnimation("Alpha")
            show:SetFromAlpha(0)
            show:SetToAlpha(1)
            show:SetDuration(0.0)
            show:SetOrder(1)

            local fade = ag:CreateAnimation("Alpha")
            fade:SetFromAlpha(1)
            fade:SetToAlpha(0)
            fade:SetDuration(0.18)
            fade:SetOrder(1)
            fade:SetStartDelay(0.27)

            ag:SetToFinalAlpha(true)
            animGroups[1] = ag

            -- Halo: same travel, but it swells on the way across and fades a beat
            -- behind the shine, so the light lingers where the shine has been.
            local gag = glow:CreateAnimationGroup()

            local gmove = gag:CreateAnimation("Translation")
            gmove:SetDuration(0.45)
            gmove:SetSmoothing("NONE")
            gmove:SetOrder(1)

            local bloom = gag:CreateAnimation("Scale")
            bloom:SetScaleFrom(0.75, 0.75)
            bloom:SetScaleTo(1.35, 1.35)
            bloom:SetDuration(0.45)
            bloom:SetOrder(1)

            local gshow = gag:CreateAnimation("Alpha")
            gshow:SetFromAlpha(0)
            gshow:SetToAlpha(1)
            gshow:SetDuration(0.08)
            gshow:SetOrder(1)

            local gfade = gag:CreateAnimation("Alpha")
            gfade:SetFromAlpha(1)
            gfade:SetToAlpha(0)
            gfade:SetDuration(0.22)
            gfade:SetStartDelay(0.23)
            gfade:SetOrder(1)

            gag:SetToFinalAlpha(true)
            animGroups[2] = gag

            -- Kept on the frame so the layout pass can set the travel distance and
            -- the sizes from the DB width without rebuilding the animations.
            f._wipeMove = move
            f._wipeGlowMove = gmove
            f._wipeTex = tex
            f._wipeGlow = glow
        end)
    end,
})

-- Wisp sweep: ChannelFinish (CastingBarFrame.xml:166-185). The only one of the
-- four that moves along the bar's own axis rather than off it, which is why it
-- suits a horizontal line better than the vertical effects do. Blizzard's
-- version masks the wisp to the bar body; on a 2px line there is no body to mask
-- to, so the mask is dropped and the travel distance does the shaping instead.
--
-- Blizzard's offsets (+50 / +40 / +20 on a 200px bar) are NOT copied, and the
-- first build's mistake was scaling them by barW/200 instead. That preserved the
-- fraction, and the fraction was the problem: their wisp only crosses a quarter of
-- their own bar, because ChannelFinish is a burst at the end of a channel, not a
-- sweep along it. Ours is a sweep, so the distance is the bar.
local SWEEP_OVERSHOOT = 16

Anim.Register({
    id = FX_PREFIX .. "Sweep",
    category = "alert",
    buildController = function(frame)
        return Anim.BuildMultiTextureController(frame, function(f, textures, animGroups)
            -- All three cross the whole bar; the choreography is in the stagger,
            -- not in the distance. The wisp leads and the two sparkles chase it,
            -- counter-rotating as they go.
            -- Sizes are Blizzard's own art at roughly two thirds scale. Theirs is
            -- meant to fill a 20px bar body; over a line it only has to be read
            -- against the line, and at full size it dwarfed what it was decorating.
            local specs = {
                { atlas = "Cast_Channel_WispGlow",    spin = 0,   size = 25, delay = 0.00 },
                { atlas = "Cast_Channel_Sparkles_01", spin = 45,  size = 15, delay = 0.06 },
                { atlas = "Cast_Channel_Sparkles_02", spin = -45, size = 15, delay = 0.12 },
            }
            local moves = {}

            for i, spec in ipairs(specs) do
                local tex = f:CreateTexture(nil, "OVERLAY")
                if HasAtlas(spec.atlas) then
                    tex:SetAtlas(spec.atlas, false)
                else
                    tex:SetTexture(W8)
                end
                tex:SetBlendMode("ADD")
                tex:SetAlpha(0)
                tex:SetSize(spec.size, spec.size)
                -- Half off the left edge, so the sweep enters rather than appears.
                tex:SetPoint("CENTER", f, "LEFT", -SWEEP_OVERSHOOT * 0.5, 0)
                textures[i] = tex

                local ag = tex:CreateAnimationGroup()

                -- Linear for every one of them: a sweep that eases is a sweep that
                -- has slowed down somewhere, and there is nothing on a cast bar for
                -- it to have slowed down for.
                local move = ag:CreateAnimation("Translation")
                move:SetDuration(0.45)
                move:SetSmoothing("NONE")
                move:SetStartDelay(spec.delay)
                move:SetOrder(1)
                moves[i] = move

                if spec.spin ~= 0 then
                    local spin = ag:CreateAnimation("Rotation")
                    spin:SetDegrees(spec.spin)
                    spin:SetDuration(0.45)
                    spin:SetStartDelay(spec.delay)
                    spin:SetOrder(1)
                end

                local show = ag:CreateAnimation("Alpha")
                show:SetFromAlpha(0)
                show:SetToAlpha(1)
                show:SetDuration(0.0)
                show:SetStartDelay(spec.delay)
                show:SetOrder(1)

                -- Fades over the back 40% only. Blizzard's fade covers two thirds
                -- of the travel, which was survivable at their distance and is not
                -- at ours -- the wisp would be spent by mid-bar and the sweep would
                -- read as stopping early all over again.
                local fade = ag:CreateAnimation("Alpha")
                fade:SetFromAlpha(1)
                fade:SetToAlpha(0)
                fade:SetDuration(0.18)
                fade:SetStartDelay(spec.delay + 0.27)
                fade:SetOrder(1)

                ag:SetToFinalAlpha(true)
                animGroups[i] = ag
            end

            -- The wisp leads; its group decides when the effect is over.
            f._sweepMoves = moves
            f._sweepOvershoot = SWEEP_OVERSHOOT
        end)
    end,
})

-- Rising embers: StandardFinish (CastingBarFrame.xml:155-161). Blizzard's own
-- success animation, and the loudest of the four. Their offsets (+220 for the
-- glow line, +100/+90/+25 for the flakes) are sized to clear a full cast bar;
-- scaled down here so the embers clear a line instead of leaving the screen.
Anim.Register({
    id = FX_PREFIX .. "Embers",
    category = "alert",
    buildController = function(frame)
        return Anim.BuildMultiTextureController(frame, function(f, textures, animGroups)
            local specs = {
                { atlas = "Cast_Standard_GlowLine",  dy = 46, size = 44, delay = 0.00, smooth = "NONE" },
                { atlas = "Cast_Standard_Flakes01",  dy = 30, size = 30, delay = 0.00, smooth = "IN"   },
                { atlas = "Cast_Standard_Flakes02",  dy = 26, size = 30, delay = 0.00, smooth = "OUT"  },
                { atlas = "Cast_Standard_Flakes03",  dy = 16, size = 30, delay = 0.12, smooth = "IN"   },
            }

            for i, spec in ipairs(specs) do
                local tex = f:CreateTexture(nil, "OVERLAY")
                if HasAtlas(spec.atlas) then
                    tex:SetAtlas(spec.atlas, false)
                else
                    tex:SetTexture(W8)
                end
                tex:SetBlendMode("ADD")
                tex:SetAlpha(0)
                tex:SetSize(spec.size, spec.size)
                tex:SetPoint("CENTER", f, "CENTER", 0, 0)
                textures[i] = tex

                local ag = tex:CreateAnimationGroup()

                local move = ag:CreateAnimation("Translation")
                move:SetOffset(0, spec.dy)
                move:SetDuration(0.45)
                move:SetSmoothing(spec.smooth)
                move:SetStartDelay(spec.delay)
                move:SetOrder(1)

                local show = ag:CreateAnimation("Alpha")
                show:SetFromAlpha(0)
                show:SetToAlpha(1)
                show:SetDuration(0.0)
                show:SetStartDelay(spec.delay)
                show:SetOrder(1)

                local fade = ag:CreateAnimation("Alpha")
                fade:SetFromAlpha(1)
                fade:SetToAlpha(0)
                fade:SetDuration(0.30)
                fade:SetStartDelay(spec.delay + 0.15)
                fade:SetOrder(1)

                ag:SetToFinalAlpha(true)
                animGroups[i] = ag
            end
        end)
    end,
})

-- Setting value -> registered animation id. "none" is absent on purpose: a
-- missing entry is the off switch, so no caller needs a special case for it.
local FX_IDS = {
    glow   = FX_PREFIX .. "Glow",
    wipe   = FX_PREFIX .. "Wipe",
    sweep  = FX_PREFIX .. "Sweep",
    embers = FX_PREFIX .. "Embers",
}

CBZ.COMPLETION_FX = { "none", "glow", "sweep", "wipe", "embers" }
table.freeze(CBZ.COMPLETION_FX)

-- How far past the bar each effect's frame extends. The glow is an outer glow
-- and has to overhang to show its falloff -- the same reason frames.lua pads the
-- interrupt glow. The others are contained.
local FX_PAD = {
    glow   = { x = 14, y = 9 },
    wipe   = { x = 0,  y = 12 },
    sweep  = { x = 0,  y = 8 },
    embers = { x = 0,  y = 4 },
}

--- Create or replace the bar's completion-effect controller.
---
--- Called from the layout pass, so it runs on every settings change. Rebuilding
--- only when the style actually changed matters: Anim.Create allocates a frame
--- and its textures, and a settings panel emits a layout pass per slider tick.
function CBZ._LayoutFinishFX(bar, geom)
    local style = tostring(CBZ._GetSetting("completionFX") or "glow")
    local animId = FX_IDS[style]

    if bar._finishFX and bar._finishStyle == style then
        CBZ._LayoutFinishFXFrame(bar, geom, style)
        return
    end

    if bar._finishFX then
        bar._finishFX:Destroy()
        bar._finishFX = nil
    end
    bar._finishStyle = style

    if not animId then return end

    local ok, ctrl = pcall(Anim.Create, animId, bar)
    if not ok or not ctrl then return end

    bar._finishFX = ctrl
    CBZ._LayoutFinishFXFrame(bar, geom, style)
end

--- Size and place the effect frame. Split out so a pure layout change (bar width
--- slider) does not tear down and rebuild the animation.
function CBZ._LayoutFinishFXFrame(bar, geom, style)
    local ctrl = bar._finishFX
    if not ctrl then return end

    local pad = FX_PAD[style] or { x = 0, y = 0 }
    local frame = ctrl:GetFrame()
    if not frame then return end

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", bar, "TOPLEFT", -pad.x, pad.y)
    frame:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", pad.x, -pad.y)

    -- Behind the bar's own textures, for the same reason the interrupt glow is:
    -- additive light on top of white glyphs at full strength erases the word.
    -- frames.lua reserves level - 1 by bumping the bar; this shares it.
    ctrl:SetFrameLevel(math.max(0, (bar.baseLevel or 1) - 1))

    -- Travel distances come from the bar's DB width, never from a read of it.
    -- Both horizontal effects cross the whole bar: Blizzard's own distances are
    -- authored for a burst at the end of a channel, not a pass along a line, so
    -- they are replaced rather than rescaled.
    if style == "wipe" and frame._wipeMove then
        local travel = geom.barW + 2 * (frame._wipeGlow and 8 or 0)
        frame._wipeMove:SetOffset(travel, 0)
        if frame._wipeGlowMove then
            frame._wipeGlowMove:SetOffset(travel, 0)
        end

        -- Back to the shine's original 2.5: the height complaints were never about
        -- this texture. A square halo 1.75x on top of it was, and enlarging the
        -- shine to compensate only made the pair taller together.
        local size = math.max(16, geom.capH * 2.5)
        if frame._wipeTex then
            frame._wipeTex:SetSize(size, size)
        end
        if frame._wipeGlow then
            -- Wider than the shine and SHORTER than it -- the halo blooms along the
            -- bar, which is the axis it is travelling, instead of away from it.
            -- Square was the mistake: scaling a square down to fix its height also
            -- throws away the width, which was never the problem.
            frame._wipeGlow:SetSize(size * 1.6, size * 0.8)
        end
    elseif style == "sweep" and frame._sweepMoves then
        local travel = geom.barW + (frame._sweepOvershoot or 0)
        for _, move in ipairs(frame._sweepMoves) do
            move:SetOffset(travel, 0)
        end
    end

    CBZ._RecolorFinishFX(bar)
end

--- The single owner of completion-effect color.
---
--- All eleven textures across the four effects are Blizzard's own art, authored in
--- its own gold and green, so every one of them is desaturated and tinted -- there
--- is no per-effect exception and no atlas whose hue is allowed to survive. One
--- loop over ctrl:GetTextures() covers both construction paths, since it returns
--- the multi-texture array or wraps the single texture (animations.lua:144-152).
---
--- Called twice: from the layout pass, and again from _PlayFinishFX so the effect
--- takes the palette of the cast that just landed rather than the one that was
--- current when the settings panel was last open. Same staleness _RecolorSpark
--- fixes, same reason.
---
--- It has to be the ONLY writer. The wipe's halo carries a deliberate 0.7 -- it is
--- meant to sit softer than the shine in front of it -- and a blanket pass running
--- after a per-style tint would silently restore it to full strength, which is why
--- that line moved out of _LayoutFinishFXFrame and down here.
function CBZ._RecolorFinishFX(bar)
    local ctrl = bar._finishFX
    if not ctrl then return end

    local textures = ctrl.GetTextures and ctrl:GetTextures()
    if not textures then return end

    local r, g, b = CBZ._ResolveFinishColor(bar)
    for _, tex in ipairs(textures) do
        Tint(tex, r, g, b)
    end

    local frame = ctrl:GetFrame()
    if frame and frame._wipeGlow then
        Tint(frame._wipeGlow, r, g, b, 0.7)
    end
end

--- Play the completion effect, if one is configured.
--- No-op when the setting is "none".
function CBZ._PlayFinishFX(bar)
    local ctrl = bar._finishFX
    if not ctrl then return end
    -- After Stop (which zeroes every texture's alpha) and before Play, so the
    -- effect takes the palette of the cast that has just landed. Vertex color and
    -- the animated alpha are independent channels, so recoloring here cannot
    -- disturb the fade the animation is about to drive.
    ctrl:Stop()
    CBZ._RecolorFinishFX(bar)
    ctrl:Play()
end

-- How long the completion effect waits before committing.
--
-- events.lua already coalesces the reports of one ending cast into a single
-- deferred resolution, so this is the second line of defence, not the first: it
-- covers a failure that arrives a few frames *after* a clean stop has already
-- resolved. Judged against the 0.35s hold the effect plays inside, the delay is
-- invisible, so it is priced entirely in insurance.
local FX_QUEUE_DELAY = 0.05

--- Play the completion effect shortly, unless the cast is re-resolved first.
---
--- Nothing about the end of a cast is decidable at the instant it is reported --
--- see HandleStop in events.lua. Committing the flourish immediately is how a
--- cancelled cast came to open with a success animation and then turn red.
---
--- bar.hideToken is the invalidation channel. Every resolution bumps it, so a
--- failure landing in the meantime cancels the celebration a clean stop had
--- queued, without either side needing to know the other exists.
function CBZ._QueueFinishFX(bar)
    if not bar._finishFX then return end
    local token = bar.hideToken
    C_Timer.After(FX_QUEUE_DELAY, function()
        if bar.hideToken ~= token then return end
        CBZ._PlayFinishFX(bar)
    end)
end

--- Halt any effect in flight. Called whenever a new cast starts and on the hide
--- leg of a finished one: spam-casting must not leave the previous cast's
--- celebration playing over the next cast's bar.
function CBZ._StopFinishFX(bar)
    local ctrl = bar._finishFX
    if not ctrl then return end
    ctrl:Stop()
end
