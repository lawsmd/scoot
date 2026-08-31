--------------------------------------------------------------------------------
-- core/components/unitframes/auracontainer.lua
-- Target/Focus replacement aura display (12.1 AuraContainer pilot)
--
-- Patch 12.1 removed any public way to enumerate or restyle the buttons inside
-- Blizzard's target/focus aura container (a single engine-managed container at
-- TargetFrame.TargetFrameContent.TargetFrameContentContextual.Auras with
-- private Buffs/Debuffs groups). This module therefore builds a Scoot-owned
-- CustomAuraContainer per unit that mirrors Blizzard's filter strings and lets
-- Scoot style its own buttons freely. The engine does all aura tracking,
-- filtering, sorting, and layout internally; Scoot only supplies regions.
--
-- ACTIVATION (pilot phase): fully inert until started from the debug surface
-- (/scoot debug auracontainer start). Nothing is created at load, no events are
-- registered, and Blizzard frames are never touched by default. Suppression of
-- Blizzard's own container is probe-gated behind explicit debug commands; until
-- a suppression mode is chosen the two displays coexist. Once the in-game probe
-- battery passes, activation moves to config presence (buffsDebuffs) and the
-- chosen suppression mode ships as the default.
--
-- Contracts this build relies on (checked against the 12.1.0 UI source):
-- * CustomAuraContainerTemplate carries allowUntaintedCreation, so addon
--   CreateFrame works; buttons are engine-created via AddAuraGroup only.
-- * initializeFrame receives each button's public object table via
--   securecallfunction, BEFORE access restrictions are applied, so region
--   creation inside it is safe even mid-combat batch growth.
-- * Regions handed to Set*/Add* must be descendants of their button.
-- * Structural work (groups, filters, layout) is gated on
--   not InCombatLockdown() and not C_Secrets.ShouldAurasBeSecret().
-- * Target-unit containers need UpdateAllAuras() kicks on retarget; UNIT_AURA
--   tracking is engine-internal otherwise.
--------------------------------------------------------------------------------

local addonName, addon = ...

local issecretvalue = _G.issecretvalue

local AC = {
    enabled = false,
    containers = {},        -- [unitKey] = { container, unitToken, buttons = {}, buttonMeta = {} }
    suppression = {},       -- [unitKey] = "off" | "maxzero" | "alpha"
    results = {},           -- [key] = string; probe observations for the debug dump
    log = {},               -- breadcrumb ring
    logIndex = 0,
}
addon.AuraContainers = AC

local LOG_SIZE = 128

local UNITS = {
    Target = "target",
    Focus = "focus",
}

-- Blizzard's own container metrics (TargetFrameAuraContainerDefaults).
local MAX_BUFFS = 32
local MAX_DEBUFFS = 16
local BASE_AURA_SIZE = 21
local ELEMENT_SPACING = 3
local LINE_SPACING = 3
local LINE_SIZE = 122
local ANCHOR_X = 5   -- AURA_START_X
local ANCHOR_Y = 9   -- AURA_START_Y (TOPLEFT to FrameTexture BOTTOMLEFT)

--------------------------------------------------------------------------------
-- Breadcrumbs and probe result recording
--------------------------------------------------------------------------------

local function safeToString(v)
    local ty = type(v)
    if issecretvalue and issecretvalue(v) then
        return "<secret:" .. ty .. ">"
    end
    local ok, s = pcall(tostring, v)
    return ok and s or ("<" .. ty .. ">")
end
AC.SafeToString = safeToString

function AC.Record(tag, detail)
    AC.logIndex = AC.logIndex + 1
    local slot = ((AC.logIndex - 1) % LOG_SIZE) + 1
    AC.log[slot] = { t = GetTime(), seq = AC.logIndex, tag = tag, detail = detail or "" }
end

function AC.SetResult(key, value)
    AC.results[key] = value
    AC.Record("result", key .. " = " .. tostring(value))
end

--------------------------------------------------------------------------------
-- Frame resolution (Blizzard side, read-only)
--------------------------------------------------------------------------------

local resolveUnitFrame = addon.GetUnitFrame

local function resolveBlizzardAuraContainer(unitKey)
    local frame = resolveUnitFrame(unitKey)
    local content = frame and frame.TargetFrameContent
    local contextual = content and content.TargetFrameContentContextual
    return contextual and contextual.Auras or nil
end

local function resolveAnchorTexture(unitKey)
    local frame = resolveUnitFrame(unitKey)
    local holder = frame and frame.TargetFrameContainer
    return holder and holder.FrameTexture or nil, frame
end

--------------------------------------------------------------------------------
-- Config access (zero-touch: read-only, tolerate absence)
--------------------------------------------------------------------------------

local function getUnitConfig(unitKey)
    local db = addon and addon.db and addon.db.profile
    if not db then return nil end
    local unitFrames = rawget(db, "unitFrames")
    local unitCfg = unitFrames and rawget(unitFrames, unitKey) or nil
    if not unitCfg then return nil end
    return rawget(unitCfg, "buffsDebuffs")
end

local function computeElementSize(unitKey, cfg)
    local scalePct = cfg and tonumber(cfg.iconScale) or 100
    if scalePct < 20 then scalePct = 20 elseif scalePct > 200 then scalePct = 200 end
    local mult = scalePct / 100.0

    local ratio = cfg and tonumber(cfg.tallWideRatio) or 0
    if ratio ~= 0 and addon.IconRatio then
        local componentId = (unitKey == "Target") and "targetBuffsDebuffs" or "focusBuffsDebuffs"
        local w, h = addon.IconRatio.GetDimensionsForComponent(componentId, ratio)
        if w and h then
            return math.floor(w * mult + 0.5), math.floor(h * mult + 0.5)
        end
    end

    local size = math.floor(BASE_AURA_SIZE * mult + 0.5)
    return size, size
end

--------------------------------------------------------------------------------
-- Structural gate
--------------------------------------------------------------------------------

-- Shared fail-closed gate (base/utilities.lua); base/ loads before this file.
local function aurasSecretNow()
    return addon.AurasSecretNow and addon.AurasSecretNow() or false
end

function AC.CanDoStructuralWork()
    if InCombatLockdown and InCombatLockdown() then return false end
    if aurasSecretNow() then return false end
    return true
end

--------------------------------------------------------------------------------
-- Button wiring (runs inside the engine's initializeFrame callback)
--------------------------------------------------------------------------------

local function onButtonEnter(button)
    local entry = AC.buttonOwner and AC.buttonOwner[button]
    if not entry then return end

    local getInstance = button.GetAuraInstance
    if type(getInstance) ~= "function" then
        AC.SetResult("probe.instanceMethod", "GetAuraInstance missing on public button")
        return
    end
    local ok, unitToken, auraData = pcall(getInstance, button)
    if not ok then
        AC.SetResult("probe.instanceMethod", "GetAuraInstance call errored: " .. safeToString(unitToken))
        return
    end
    AC.SetResult("probe.instanceMethod", "GetAuraInstance callable")

    if issecretvalue and (issecretvalue(unitToken) or issecretvalue(auraData)) then
        AC.SetResult("probe.instancePlain", "SECRET at hover (restricted context)")
        return
    end
    if type(auraData) ~= "table" then return end
    local iid = auraData.auraInstanceID
    if issecretvalue and issecretvalue(iid) then
        AC.SetResult("probe.instancePlain", "struct plain but auraInstanceID SECRET")
        return
    end
    if not iid then return end
    AC.SetResult("probe.instancePlain", "plain auraInstanceID at hover: " .. tostring(iid))

    local unit = (type(unitToken) == "string" and unitToken) or entry.unitToken
    local tip = _G.GameTooltip
    if tip and tip.SetUnitAuraByAuraInstanceID then
        tip:SetOwner(button, "ANCHOR_BOTTOMRIGHT")
        local tok = pcall(tip.SetUnitAuraByAuraInstanceID, tip, unit, iid)
        if not tok then tip:Hide() end
    end
end

local function onButtonLeave()
    local tip = _G.GameTooltip
    if tip then tip:Hide() end
end

-- Weak map from public button object to its owning container entry.
AC.buttonOwner = setmetatable({}, { __mode = "k" })

local function wireButton(button, entry, groupKind)
    -- Icon fills the button; the engine writes the texture per assigned aura.
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    local okIcon, errIcon = pcall(button.SetIcon, button, icon)
    if not okIcon then
        AC.SetResult("wire.icon", "FAILED: " .. safeToString(errIcon))
    end

    -- Cooldown swipe; the engine drives it from the aura's DurationObject.
    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(button)
    cooldown:SetReverse(true)
    cooldown:SetDrawEdge(false)
    local okCd, errCd = pcall(button.SetDurationCooldown, button, cooldown)
    if not okCd then
        AC.SetResult("wire.cooldown", "FAILED: " .. safeToString(errCd))
    end

    -- Stack count above the swipe. A child frame lifts the text over the
    -- Cooldown widget; descendant validation accepting child-of-child regions
    -- is itself a recorded observation.
    local textHost = CreateFrame("Frame", nil, button)
    textHost:SetAllPoints(button)
    textHost:SetFrameLevel(cooldown:GetFrameLevel() + 1)
    local count = textHost:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    local okCount = pcall(button.SetApplicationCount, button, count, {})
    if okCount then
        AC.SetResult("wire.countDepth", "child-of-child region accepted")
    else
        -- Fall back to a direct region on the button (renders under the swipe).
        local direct = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        direct:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        local okDirect, errDirect = pcall(button.SetApplicationCount, button, direct, {})
        if okDirect then
            AC.SetResult("wire.countDepth", "child-of-child REJECTED; direct region accepted")
        else
            AC.SetResult("wire.count", "FAILED both depths: " .. safeToString(errDirect))
        end
    end

    -- Dispel-type border for debuffs (engine picks atlas and visibility).
    if groupKind == "debuff" then
        local dispel = button:CreateTexture(nil, "OVERLAY", nil, 1)
        dispel:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
        dispel:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
        local styleEnum = _G.Enum and _G.Enum.CustomAuraButtonDispelTypeTextureStyle
        local opts = {
            style = styleEnum and styleEnum.Border or 0,
            showWhenHarmful = true,
            showWhenHelpful = false,
        }
        local okDispel = pcall(button.AddDispelTypeTexture, button, dispel, opts)
        if not okDispel then
            local okBare, errBare = pcall(button.AddDispelTypeTexture, button, dispel)
            if okBare then
                AC.SetResult("wire.dispel", "options table rejected; bare call accepted")
            else
                AC.SetResult("wire.dispel", "FAILED: " .. safeToString(errBare))
            end
        end
    end

    -- Motion-only mouse: tooltips on hover, clicks fall through.
    pcall(button.SetMouseClickEnabled, button, false)
    pcall(button.SetMouseMotionEnabled, button, true)
    local okEnter, errEnter = pcall(button.SetScript, button, "OnEnter", onButtonEnter)
    pcall(button.SetScript, button, "OnLeave", onButtonLeave)
    if okEnter then
        AC.SetResult("wire.scripts", "SetScript OnEnter accepted on public button")
    else
        AC.SetResult("wire.scripts", "SetScript REJECTED: " .. safeToString(errEnter))
    end
end

local function makeInitializeFrame(entry, groupKind)
    return function(button)
        entry.buttonCount = (entry.buttonCount or 0) + 1
        table.insert(entry.buttons, button)
        AC.buttonOwner[button] = entry
        local ok, err = pcall(wireButton, button, entry, groupKind)
        if not ok then
            AC.SetResult("wire.fatal", safeToString(err))
        end
        AC.Record("initializeFrame", entry.unitKey .. " " .. groupKind .. " #" .. tostring(entry.buttonCount))
    end
end

--------------------------------------------------------------------------------
-- Container construction
--------------------------------------------------------------------------------

local function buffFilterString()
    local AU = _G.AuraUtil
    if AU and AU.CreateFilterString and AU.AuraFilters then
        return AU.CreateFilterString(AU.AuraFilters.Helpful)
    end
    return "HELPFUL"
end

local function debuffFilterString()
    local AU = _G.AuraUtil
    if AU and AU.CreateFilterString and AU.AuraFilters then
        return AU.CreateFilterString(AU.AuraFilters.Harmful, AU.AuraFilters.IncludeNameplateOnly)
    end
    return "HARMFUL|INCLUDE_NAME_PLATE_ONLY"
end

function AC.BuildContainer(unitKey)
    if AC.containers[unitKey] then return AC.containers[unitKey] end
    if not AC.CanDoStructuralWork() then
        AC.Record("build", unitKey .. " blocked (combat or restricted); not built")
        return nil
    end

    local unitToken = UNITS[unitKey]
    if not unitToken then return nil end

    local okCreate, container = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if not okCreate or not container then
        AC.SetResult("build.create", "CreateFrame FAILED: " .. safeToString(container))
        return nil
    end
    AC.SetResult("build.create", "AuraContainer created (" .. unitKey .. ")")

    local entry = {
        unitKey = unitKey,
        unitToken = unitToken,
        container = container,
        buttons = {},
        buttonCount = 0,
    }
    AC.containers[unitKey] = entry

    local okUnit, errUnit = pcall(container.SetUnit, container, unitToken)
    if not okUnit then
        AC.SetResult("build.setUnit", "FAILED: " .. safeToString(errUnit))
    end

    local w, h = computeElementSize(unitKey, getUnitConfig(unitKey))

    local okBuffs, errBuffs = pcall(container.AddAuraGroup, container, "Buffs", buffFilterString(), {
        maxFrameCount = MAX_BUFFS,
        initializeFrame = makeInitializeFrame(entry, "buff"),
        layout = {
            elementSpacing = ELEMENT_SPACING,
            lineSpacing = LINE_SPACING,
            elementWidth = w,
            elementHeight = h,
        },
    })
    if not okBuffs then
        AC.SetResult("build.buffGroup", "AddAuraGroup FAILED: " .. safeToString(errBuffs))
    end

    local okDebuffs, errDebuffs = pcall(container.AddAuraGroup, container, "Debuffs", debuffFilterString(), {
        maxFrameCount = MAX_DEBUFFS,
        initializeFrame = makeInitializeFrame(entry, "debuff"),
        layout = {
            elementSpacing = ELEMENT_SPACING,
            lineSpacing = LINE_SPACING,
            groupLineSpacing = LINE_SPACING,
            forceNewLine = true,
            elementWidth = w,
            elementHeight = h,
        },
    })
    if not okDebuffs then
        AC.SetResult("build.debuffGroup", "AddAuraGroup FAILED: " .. safeToString(errDebuffs))
    end

    pcall(container.SetFlowLayoutMaximumLineSize, container, LINE_SIZE)

    AC.AnchorContainer(unitKey)
    AC.Record("build", unitKey .. " built; buttons pre-created: " .. tostring(entry.buttonCount))
    return entry
end

function AC.AnchorContainer(unitKey)
    local entry = AC.containers[unitKey]
    if not entry then return end
    local anchorTex = resolveAnchorTexture(unitKey)
    local cfg = getUnitConfig(unitKey)
    local offsetX = cfg and tonumber(cfg.offsetX) or 0
    local offsetY = cfg and tonumber(cfg.offsetY) or 0

    entry.container:ClearAllPoints()
    if anchorTex then
        entry.container:SetPoint("TOPLEFT", anchorTex, "BOTTOMLEFT", ANCHOR_X + offsetX, ANCHOR_Y + offsetY)
    else
        entry.container:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
        AC.Record("anchor", unitKey .. " FrameTexture not found; centered fallback")
    end
end

--------------------------------------------------------------------------------
-- Config application (styling pathway; settings changes route through here)
--------------------------------------------------------------------------------

function AC.ApplyConfig(unitKey)
    local entry = AC.containers[unitKey]
    if not entry then return end
    local cfg = getUnitConfig(unitKey)

    AC.AnchorContainer(unitKey)

    if cfg and cfg.hideBuffsDebuffs == true then
        entry.container:SetShown(false)
        return
    end
    entry.container:SetShown(true)

    if not AC.CanDoStructuralWork() then
        AC.Record("applyConfig", unitKey .. " layout deferred (combat or restricted)")
        entry.pendingApply = true
        return
    end
    entry.pendingApply = nil

    local w, h = computeElementSize(unitKey, cfg)
    pcall(entry.container.SetAuraGroupLayout, entry.container, "Buffs", {
        elementSpacing = ELEMENT_SPACING,
        lineSpacing = LINE_SPACING,
        elementWidth = w,
        elementHeight = h,
    })
    pcall(entry.container.SetAuraGroupLayout, entry.container, "Debuffs", {
        elementSpacing = ELEMENT_SPACING,
        lineSpacing = LINE_SPACING,
        groupLineSpacing = LINE_SPACING,
        forceNewLine = true,
        elementWidth = w,
        elementHeight = h,
    })
end

--------------------------------------------------------------------------------
-- Retarget kicks and recovery
--------------------------------------------------------------------------------

function AC.KickContainer(unitKey, reason)
    local entry = AC.containers[unitKey]
    if not entry then return end
    local ok, err = pcall(entry.container.UpdateAllAuras, entry.container)
    if ok then
        AC.Record("kick", unitKey .. " UpdateAllAuras ok (" .. reason .. ")")
        if InCombatLockdown and InCombatLockdown() then
            AC.SetResult("probe.kickInCombat", "UpdateAllAuras succeeded in combat")
        end
    else
        AC.Record("kick", unitKey .. " UpdateAllAuras FAILED (" .. reason .. "): " .. safeToString(err))
        if InCombatLockdown and InCombatLockdown() then
            AC.SetResult("probe.kickInCombat", "UpdateAllAuras FAILED in combat: " .. safeToString(err))
        end
    end
end

local eventsRegistered = false

local function onEvent(event)
    if event == "PLAYER_TARGET_CHANGED" then
        AC.KickContainer("Target", event)
    elseif event == "PLAYER_FOCUS_CHANGED" then
        AC.KickContainer("Focus", event)
    elseif event == "PLAYER_ENTERING_WORLD" then
        AC.KickContainer("Target", event)
        AC.KickContainer("Focus", event)
    elseif event == "PLAYER_REGEN_ENABLED" then
        for unitKey, entry in pairs(AC.containers) do
            if entry.pendingApply then
                AC.ApplyConfig(unitKey)
            end
            AC.KickContainer(unitKey, event)
        end
        AC.ReassertSuppression()
    end
end

local function ensureEvents()
    if eventsRegistered then return end
    eventsRegistered = true
    addon.Events.On("UnitFrames:AuraContainer", "PLAYER_TARGET_CHANGED", onEvent)
    addon.Events.On("UnitFrames:AuraContainer", "PLAYER_FOCUS_CHANGED", onEvent)
    addon.Events.On("UnitFrames:AuraContainer", "PLAYER_ENTERING_WORLD", onEvent)
    addon.Events.On("UnitFrames:AuraContainer", "PLAYER_REGEN_ENABLED", onEvent)
end

--------------------------------------------------------------------------------
-- Session activation (debug-driven during the pilot)
--------------------------------------------------------------------------------

function AC.Start()
    if AC.enabled then return true, "already started" end
    if not AC.CanDoStructuralWork() then
        return false, "cannot start now (combat or restricted); try again out of combat"
    end
    AC.enabled = true
    ensureEvents()
    AC.BuildContainer("Target")
    AC.BuildContainer("Focus")
    AC.ApplyConfig("Target")
    AC.ApplyConfig("Focus")
    AC.KickContainer("Target", "start")
    AC.KickContainer("Focus", "start")
    return true, "containers started for Target and Focus"
end

function AC.Stop()
    -- The engine offers no group teardown, so stop hides the containers and
    -- leaves the frames parked for the session.
    AC.enabled = false
    for unitKey, entry in pairs(AC.containers) do
        entry.container:SetShown(false)
        AC.Record("stop", unitKey .. " hidden")
    end
    AC.SetSuppressionAll("off")
    return true, "containers hidden; suppression reverted"
end

--------------------------------------------------------------------------------
-- Suppression of Blizzard's container (probe-gated; debug-triggered only).
-- Mode "maxzero": inbound SetMaxBuffs(0)/SetMaxDebuffs(0). Blizzard's
--   ConfigureAuraContainer re-applies its own values on every UpdateAuras, so
--   this needs event-driven re-assertion (no hooks on the system frame tree).
-- Mode "alpha": SetAlpha(0) plus mouse-off on Blizzard's container.
--------------------------------------------------------------------------------

local suppressionWatcher = nil

-- Tracks which units have had a suppression write applied this
-- session. The "off" revert only runs for touched units, so a session that
-- never enables suppression never writes to Blizzard's container at all.
AC.suppressionTouched = {}

local function applySuppression(unitKey)
    local mode = AC.suppression[unitKey] or "off"
    if mode == "off" and not AC.suppressionTouched[unitKey] then
        return
    end
    local blizzContainer = resolveBlizzardAuraContainer(unitKey)
    if not blizzContainer then
        AC.SetResult("suppress." .. unitKey, "Blizzard container not found")
        return
    end

    if mode ~= "off" then
        AC.suppressionTouched[unitKey] = true
    end

    if mode == "maxzero" then
        local okB, errB = pcall(blizzContainer.SetMaxBuffs, blizzContainer, 0)
        local okD, errD = pcall(blizzContainer.SetMaxDebuffs, blizzContainer, 0)
        AC.SetResult("probe.maxzero." .. unitKey,
            string.format("SetMaxBuffs(0) %s%s; SetMaxDebuffs(0) %s%s",
                okB and "ok" or "FAILED", okB and "" or (" (" .. safeToString(errB) .. ")"),
                okD and "ok" or "FAILED", okD and "" or (" (" .. safeToString(errD) .. ")")))
    elseif mode == "alpha" then
        local okA, errA = pcall(blizzContainer.SetAlpha, blizzContainer, 0)
        pcall(blizzContainer.SetMouseClickEnabled, blizzContainer, false)
        pcall(blizzContainer.SetMouseMotionEnabled, blizzContainer, false)
        AC.SetResult("probe.alpha." .. unitKey,
            okA and "SetAlpha(0) ok" or ("SetAlpha(0) FAILED: " .. safeToString(errA)))
    else
        pcall(blizzContainer.SetAlpha, blizzContainer, 1)
        pcall(blizzContainer.SetMouseClickEnabled, blizzContainer, true)
        pcall(blizzContainer.SetMouseMotionEnabled, blizzContainer, true)
        pcall(blizzContainer.SetMaxBuffs, blizzContainer, MAX_BUFFS)
        pcall(blizzContainer.SetMaxDebuffs, blizzContainer, MAX_DEBUFFS)
        AC.suppressionTouched[unitKey] = nil
        AC.Record("suppress", unitKey .. " reverted to off")
    end
end

function AC.ReassertSuppression()
    for unitKey, mode in pairs(AC.suppression) do
        if mode == "maxzero" then
            -- Deferred so this lands after Blizzard's own configure pass.
            local key = unitKey
            C_Timer.After(0.1, function() applySuppression(key) end)
        end
    end
end

local function onSuppressionEvent(_, event, unit)
    if event == "PLAYER_TARGET_CHANGED" or (event == "UNIT_AURA" and (unit == "target" or unit == "focus")) then
        AC.ReassertSuppression()
    end
end

local function ensureSuppressionWatcher()
    if suppressionWatcher then return end
    suppressionWatcher = CreateFrame("Frame")
    suppressionWatcher:SetScript("OnEvent", onSuppressionEvent)
    suppressionWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
    suppressionWatcher:RegisterUnitEvent("UNIT_AURA", "target", "focus")
end

function AC.SetSuppression(unitKey, mode)
    if mode ~= "off" and mode ~= "maxzero" and mode ~= "alpha" then
        return false, "unknown mode: " .. tostring(mode)
    end
    AC.suppression[unitKey] = mode
    if mode == "maxzero" then
        ensureSuppressionWatcher()
    end
    applySuppression(unitKey)
    return true, unitKey .. " suppression mode: " .. mode
end

function AC.SetSuppressionAll(mode)
    for unitKey in pairs(UNITS) do
        AC.SetSuppression(unitKey, mode)
    end
end

--------------------------------------------------------------------------------
-- Settings pathway: when the pilot is active, buffsDebuffs settings changes
-- restyle the Scoot container as well as running the legacy 12.0 path (which
-- self no-ops against the removed aura pools).
--------------------------------------------------------------------------------

do
    local baseApply = addon.ApplyUnitFrameBuffsDebuffsFor
    function addon.ApplyUnitFrameBuffsDebuffsFor(unit)
        if baseApply then baseApply(unit) end
        if AC.enabled then AC.ApplyConfig(unit) end
    end
end
