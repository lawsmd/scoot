--------------------------------------------------------------------------------
-- forever/unitframes/art.lua
-- What every Classic unit frame's art shares: the texture paths, the region
-- format and its reader, and the border style. One spec per frame shape lives
-- beside this file (artplayer, arttarget, arttot, artpet) and registers into
-- Art.Frames.
--
-- Every number in a spec is Blizzard's own, read out of the vanilla XML rather
-- than measured off a screenshot, so the rebuild is a transcription. The source
-- is the classic_era branch of the UI source mirror:
--
--   git show origin/classic_era:Interface/AddOns/Blizzard_UnitFrame/Classic/<file>.xml
--
-- Every stock path below resolves by name in a 12.x client.
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

-- key -> spec, filled by the art*.lua files.
Art.Frames = {}

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
}

--------------------------------------------------------------------------------
-- The reader
--------------------------------------------------------------------------------

-- This file defines the region format, so it owns the one function that turns a
-- def into a texture.
function Art.BuildRegion(host, def)
    local tex = host:CreateTexture(nil, def.layer, nil, def.sublevel)
    if def.path then tex:SetTexture(def.path) end
    tex:SetSize(def.w, def.h)
    local nudge = def.nudge
    tex:SetPoint(def.point, host, def.relPoint or def.point,
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
    if def.hidden then tex:Hide() end
    return tex
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

-- Art.Paths key -> file name under BRONZE_ROOT.
local BRONZE_FILES = {
    border = "UI-TargetingFrame",
    borderElite = "UI-TargetingFrame-Elite",
    borderRare = "UI-TargetingFrame-Rare",
    borderMinus = "UI-TargetingFrame-Minus",
    borderToT = "UI-TargetofTargetFrame",
    borderSmall = "UI-SmallTargetingFrame",
    borderSmallNoMana = "UI-SmallTargetingFrame-NoMana",
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

    local style = currentStyle()
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
