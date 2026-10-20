--------------------------------------------------------------------------------
-- forever/qualityoflife/animationsdisplay.lua
-- The overhead bars (animations.lua holds the settings). While the player
-- eats, a small health bar shows; while they drink, a mana bar; while the
-- Welcoming Campfire aura counts down its minute, a wider red bar fills.
-- Above each, its icon rises in a swaying line: a green plus, a blue plus,
-- a flame. A lone bar's icons rise from its center; with more than one bar
-- emitting, each kind takes its own lane so they never meet.
-- A plus stops rising at full; the bar then holds a moment and fades.
--
-- Nothing on screen follows the character's head: 12.0 took away the
-- player's nameplate and there is no world-to-screen call. The holder is a
-- plain UIParent frame above screen center, where the third-person camera
-- keeps the head, dragged in Edit Mode like any Camelot frame.
--
-- Out of combat only. Auras read plain then;
-- health and power stay secret, so the bars take them through SetValue and
-- "full" is the zero launder on the missing amount.
--------------------------------------------------------------------------------

local addonName, addon = ...

local Animations = addon.QualityOfLife.Animations
local DB = addon.DB

local OWNER = "QoLAnimations"
local LAYOUT_KEY = "qolAnimations"

local CAMPFIRE_SPELL = 1289723
local MANA = Enum.PowerType.Mana

-- The aura names, read once from a known Food and Drink spell so a
-- localized client matches its own names. The combined names are the
-- English ones only.
local FOOD_NAMES, DRINK_NAMES = {}, {}
local function loadNames()
    local food = C_Spell.GetSpellName(433) or "Food"
    local drink = C_Spell.GetSpellName(430) or "Drink"
    FOOD_NAMES = { [food] = true, ["Food & Drink"] = true, ["Refreshment"] = true }
    DRINK_NAMES = { [drink] = true, ["Food & Drink"] = true, ["Refreshment"] = true }
end

--------------------------------------------------------------------------------
-- Shape
--------------------------------------------------------------------------------

local BARS = {
    food = { w = 60, h = 6, color = { 0.1, 0.85, 0.1 } },
    drink = { w = 60, h = 6, color = { 0, 0.55, 1 } },
    campfire = { w = 80, h = 8, color = { 0.85, 0.18, 0.08 } },
}
local GAP = 4
local HOLDER_W, HOLDER_H = 80, 6 + GAP + 6 + GAP + 8

-- The PRD bar art's background overhang (CamelotPersonalResourceStatusBar),
-- which the Edit Mode box covers.
local REACH = { left = 2, right = 6, top = 3, bottom = 7 }

local DEFAULT_POSITION = { point = "CENTER", x = 0, y = 60 }

-- After a bar stops (full, or its aura gone): hold, then fade.
local HOLD, FADE = 1.0, 0.5

-- The rising icons. Lanes sit further apart than an icon plus its sway,
-- so neighbors never touch. Emitting kinds take lanes left to right in
-- LANE_ORDER, centered on the holder: one at 0, two at -13 and 13, three at
-- -26, 0 and 26.
local ICON_SIZE = 14
local LANE_SPACING = 26
local LANE_ORDER = { "food", "campfire", "drink" }
local SPAWN_EVERY = 2.1
local LIFE = 1.6
local RISE = 40
local SWAY, SWAY_HZ = 4, 1.2

local VALUE_EVERY = 0.1

--------------------------------------------------------------------------------
-- Secret helpers
--------------------------------------------------------------------------------

local function isSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- The zero launder (core/components/unitframesz/engine.lua, "The zero
-- launder"): TruncateWhenZero blanks a zero amount, and a scratch
-- FontString hands the blank back as a plain nil. true = zero, false = not,
-- nil = no answer, which the callers read as not full.
local scratch
local function isZeroAmount(v)
    if not (C_StringUtil and C_StringUtil.TruncateWhenZero) then return nil end
    local okT, trunc = pcall(C_StringUtil.TruncateWhenZero, v)
    if not okT then return nil end
    if not isSecret(trunc) then
        return (trunc == nil or trunc == "") and true or false
    end
    if not scratch then
        local f = CreateFrame("Frame", nil, UIParent)
        f:Hide()
        scratch = f:CreateFontString(nil, "BACKGROUND")
        scratch:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    end
    if scratch.ClearText then scratch:ClearText() end
    if not pcall(scratch.SetText, scratch, trunc) then return nil end
    local okG, text = pcall(scratch.GetText, scratch)
    if not okG then return nil end
    local okB, blank = pcall(function() return not text end)
    if not okB then return nil end
    return blank and true or false
end

local function isFull(kind)
    local missing
    if kind == "food" then
        local ok, v = pcall(_G.UnitHealthMissing, "player")
        missing = ok and v or nil
    else
        local ok, v = pcall(_G.UnitPowerMissing, "player", MANA)
        missing = ok and v or nil
    end
    if missing == nil then return false end
    return isZeroAmount(missing) == true
end

--------------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------------

local holder
local bars = {}
local states = {}
local icons = {}
local iconPool
local preview = false

-- The icons are white silhouettes in forever/media/animations, tinted
-- per kind in muted shades of the bar colors: two plus marks and a flame,
-- no frame or background behind them.
local ICON_ART = {
    food = { file = "plus.png", color = { 0.55, 0.95, 0.5 } },
    drink = { file = "plus.png", color = { 0.5, 0.75, 1 } },
    campfire = { file = "flame.png", color = { 1, 0.6, 0.25 } },
}

local function paintIcon(tex, kind)
    local art = ICON_ART[kind]
    tex:SetTexture(addon.MediaPath .. "forever\\media\\animations\\" .. art.file)
    tex:SetVertexColor(art.color[1], art.color[2], art.color[3])
end

local function build()
    if holder then return end
    holder = CreateFrame("Frame", "CamelotOverheadBars", UIParent)
    holder:SetSize(HOLDER_W, HOLDER_H)
    holder:SetPoint(DEFAULT_POSITION.point, DEFAULT_POSITION.x, DEFAULT_POSITION.y)
    holder:SetFrameStrata("LOW")
    holder:Hide()

    for _, kind in ipairs(Animations.KINDS) do
        local spec = BARS[kind]
        local bar = CreateFrame("StatusBar", nil, holder, "CamelotPersonalResourceStatusBar")
        bar:SetSize(spec.w, spec.h)
        bar:SetStatusBarColor(spec.color[1], spec.color[2], spec.color[3])
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar:Hide()
        bars[kind] = bar
        states[kind] = { want = false, emitting = false, stoppedAt = nil, nextSpawn = 0 }
    end

    iconPool = addon.Pool.New(function()
        return holder:CreateTexture(nil, "OVERLAY")
    end, function(tex)
        tex:Hide()
        tex:ClearAllPoints()
    end)
end

-- Shown bars stack up from the holder's bottom in KINDS order reversed, so
-- the campfire is lowest and a lone bar sits on the bottom edge. Returns
-- the stack's height, where the icons start.
local function layout()
    local y = 0
    for i = #Animations.KINDS, 1, -1 do
        local bar = bars[Animations.KINDS[i]]
        if bar:IsShown() then
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOM", holder, "BOTTOM", 0, y)
            y = y + bar:GetHeight() + GAP
        end
    end
    return y
end

local stackTop = 0

--------------------------------------------------------------------------------
-- Icons
--------------------------------------------------------------------------------

-- An icon keeps the lane it spawned in, so one bar starting or stopping
-- never makes the icons already rising jump sideways.
local function laneX(kind)
    local count, index = 0, 0
    for _, k in ipairs(LANE_ORDER) do
        if states[k].emitting then
            count = count + 1
            if k == kind then index = count end
        end
    end
    if index == 0 then return 0 end
    return (index - (count + 1) / 2) * LANE_SPACING
end

local function spawnIcon(kind, now)
    local tex = iconPool:Acquire()
    if not tex then return end
    paintIcon(tex, kind)
    tex:SetSize(ICON_SIZE, ICON_SIZE)
    tex:SetAlpha(0)
    tex:Show()
    icons[#icons + 1] = { tex = tex, x = laneX(kind), born = now, phase = math.random() * 2 * math.pi }
end

local function releaseIcons()
    for i = #icons, 1, -1 do
        iconPool:Release(icons[i].tex)
        icons[i] = nil
    end
end

local TWO_PI = 2 * math.pi

local function moveIcons(now)
    for i = #icons, 1, -1 do
        local icon = icons[i]
        local age = now - icon.born
        if age >= LIFE then
            iconPool:Release(icon.tex)
            table.remove(icons, i)
        else
            local p = age / LIFE
            local x = icon.x + math.sin(age * TWO_PI * SWAY_HZ + icon.phase) * SWAY
            local y = stackTop + ICON_SIZE / 2 + RISE * p
            icon.tex:ClearAllPoints()
            icon.tex:SetPoint("CENTER", holder, "BOTTOM", x, y)
            local alpha
            if p < 0.15 then
                alpha = p / 0.15
            elseif p > 2 / 3 then
                alpha = (1 - p) * 3
            else
                alpha = 1
            end
            icon.tex:SetAlpha(alpha)
        end
    end
end

--------------------------------------------------------------------------------
-- Auras
--------------------------------------------------------------------------------

local campfireStart, campfireDuration

local function scanAuras()
    local eating, drinking, camp = false, false, nil
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not aura then break end
        local name, spellId = aura.name, aura.spellId
        if not isSecret(name) and not isSecret(spellId) then
            if spellId == CAMPFIRE_SPELL then
                camp = aura
            else
                if FOOD_NAMES[name] then eating = true end
                if DRINK_NAMES[name] then drinking = true end
            end
        end
    end
    return eating, drinking, camp
end

-- A missing aura keeps the last start and duration: the driver reads them
-- once more to tell an aura that ran out from one taken away early.
local function readCampfire(aura)
    if not aura then return false end
    local duration, expires = aura.duration, aura.expirationTime
    if isSecret(duration) or isSecret(expires) then return false end
    if not duration or duration <= 0 or not expires then return false end
    campfireStart, campfireDuration = expires - duration, duration
    bars.campfire:SetMinMaxValues(0, duration)
    return true
end

local function hasMana()
    local ok, max = pcall(UnitPowerMax, "player", MANA)
    return ok and not isSecret(max) and max and max > 0
end

--------------------------------------------------------------------------------
-- The driver
--------------------------------------------------------------------------------

local function feedValue(kind)
    local bar = bars[kind]
    if kind == "food" then
        pcall(function()
            bar:SetMinMaxValues(0, UnitHealthMax("player"))
            bar:SetValue(UnitHealth("player"))
        end)
    elseif kind == "drink" then
        pcall(function()
            bar:SetMinMaxValues(0, UnitPowerMax("player", MANA))
            bar:SetValue(UnitPower("player", MANA))
        end)
    elseif campfireStart then
        bar:SetValue(math.min(GetTime() - campfireStart, campfireDuration))
    end
end

local function hideAll()
    if not holder then return end
    releaseIcons()
    for _, kind in ipairs(Animations.KINDS) do
        bars[kind]:Hide()
        local st = states[kind]
        st.want, st.emitting, st.stoppedAt = false, false, nil
    end
    holder:Hide()
end

local valueClock = 0

local function onUpdate(_, elapsed)
    if preview then return end
    local now = GetTime()
    valueClock = valueClock + elapsed
    local readValues = valueClock >= VALUE_EVERY
    if readValues then valueClock = 0 end

    local stackChanged = false
    local spawns = {}
    for _, kind in ipairs(Animations.KINDS) do
        local st, bar = states[kind], bars[kind]
        local emitting = st.want
        if emitting and readValues and kind ~= "campfire" then
            st.full = isFull(kind)
        end
        if kind ~= "campfire" and st.full then emitting = false end

        if emitting then
            if not bar:IsShown() then
                bar:SetAlpha(1)
                bar:Show()
                stackChanged = true
                st.nextSpawn = now
            end
            bar:SetAlpha(1)
            st.stoppedAt = nil
            if readValues or kind == "campfire" then feedValue(kind) end
            if now >= st.nextSpawn then
                spawns[#spawns + 1] = kind
                st.nextSpawn = now + SPAWN_EVERY
            end
        elseif bar:IsShown() then
            if not st.stoppedAt then
                st.stoppedAt = now
                feedValue(kind)
                -- A campfire aura that ran out filled the bar; one taken
                -- away early (the player stood up) leaves it where it was.
                if kind == "campfire" and campfireStart and now >= campfireStart + campfireDuration - 0.5 then
                    bar:SetValue(campfireDuration)
                end
            end
            local age = now - st.stoppedAt
            if age < HOLD then
                bar:SetAlpha(1)
            elseif age < HOLD + FADE then
                bar:SetAlpha(1 - (age - HOLD) / FADE)
            else
                bar:Hide()
                st.stoppedAt = nil
                stackChanged = true
            end
        end
        st.emitting = emitting
    end

    -- Spawned after the loop, once every kind's emitting state is known, so
    -- the lane count is this frame's.
    for _, kind in ipairs(spawns) do spawnIcon(kind, now) end

    if stackChanged then stackTop = layout() end
    moveIcons(now)

    local anyShown = #icons > 0
    for _, kind in ipairs(Animations.KINDS) do
        if bars[kind]:IsShown() then anyShown = true end
    end
    if not anyShown then holder:Hide() end
end

-- What the auras ask for, read on every player UNIT_AURA. The driver does
-- the rest while the holder is shown.
local function evaluate()
    if not holder or preview then return end
    if InCombatLockdown() or addon.AurasSecretNow() then
        hideAll()
        return
    end
    local eating, drinking, camp = scanAuras()
    local want = {
        food = eating and Animations.IsOn("food"),
        drink = drinking and Animations.IsOn("drink") and hasMana(),
        campfire = Animations.IsOn("campfire") and readCampfire(camp),
    }
    local any = false
    for _, kind in ipairs(Animations.KINDS) do
        local st = states[kind]
        if want[kind] and not st.want then st.full = isFull(kind) end
        st.want = want[kind] and true or false
        if st.want then any = true end
    end
    if any then holder:Show() end
end

function Animations.Refresh()
    evaluate()
end

--------------------------------------------------------------------------------
-- Edit Mode
--------------------------------------------------------------------------------
-- In Edit Mode all three bars show, part filled, so there is something to
-- drag; the icons wait.

local function showPreview()
    preview = true
    releaseIcons()
    for _, kind in ipairs(Animations.KINDS) do
        local bar = bars[kind]
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0.6)
        bar:SetAlpha(1)
        bar:Show()
    end
    stackTop = layout()
    holder:Show()
end

local function endPreview()
    preview = false
    hideAll()
    evaluate()
end

local store = {
    get = function(key, layoutName)
        local entry = DB.GetLayout(key)
        local positions = entry and entry.positions
        return positions and positions[layoutName] or nil
    end,
    set = function(key, layoutName, point, x, y)
        local entry = DB.GetLayout(key) or {}
        entry.positions = entry.positions or {}
        entry.positions[layoutName] = { point = point, x = x, y = y }
        DB.SetLayout(key, entry)
    end,
}

local registered = false
local function registerEditMode()
    if registered or not (addon.EditMode and addon.EditMode.RegisterPositionable) then return end
    registered = true
    holder.editModeName = "Overhead Bars"
    addon.EditMode.RegisterPositionable(holder, {
        key = LAYOUT_KEY,
        default = DEFAULT_POSITION,
        restoreDefault = true,
        reach = REACH,
        store = store,
        brand = { navKey = Animations.NAV_KEY, componentId = Animations.NAV_KEY },
    })
    addon.EditMode.OnEditMode(OWNER, { enter = showPreview, exit = endPreview })
    if addon.EditMode.IsEditing() then showPreview() end
end

--------------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------------

addon.Events.OnWorldEntered(function()
    loadNames()
    build()
    holder:SetScript("OnUpdate", onUpdate)
    registerEditMode()
    evaluate()
end)

addon.Events.On(OWNER, "UNIT_AURA", function(_, unit)
    if unit == "player" then evaluate() end
end)
addon.Events.On(OWNER, "PLAYER_REGEN_DISABLED", function()
    if not preview then hideAll() end
end)
addon.Events.On(OWNER, "PLAYER_REGEN_ENABLED", evaluate)

-- After a profile switch the bars read the new profile's toggles. A resync
-- pass keeps the profile it had.
addon.Profiles.RegisterApplyStep("camelotAnimations", function(_, ctx)
    if ctx.initial or ctx.resync then return end
    evaluate()
end, 40)
