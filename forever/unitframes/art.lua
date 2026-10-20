--------------------------------------------------------------------------------
-- forever/unitframes/art.lua
-- What every unit frame's art shares: the texture paths, the region format
-- and its reader, and the border style. One spec per frame shape lives beside
-- this file (artplayer, arttarget, arttot, artpet) and registers into
-- Art.Frames under the Camelot style; the Modern specs under modern/ register
-- under theirs, and the Classic style reads a copy of the Camelot ones
-- (Art.Spec).
--
-- Every number in a spec is Blizzard's own, read out of the XML rather than
-- measured off a screenshot, so the rebuild is a transcription. The Classic
-- source is the classic_era branch of the UI source mirror:
--
--   git show origin/classic_era:Interface/AddOns/Blizzard_UnitFrame/Classic/<file>.xml
--
-- and the Modern source its live branch, the 12.1.5 build Forever inherits.
--
-- Every stock path below resolves by name in a 12.x client. The Modern specs
-- name no file: their art is atlas members by retail's names, which Forever
-- ships its own bronze behind.
--
-- Two conventions carried over from the XML:
--
--   coords = { left, right, top, bottom } in SetTexCoord order. Where left is
--   GREATER than right the texture is mirrored horizontally. The player's
--   border and flash are authored that way, and the values are kept as written
--   rather than "corrected".
--
--   A region anchors def.point to def.relPoint (def.point when absent) on its
--   host, with a negative Y running down the frame, which is how the XML
--   anchors them.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Art = {}
addon.UnitFrames.Art = Art

-- style -> key -> spec, filled by the art*.lua files: the Classic specs under
-- camelot, the Modern ones under modern (the modern/ folder beside them).
-- The classic set is copied from the camelot one on first use.
Art.Frames = { camelot = {}, classic = {}, modern = {} }

-- The Classic style draws the Camelot specs as vanilla placed them: a copy
-- with every nudge taken out, the level disc's among them (artplayer.lua,
-- DISC_NUDGE), so each region and string sits on Blizzard's own anchor.
local function withoutNudges(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for field, v in pairs(value) do
        if field ~= "nudge" and field ~= "DiscNudge" then copy[field] = withoutNudges(v) end
    end
    return copy
end

--- The spec a style draws a frame from, or nil.
function Art.Spec(style, key)
    if style == "classic" and not Art.Frames.classic[key] and Art.Frames.camelot[key] then
        Art.Frames.classic[key] = withoutNudges(Art.Frames.camelot[key])
    end
    return Art.Frames[style] and Art.Frames[style][key]
end

--------------------------------------------------------------------------------
-- Paths
--------------------------------------------------------------------------------

local TARGETING = "Interface\\TargetingFrame\\"
local CHARACTER = "Interface\\CharacterFrame\\"
local GROUP     = "Interface\\GroupFrame\\"

Art.Paths = {
    border       = TARGETING .. "UI-TargetingFrame",
    borderElite  = TARGETING .. "UI-TargetingFrame-Elite",
    borderRare   = TARGETING .. "UI-TargetingFrame-Rare",
    borderMinus  = TARGETING .. "UI-TargetingFrame-Minus",
    borderToT    = TARGETING .. "UI-TargetofTargetFrame",
    borderSmall  = TARGETING .. "UI-SmallTargetingFrame",
    borderSmallNoMana = TARGETING .. "UI-SmallTargetingFrame-NoMana",
    flash        = TARGETING .. "UI-TargetingFrame-Flash",
    attackBG     = TARGETING .. "UI-TargetingFrame-AttackBackground",
    nameBG       = TARGETING .. "UI-TargetingFrame-LevelBackground",
    skull        = TARGETING .. "UI-TargetingFrame-Skull",
    raidIcons    = TARGETING .. "UI-RaidTargetingIcons",
    statusBar    = TARGETING .. "UI-StatusBar",
    playerStatus = CHARACTER .. "UI-Player-Status",
    stateIcon    = CHARACTER .. "UI-StateIcon",
    playTime     = CHARACTER .. "UI-Player-PlayTimeTired",
    petAttack    = CHARACTER .. "UI-Player-AttackStatus",
    petHappiness = "Interface\\PetPaperDollFrame\\UI-PetHappiness",
    leaderIcon   = GROUP .. "UI-Group-LeaderIcon",
    masterLooter = GROUP .. "UI-Group-MasterLooter",
    -- The disc the portraits and the minimap are cut with; a backdrop that
    -- names it as `mask` draws as a circle.
    circleMask   = CHARACTER .. "TempPortraitAlphaMask",
}

-- Draw order for the art swatch dump. A path that fails to resolve draws blank,
-- which is the only way a missing file announces itself.
Art.ManifestOrder = {
    "border", "borderElite", "borderRare", "borderMinus",
    "borderToT", "borderSmall", "borderSmallNoMana",
    "flash", "attackBG", "nameBG", "skull", "raidIcons", "statusBar",
    "playerStatus", "stateIcon", "playTime",
    "petAttack", "petHappiness",
    "leaderIcon", "masterLooter",
    "circleMask",
}

--------------------------------------------------------------------------------
-- Backdrops
--------------------------------------------------------------------------------
-- The dark brown leather behind the name and the level, cut from the Legacy
-- pane's page background, so the frames read as Camelot's beside Blizzard's
-- own panes. A Camelot addition: vanilla draws a black fill at 0.5 behind the
-- name and nothing behind the level, whose disc is baked into the border art
-- as black glass at about 55 percent with an opaque sheen across it. That is
-- why the disc backdrop draws OVER the border, masked to a circle, the way
-- vanilla's own attack backing covers the ring in combat.
--
-- Each crop is a rect in the member's own pixels, taken at 1:1 from the flat
-- interior (columns 125 to 806, rows 60 to 503). The alpha a region is built
-- at is the registered default (text.lua); Text.ApplyBackdrop writes the
-- stored one over it, and the reaction strip's alpha is its own setting there.
--
-- The crops measure about #1c120c, which reads as black at 20 pixels tall. A
-- region marked `lift` gets an additive copy of itself one sublevel up, tinted
-- by Text.BACKDROP_LIFT, so the leather keeps its grain and reads brown.

Art.BACKDROP_ALPHA = addon.UnitFrames.Text.BACKDROP_OPACITY / 100
-- The card's leather at #170a02, drawn flat when the atlas does not resolve.
Art.BACKDROP_FALLBACK = { 0.09, 0.04, 0.01 }

local LEATHER = "Legacy-Tree-Frame-background"
Art.BACKDROP_SOURCE = {
    strip      = { name = LEATHER, rect = { 300, 200, 419, 219 } },   -- 119x19
    disc       = { name = LEATHER, rect = { 300, 240, 320, 260 } },   -- 20x20
    smallStrip = { name = LEATHER, rect = { 300, 280, 346, 295 } },   -- 46x15
}

--------------------------------------------------------------------------------
-- The reader
--------------------------------------------------------------------------------

-- Point a texture at a sub-rect of an atlas member. rect = { left, top,
-- right, bottom } in the member's pixels. Chrome.AtlasSource is read at call
-- time: ui/v2/Chrome.lua loads after this file, and nothing builds a frame
-- before world entry. Returns false when the atlas does not resolve.
local function applyAtlasCrop(tex, atlas)
    local Chrome = addon.UI and addon.UI.Chrome
    if not (Chrome and Chrome.AtlasSource) then return false end
    local file, w, h, L, R, T, B = Chrome.AtlasSource({ atlas = atlas.name })
    if not file then return false end
    local rect = atlas.rect
    local su, sv = (R - L) / w, (B - T) / h
    tex:SetTexture(file)
    tex:SetTexCoord(L + rect[1] * su, L + rect[3] * su, T + rect[2] * sv, T + rect[4] * sv)
    return true
end

local function atlasKnown(name)
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end

--- The name this client answers to for an atlas member, or nil. Forever
--- keeps its own art set behind retail's names, and a member that exists in
--- that set alone is listed under the set's "-c60" suffix with no plain
--- name beside it (the unit frames' level circle), while Blizzard's own XML
--- names it plain; so the plain name is tried first and the suffixed one
--- second. The resolved name is what SetAtlas and SetStatusBarTexture take.
function Art.ResolveAtlasName(name)
    if type(name) ~= "string" or not (C_Texture and C_Texture.GetAtlasInfo) then return nil end
    if atlasKnown(name) then return name end
    local suffixed = name .. "-c60"
    if atlasKnown(suffixed) then return suffixed end
    return nil
end

--- Whether this client has an atlas member by that name, under the name or
--- its suffixed form. A Modern spec's art is all names, and Forever's sheets
--- may lack some of retail's.
function Art.AtlasResolves(name)
    return Art.ResolveAtlasName(name) ~= nil
end

--- An atlas member by name on a texture Camelot owns, at the member's own
--- size unless useAtlasSize is false. A name this client lacks is skipped and
--- recorded on the texture, so the region draws nothing and /camelot state
--- names it: the flat fallback the crop form draws would stand as a block
--- the size of the art. The texture remembers the name as asked, so a state
--- write compares against the spec's own. Returns whether the name resolved.
function Art.SetAtlas(tex, name, useAtlasSize)
    tex.camelotAtlas = name
    local resolved = Art.ResolveAtlasName(name)
    if resolved then
        tex:SetAtlas(resolved, useAtlasSize ~= false)
        tex.camelotAtlasMissing = nil
        return true
    end
    tex.camelotAtlasMissing = true
    pcall(tex.SetTexture, tex, nil)
    return false
end

-- A looping flipbook over the region's sheet (the Modern player's rest
-- animation). Frame.SetPulsed starts and stops it as it does a glow, so the
-- painter files it in inst.pulses. A client without the animation type
-- leaves the region a still frame, hidden.
local function attachFlipbook(tex, fb)
    local group = tex:CreateAnimationGroup()
    group:SetLooping("REPEAT")
    local ok, anim = pcall(group.CreateAnimation, group, "FlipBook")
    if not (ok and anim) then return nil end
    anim:SetFlipBookRows(fb.rows)
    anim:SetFlipBookColumns(fb.columns)
    anim:SetFlipBookFrames(fb.frames)
    anim:SetFlipBookFrameWidth(0)
    anim:SetFlipBookFrameHeight(0)
    anim:SetDuration(fb.duration)
    anim:SetOrder(1)
    return group
end

--- A MaskTexture on host over the rect of anchorTo, from def = { atlas |
--- file, point, relPoint, x, y, w, h }: with a point it anchors that point
--- to anchorTo at the offset (the bar masks, which stand off their bar), and
--- without one it covers anchorTo (a region's own mask). An atlas mask takes
--- the member's size, then the def's own where it names one, since Blizzard's
--- Lua resizes the player's bar masks at load. Returns the mask, or nil when
--- an atlas does not resolve, so the texture draws unmasked rather than
--- behind a mask of nothing.
function Art.BuildMask(host, anchorTo, def)
    local mask = host:CreateMaskTexture()
    if def.atlas then
        if not Art.SetAtlas(mask, def.atlas, true) then return nil end
    else
        mask:SetTexture(def.file or def[1])
    end
    if def.point then
        mask:SetPoint(def.point, anchorTo, def.relPoint or def.point, def.x or 0, def.y or 0)
    else
        mask:SetAllPoints(anchorTo)
    end
    if def.w then mask:SetWidth(def.w) end
    if def.h then mask:SetHeight(def.h) end
    return mask
end

-- This file defines the region format, so it owns the one function that turns a
-- def into a texture. `atlas` is a crop as a table and a whole member as a
-- string; `mask` a file as a string and a BuildMask def as a table. A def
-- that names a region in `relTo` anchors to that region of the instance
-- rather than to its host, as a text slot does (the Modern target's skull at
-- its level circle's centre, its icons at its portrait's edges); regions is
-- the instance's table so far, and the painter builds in DrawOrder, so the
-- named region comes first.
function Art.BuildRegion(host, def, regions)
    local tex = host:CreateTexture(nil, def.layer, nil, def.sublevel)
    if def.path then tex:SetTexture(def.path) end
    if type(def.atlas) == "string" then
        Art.SetAtlas(tex, def.atlas, def.useAtlasSize)
    elseif def.atlas and not applyAtlasCrop(tex, def.atlas) then
        local fb = def.fallback or Art.BACKDROP_FALLBACK
        tex:SetColorTexture(fb[1], fb[2], fb[3], fb[4] or 1)
    end
    if def.w then tex:SetSize(def.w, def.h) end
    if def.snap == false then
        tex:SetTexelSnappingBias(0)
        tex:SetSnapToPixelGrid(false)
    end
    -- A texture's own scale, as the XML's scale attribute sets it: the
    -- member's size and the anchor offsets both scale with it.
    if def.scale then tex:SetScale(def.scale) end
    local nudge = def.nudge
    local rel = def.relTo and regions and regions[def.relTo] or host
    tex:SetPoint(def.point, rel, def.relPoint or def.point,
        (def.x or 0) + (nudge and nudge.x or 0), (def.y or 0) + (nudge and nudge.y or 0))
    if def.coords then
        tex:SetTexCoord(def.coords[1], def.coords[2], def.coords[3], def.coords[4])
    end
    if def.blend then tex:SetBlendMode(def.blend) end
    if def.color then
        tex:SetColorTexture(def.color[1], def.color[2], def.color[3], def.color[4] or 1)
    end
    if def.vertex then
        tex:SetVertexColor(def.vertex[1], def.vertex[2], def.vertex[3], def.vertex[4] or 1)
    end
    if type(def.mask) == "string" then
        local mask = host:CreateMaskTexture()
        mask:SetTexture(def.mask)
        mask:SetAllPoints(tex)
        tex:AddMaskTexture(mask)
    elseif def.mask then
        local mask = Art.BuildMask(host, tex, def.mask)
        if mask then tex:AddMaskTexture(mask) end
        tex.camelotMask = mask
    end
    if def.flipbook then tex.flipbook = attachFlipbook(tex, def.flipbook) end
    if def.hidden then tex:Hide() end
    if def.lift then
        local copy = {}
        for k, v in pairs(def) do copy[k] = v end
        copy.lift = nil
        copy.sublevel = (def.sublevel or 0) + 1
        copy.blend = "ADD"
        local lift = addon.UnitFrames.Text.BACKDROP_LIFT
        copy.vertex = { lift[1], lift[2], lift[3], def.vertex and def.vertex[4] or 1 }
        tex.lift = Art.BuildRegion(host, copy, regions)
    end
    return tex
end

--- Swap a region's art by state, for a def that carries `atlasByState = {
--- key = name }` beside its `atlas`: a key takes that state's member, nil
--- the def's own. The size follows the member, since the states differ in
--- size (the Modern target's rare and minus frames). A name this client
--- lacks blanks the region, as at build.
function Art.ApplyRegionAtlas(inst, region, stateKey)
    local tex = inst.regions and inst.regions[region]
    local def = inst.spec.Regions[region]
    if not (tex and def) then return end
    local name = stateKey and def.atlasByState and def.atlasByState[stateKey] or def.atlas
    if type(name) ~= "string" or tex.camelotAtlas == name then return end
    Art.SetAtlas(tex, name, def.useAtlasSize)
end

--------------------------------------------------------------------------------
-- The border style
--------------------------------------------------------------------------------
-- The vanilla border art is silver with a gold level ring. Three styles:
--
--   stock    the file as Blizzard drew it
--   tint     the stock file desaturated and multiplied by the Forever bronze,
--            with an additive copy of itself over the top. A multiply can only
--            darken, so on its own it lands near #4e3c2e and loses the lit edge
--            that makes metal read as metal; the additive copy puts it back.
--            The gold ring and the elite dragon go brown with everything else.
--   bronze   an authored copy under forever/media/unitframes/, recoloured
--            offline so the silver goes bronze and the gold is left alone
--            (docs/tools/ufcbronze.py writes them)
--
-- A spec marks its border region `border = true`. The painter builds a second,
-- hidden copy of that region as inst.borderLight for the tint style.

Art.BORDER_STYLES = { stock = true, tint = true, bronze = true }

-- The bronze the metal is multiplied by, and the lit edge laid back over it.
-- Both layers scale with the gray underneath, so the tint has one hue at every
-- brightness: TINT + LIGHT * LIGHT_ALPHA, here (1.0, 0.68, 0.40), hue 28.
-- Forever's own metal runs from hue 20 in the shadows to 37 in the highlights
-- (measured off the character frame and the gryphons); 28 is its midtone. The
-- first pair summed to hue 36 and read olive beside the real art. Only the
-- authored files can follow the ramp.
local TINT = { 0.70, 0.46, 0.26 }
local LIGHT = { 1.0, 0.73, 0.47 }
local LIGHT_ALPHA = 0.30

local BRONZE_ROOT = addon.MediaPath .. "forever\\media\\unitframes\\"

-- Art.Paths key -> file name under BRONZE_ROOT. These are PNGs and carry the
-- extension: an extension-less path resolves to .blp, then .tga, never .png.
-- Art.Paths above names Blizzard's BLPs and stays extension-less.
local BRONZE_FILES = {
    border = "UI-TargetingFrame.png",
    borderElite = "UI-TargetingFrame-Elite.png",
    borderRare = "UI-TargetingFrame-Rare.png",
    borderMinus = "UI-TargetingFrame-Minus.png",
    borderToT = "UI-TargetofTargetFrame.png",
    borderSmall = "UI-SmallTargetingFrame.png",
    borderSmallNoMana = "UI-SmallTargetingFrame-NoMana.png",
}

local function currentStyle()
    local style = addon.DB and addon.DB.Get("unitFrames.borderStyle")
    return Art.BORDER_STYLES[style] and style or "tint"
end

--- Point an instance's border at a file by Art.Paths key and dress it in the
--- current style. The decorator calls this when the file changes (an elite
--- target, a pet with no power bar); the style switch calls it for every frame.
function Art.ApplyBorder(inst, pathKey)
    local border = inst.regions and inst.regions.border
    if not border then return end
    pathKey = pathKey or inst.borderKey or (inst.spec and inst.spec.borderKey) or "border"
    inst.borderKey = pathKey

    -- The Classic style wears Blizzard's silver whatever the module's look.
    local style = inst.style == "classic" and "stock" or currentStyle()
    local path = Art.Paths[pathKey]
    if style == "bronze" and BRONZE_FILES[pathKey] then
        path = BRONZE_ROOT .. BRONZE_FILES[pathKey]
    end
    border:SetTexture(path)

    local tinted = style == "tint"
    border:SetDesaturated(tinted)
    if tinted then
        border:SetVertexColor(TINT[1], TINT[2], TINT[3])
    else
        border:SetVertexColor(1, 1, 1)
    end

    local light = inst.borderLight
    if light then
        if tinted then
            light:SetTexture(path)
            light:SetDesaturated(true)
            light:SetVertexColor(LIGHT[1], LIGHT[2], LIGHT[3], LIGHT_ALPHA)
            light:Show()
        else
            light:Hide()
        end
    end
end
