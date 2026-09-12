--------------------------------------------------------------------------------
-- core/debug/prdclass.lua
-- Class resource geometry dump (/scoot debug prdclass)
--
-- Blizzard centers the PRD class resource frame itself: SetupClassBar anchors
-- it CENTER-to-CENTER inside ClassFrameContainer, and the frame is a
-- HorizontalLayoutFrame whose Layout() resizes it to hug its point buttons
-- (Blizzard_PersonalResourceDisplay.lua, ClassResourceBarTemplate.lua,
-- LayoutFrame.lua). A row that reads off-centre therefore comes from one of
-- three places, and this dump separates them:
--
--   1. The frame's width no longer matches its children. HorizontalLayoutMixin
--      packs children from the LEFT edge and CalculateFrameSize honours
--      fixedWidth and leftPadding, so a stale or padded width leaves the
--      children left of the frame's own centre.
--   2. The frame's anchor is not the CENTER-to-CENTER one, because something
--      re-anchored it (the managed frame container does this on Show unless
--      ignoreFramePositionManager is set).
--   3. Scale. Scoot's prdClassResource "scale" slider calls SetScale on this
--      frame, so its rect getters report in a different unit than the
--      container's. Every rect below is converted to screen pixels with
--      GetEffectiveScale so the two are comparable.
--
-- The player-frame twin (DruidComboPointBarFrame and friends) is dumped beside
-- it because Scoot's unit frame classResource offsets write leftPadding and
-- topPadding to that object, which shifts its children by half the padding.
--------------------------------------------------------------------------------

local addonName, addon = ...

local SS = addon.SecretSafe

--------------------------------------------------------------------------------
-- Readers
--------------------------------------------------------------------------------

-- Every getter below runs on a Blizzard frame, so each read is pcall-wrapped
-- and screened for a secret before it reaches string.format.
local function num(frame, method)
    if not frame or not frame[method] then return nil end
    local ok, v = pcall(frame[method], frame)
    if not ok then return nil end
    return SS.safeNumber(v)
end

local function fmtNum(v, places)
    if v == nil then return "n/a" end
    return string.format("%." .. (places or 1) .. "f", v)
end

local function fmtField(v)
    if v == nil then return "nil" end
    local t = type(v)
    if t == "number" then return fmtNum(v, 2) end
    if t == "boolean" then return tostring(v) end
    if t == "string" then return SS.plainString(v) or "<secret>" end
    return "<" .. t .. ">"
end

local function field(frame, key)
    if not frame then return nil end
    local ok, v = pcall(function() return frame[key] end)
    if not ok then return nil end
    return v
end

local function frameName(frame)
    frame = SS.plainFrame(frame)
    if not frame then return "<none>" end
    local ok, name = pcall(frame.GetName, frame)
    if ok then
        local plain = SS.plainString(name)
        if plain then return plain end
    end
    return "<unnamed>"
end

-- Left/right/centre in screen pixels, so a scaled frame and its parent compare
-- directly. Rect getters report in the frame's own effective-scale space.
local function screenRect(frame)
    frame = SS.plainFrame(frame)
    if not frame then return nil end
    local es = num(frame, "GetEffectiveScale") or 1
    local left, right = num(frame, "GetLeft"), num(frame, "GetRight")
    local top, bottom = num(frame, "GetTop"), num(frame, "GetBottom")
    if not left or not right then return nil end
    return {
        left = left * es,
        right = right * es,
        top = top and top * es or nil,
        bottom = bottom and bottom * es or nil,
        centerX = (left + right) / 2 * es,
        centerY = (top and bottom) and (top + bottom) / 2 * es or nil,
        effectiveScale = es,
    }
end

local function fmtRect(rect)
    if not rect then return "no rect" end
    return string.format("L %s  R %s  cx %s  (w %s)  scale %s",
        fmtNum(rect.left), fmtNum(rect.right), fmtNum(rect.centerX),
        fmtNum(rect.right - rect.left), fmtNum(rect.effectiveScale, 3))
end

local function addPoints(add, frame, indent)
    local count = num(frame, "GetNumPoints")
    if not count then
        add("%sGetNumPoints unreadable", indent)
        return
    end
    if count == 0 then
        add("%s(no points)", indent)
        return
    end
    for i = 1, count do
        local ok, point, relativeTo, relativePoint, x, y = pcall(frame.GetPoint, frame, i)
        if ok then
            add("%s#%d %s -> %s %s  x %s  y %s", indent, i,
                SS.safePointToken(point, "<secret>"),
                frameName(relativeTo),
                SS.safePointToken(relativePoint, "<secret>"),
                fmtNum(SS.safeNumber(x), 2), fmtNum(SS.safeNumber(y), 2))
        else
            add("%s#%d unreadable", indent, i)
        end
    end
end

--------------------------------------------------------------------------------
-- Bar dump
--------------------------------------------------------------------------------

-- The layout inputs HorizontalLayoutMixin and CalculateFrameSize read.
local LAYOUT_KEYS = {
    "leftPadding", "rightPadding", "topPadding", "bottomPadding",
    "spacing", "fixedWidth", "fixedHeight", "minimumWidth", "maximumWidth",
    "expand", "align", "childLayoutDirection", "respectChildScale",
    "layoutIndex", "ignoreInLayout", "ignoreFramePositionManager",
    "maxUsablePoints", "usePooledResourceButtons", "powerType", "xOffset",
    "hiddenByPersonalResourceDisplay", "canBeHiddenByPersonalResourceDisplay",
}

local function pointButtons(bar)
    local ok, tbl = pcall(function() return bar.classResourceButtonTable end)
    if not ok or type(tbl) ~= "table" then return nil end
    return tbl
end

local function addBar(add, bar, label, container)
    add("%s", label)
    bar = SS.plainFrame(bar)
    if not bar then
        add("  frame: <missing or secret>")
        return
    end
    local shownOk, shown = pcall(bar.IsShown, bar)
    add("  name: %s   shown: %s", frameName(bar), shownOk and tostring(shown) or "?")

    local rect = screenRect(bar)
    add("  rect: %s", fmtRect(rect))
    add("  size: w %s  h %s   own scale %s",
        fmtNum(num(bar, "GetWidth"), 2), fmtNum(num(bar, "GetHeight"), 2),
        fmtNum(num(bar, "GetScale"), 3))

    add("  points:")
    addPoints(add, bar, "    ")

    local parts = {}
    for _, key in ipairs(LAYOUT_KEYS) do
        local v = field(bar, key)
        if v ~= nil then
            parts[#parts + 1] = key .. "=" .. fmtField(v)
        end
    end
    add("  layout inputs: %s", #parts > 0 and table.concat(parts, "  ") or "(all nil)")

    -- Children packed from the left, so their span against the bar's own rect
    -- is the direct read on fault 1 above.
    local buttons = pointButtons(bar)
    if not buttons then
        add("  classResourceButtonTable: unreadable")
    else
        add("  classResourceButtonTable: %d entries", #buttons)
        local spanLeft, spanRight
        for i = 1, #buttons do
            local btn = SS.plainFrame(buttons[i])
            local brect = btn and screenRect(btn)
            local btnShownOk, btnShown = pcall(function() return btn and btn:IsShown() end)
            add("    [%d] layoutIndex %s  shown %s  size %sx%s  %s",
                i, fmtField(field(btn, "layoutIndex")),
                btnShownOk and tostring(btnShown) or "?",
                fmtNum(num(btn, "GetWidth"), 1), fmtNum(num(btn, "GetHeight"), 1),
                fmtRect(brect))
            if brect then
                spanLeft = spanLeft and math.min(spanLeft, brect.left) or brect.left
                spanRight = spanRight and math.max(spanRight, brect.right) or brect.right
            end
        end
        if spanLeft and spanRight then
            local contentCenter = (spanLeft + spanRight) / 2
            add("  point span: L %s  R %s  cx %s  (w %s)",
                fmtNum(spanLeft), fmtNum(spanRight), fmtNum(contentCenter),
                fmtNum(spanRight - spanLeft))
            if rect then
                add("  DELTA point span cx - bar cx = %s px",
                    fmtNum(contentCenter - rect.centerX, 2))
            end
            local crect = container and screenRect(container)
            if crect then
                add("  DELTA point span cx - container cx = %s px",
                    fmtNum(contentCenter - crect.centerX, 2))
            end
        end
    end

    if container then
        local crect, brect = screenRect(container), rect
        if crect and brect then
            add("  DELTA bar cx - container cx = %s px",
                fmtNum(brect.centerX - crect.centerX, 2))
        end
    end
end

--------------------------------------------------------------------------------
-- Config dump
--------------------------------------------------------------------------------

local function addConfig(add)
    add("Scoot config")
    local comp = addon.Components and addon.Components.prdClassResource
    local db = comp and comp.db
    if type(db) ~= "table" then
        add("  prdClassResource.db: <none>")
    else
        local keys = {}
        for k in pairs(db) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            add("  prdClassResource.%s = %s", k, fmtField(db[k]))
        end
    end

    local profile = addon.db and addon.db.profile
    local ufCfg = profile and profile.unitFrames and profile.unitFrames.Player
        and profile.unitFrames.Player.classResource
    if type(ufCfg) ~= "table" then
        add("  unitFrames.Player.classResource: <none>")
    else
        local keys = {}
        for k in pairs(ufCfg) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            add("  unitFrames.Player.classResource.%s = %s", k, fmtField(ufCfg[k]))
        end
    end
end

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------

-- Player-frame twins, matching CLASS_FRAME_INFO_MAP in
-- Blizzard_PersonalResourceDisplay.lua. Only used to name the comparison frame.
local PLAYER_FRAME_BARS = {
    DRUID = "DruidComboPointBarFrame",
    ROGUE = "RogueComboPointBarFrame",
    PALADIN = "PaladinPowerBarFrame",
    MONK = "MonkHarmonyBarFrame",
    WARLOCK = "WarlockPowerFrame",
    DEATHKNIGHT = "RuneFrame",
    MAGE = "MageArcaneChargesFrame",
    EVOKER = "EssencePlayerFrame",
}

local function DebugPRDClass()
    local lines, add = addon.DebugLines()

    local classToken = UnitClassBase and UnitClassBase("player") or select(2, UnitClass("player"))
    add("PRD class resource geometry — GetTime %.3f", GetTime())
    add("class %s   spec %s   nameplateShowSelf %s",
        fmtField(classToken),
        fmtField(C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()),
        fmtField(GetCVar and GetCVar("nameplateShowSelf")))
    add("Edit Mode active/opening: %s",
        fmtField(addon.EditMode and addon.EditMode.IsEditModeActiveOrOpening
            and addon.EditMode.IsEditModeActiveOrOpening()))
    add("")

    local prd = SS.plainFrame(PersonalResourceDisplayFrame)
    if not prd then
        add("PersonalResourceDisplayFrame: <missing or secret>")
        addon.DebugShowWindow("Scoot Debug: PRD Class Resource", lines)
        return
    end

    add("PersonalResourceDisplayFrame")
    add("  rect: %s", fmtRect(screenRect(prd)))
    add("  own scale %s   defaultBarWidth %s   barWidthPercent %s   barPadding %s",
        fmtNum(num(prd, "GetScale"), 3), fmtField(field(prd, "defaultBarWidth")),
        fmtField(field(prd, "barWidthPercent")), fmtField(field(prd, "barPadding")))
    add("  hideHealth %s  hidePower %s  hideAltPower %s  hideClassInfo %s",
        fmtField(field(prd, "hideHealth")), fmtField(field(prd, "hidePower")),
        fmtField(field(prd, "hideAltPower")), fmtField(field(prd, "hideClassInfo")))
    add("")

    local container = SS.plainFrame(field(prd, "ClassFrameContainer"))
    if not container then
        add("ClassFrameContainer: <missing or secret>")
    else
        local shownOk, shown = pcall(container.IsShown, container)
        add("ClassFrameContainer")
        add("  shown %s   yOffset %s", shownOk and tostring(shown) or "?",
            fmtField(field(container, "yOffset")))
        add("  rect: %s", fmtRect(screenRect(container)))
        add("  size: w %s  h %s", fmtNum(num(container, "GetWidth"), 2),
            fmtNum(num(container, "GetHeight"), 2))
        add("  points:")
        addPoints(add, container, "    ")
        add("  children: %s", fmtNum(num(container, "GetNumChildren"), 0))
    end
    add("")

    addBar(add, field(prd, "classFrame"), "PRD classFrame (the bar inside ClassFrameContainer)", container)
    add("")

    local twinName = classToken and PLAYER_FRAME_BARS[classToken]
    if twinName then
        local twin = SS.plainFrame(_G[twinName])
        local twinParent
        if twin then
            local ok, parent = pcall(twin.GetParent, twin)
            twinParent = ok and SS.plainFrame(parent) or nil
        end
        addBar(add, twin, "Player-frame twin: " .. twinName, twinParent)
    else
        add("Player-frame twin: none for this class")
    end
    add("")

    addConfig(add)

    addon.DebugShowWindow("Scoot Debug: PRD Class Resource", lines)
end

addon:RegisterDebugCommand({
    name = "prdclass", help = "PRD class resource geometry and layout inputs",
    usage = { "prdclass" },
    handler = function() DebugPRDClass() end,
})
