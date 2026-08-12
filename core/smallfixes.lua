-- smallfixes.lua - Small fixes for Blizzard behavior regressions (Quality of Life)
local addonName, addon = ...

addon.SmallFixes = addon.SmallFixes or {}
local SmallFixes = addon.SmallFixes

--------------------------------------------------------------------------------
-- DB Helpers
--------------------------------------------------------------------------------

local function getQoL()
    local profile = addon and addon.db and addon.db.profile
    return profile and profile.qol
end

local function ensureQoL()
    if not (addon and addon.db and addon.db.profile) then return nil end
    addon.db.profile.qol = addon.db.profile.qol or {}
    return addon.db.profile.qol
end

--------------------------------------------------------------------------------
-- Modifier + Left-Click Targeting
--
-- Since 12.0.7, SecureUnitButton_OnClick returns before it reaches the target
-- action whenever a modifier is held:
--
--     type = SecureButton_GetModifiedAttribute(self, "type", button)
--     local expectBinding = type == "target" or type == "menu" or type == "togglemenu"
--     if expectBinding and bindingType == Enum.ClickBindingType.None then return end
--
-- Unit buttons carry *type1 = "target", and the engine has no click binding for
-- a modified left-click, so the guard trips and the click is dropped. Routing
-- the modified click through "click" resolves the type to a delegate button
-- instead, and the delegate own handler (SecureActionButton_OnClick) has no
-- such guard.
--
-- The delegate is a child of the unit button and carries useparent-unit, so
-- group frames keep resolving the correct unit as the roster changes, including
-- changes that land mid-combat when no attribute could be rewritten.
--------------------------------------------------------------------------------

local MODIFIERS = { "shift", "ctrl", "alt" }

local SETTING_KEY = {
    shift = "modifierTargetShift",
    ctrl  = "modifierTargetCtrl",
    alt   = "modifierTargetAlt",
}

-- Weak keys throughout: state for frames we do not own lives here, never as
-- fields written onto the frames themselves.
local targetProxies = setmetatable({}, { __mode = "k" })
local attachedFrames = setmetatable({}, { __mode = "k" })

local pendingApply = false
local regenWatcher
local hooksInstalled = false

local UNIT_FRAME_NAME_PATTERNS = {
    "^PlayerFrame$",
    "^TargetFrame$",
    "^FocusFrame$",
    "^TargetFrameToT$",
    "^FocusFrameToT$",
    "^PetFrame$",
    "^Boss%d+TargetFrame$",
    "^CompactPartyFrameMember%d+$",
    "^CompactRaidFrame%d+$",
    "^CompactRaidGroup%d+Member%d+$",
    "^CompactArenaFrameMember%d+$",
    "^ArenaEnemyFrame%d+$",
    "^ArenaPrepFrame%d+$",
    "^PartyFrameMemberFrame%d+$",
}

local function IsModifierEnabled(mod)
    local qol = getQoL()
    if not qol then return false end
    return qol[SETTING_KEY[mod]] and true or false
end

local function AnyModifierEnabled()
    for _, mod in ipairs(MODIFIERS) do
        if IsModifierEnabled(mod) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Frame eligibility
--------------------------------------------------------------------------------

local function FrameName(frame)
    if frame and frame.GetName then
        return frame:GetName() or ""
    end
    return ""
end

local function MatchesUnitFrameName(name)
    if name == "" then return false end
    for _, pattern in ipairs(UNIT_FRAME_NAME_PATTERNS) do
        if name:match(pattern) then return true end
    end
    return false
end

-- Aura hosts and bar chrome carry unit data but are not click targets. Touching
-- them is what breaks private aura and buff display on compact frames.
local function IsAuraOrChromeFrame(frame)
    local name = FrameName(frame):lower()
    if name == "" then return false end
    return (name:find("buff", 1, true)
        or name:find("debuff", 1, true)
        or name:find("aura", 1, true)
        or name:find("dispel", 1, true)
        or name:find("private", 1, true)
        or name:find("cooldown", 1, true)
        or name:find("status", 1, true)
        or name:find("healthbar", 1, true)
        or name:find("manabar", 1, true)
        or name:find("powerbar", 1, true)) and true or false
end

-- Nameplates are out of scope: they are commonly replaced wholesale, and they
-- carry the same unit fields the compact-frame heuristic below looks for.
local function IsNameplateRelatedFrame(frame)
    if not frame then return false end

    local current = frame
    for _ = 1, 10 do
        if not current then break end
        if current.isNamePlate then return true end
        if FrameName(current):lower():find("nameplate", 1, true) then return true end
        current = current.GetParent and current:GetParent() or nil
    end

    return false
end

-- Top-level secure unit buttons only, never their children.
local function IsAllowedUnitButton(frame)
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then return false end
    if not frame.SetAttribute or not frame.GetAttribute then return false end
    if not frame.IsObjectType or not frame:IsObjectType("Button") then return false end
    if IsNameplateRelatedFrame(frame) then return false end
    if IsAuraOrChromeFrame(frame) then return false end

    if MatchesUnitFrameName(FrameName(frame)) then return true end

    -- Named compact party/raid/arena frames that the pattern list missed.
    if frame.unit and (frame.maxDebuffs ~= nil or frame.maxBuffs ~= nil) then
        if frame.optionTable or frame.groupType then return true end
    end

    if frame:GetAttribute("unit") and (frame:GetAttribute("type1") or frame:GetAttribute("*type1")) then
        return true
    end

    return false
end

--------------------------------------------------------------------------------
-- Delegate attach / detach
--------------------------------------------------------------------------------

local function GetTargetProxy(button)
    local proxy = targetProxies[button]
    if not proxy then
        -- Must be a CHILD of the unit button: SecureButton_GetModifiedAttribute
        -- resolves useparent-unit through the frame parent, so any other parent
        -- would break unit resolution.
        proxy = CreateFrame("Button", nil, button, "SecureActionButtonTemplate")
        proxy:SetSize(1, 1)
        proxy:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        proxy:SetAlpha(0)
        proxy:EnableMouse(false)
        proxy:RegisterForClicks("AnyUp")
        -- Bare "type" is the final fallback in the attribute resolution chain,
        -- so it answers for every modifier and button combination. *type1 is
        -- set alongside it to match the shape the stock unit loader uses.
        proxy:SetAttribute("type", "target")
        proxy:SetAttribute("*type1", "target")
        proxy:SetAttribute("useparent-unit", true)
        -- The delegate is driven by Click() on mouse up, not on key down.
        proxy:SetAttribute("useOnKeyDown", false)
        targetProxies[button] = proxy
    end
    return proxy
end

-- True when the modifier is currently routed through a delegate we created.
local function ModifierIsOurs(button, mod)
    local proxy = targetProxies[button]
    if not proxy then return false end

    local resolvedType = button:GetAttribute("*" .. mod .. "-type1")
        or button:GetAttribute(mod .. "-type1")
    if resolvedType ~= "click" then return false end

    local delegate = button:GetAttribute("*" .. mod .. "-clickbutton1")
        or button:GetAttribute(mod .. "-clickbutton1")
    return delegate == proxy
end

local function ShouldAttachForModifier(button, mod)
    if ModifierIsOurs(button, mod) then return false end

    -- Never stomp a binding someone else owns. "target" is the stock value the
    -- 12.0.7 guard rejects, so replacing that one is the whole point.
    local currentType = button:GetAttribute("*" .. mod .. "-type1")
        or button:GetAttribute(mod .. "-type1")
    if currentType and currentType ~= "target" and currentType ~= "click" then
        return false
    end

    return true
end

local function AttachModifier(button, mod)
    local proxy = GetTargetProxy(button)
    local ok = pcall(function()
        button:SetAttribute(mod .. "-type1", "click")
        button:SetAttribute(mod .. "-clickbutton1", proxy)
        button:SetAttribute("*" .. mod .. "-type1", "click")
        button:SetAttribute("*" .. mod .. "-clickbutton1", proxy)
    end)
    return ok
end

local function DetachModifier(button, mod)
    pcall(function()
        button:SetAttribute(mod .. "-type1", nil)
        button:SetAttribute(mod .. "-clickbutton1", nil)
        button:SetAttribute("*" .. mod .. "-type1", nil)
        button:SetAttribute("*" .. mod .. "-clickbutton1", nil)
    end)
end

-- The shared attribute recipe, with no eligibility check. Callers own that.
local function ApplyModifiersToButton(button)
    local touched = false

    for _, mod in ipairs(MODIFIERS) do
        if IsModifierEnabled(mod) then
            if ShouldAttachForModifier(button, mod) and AttachModifier(button, mod) then
                touched = true
            end
        elseif ModifierIsOurs(button, mod) then
            -- Only ever clear routing we installed ourselves.
            DetachModifier(button, mod)
            touched = true
        end
    end

    if touched then
        attachedFrames[button] = true
    end

    return touched
end

local function AttachTargetFix(frame)
    if not IsAllowedUnitButton(frame) then return false end
    return ApplyModifiersToButton(frame)
end

--------------------------------------------------------------------------------
-- Combat deferral
--
-- Flags only, never queued values: the drain re-runs the sweep so it recomputes
-- against whatever the settings and roster look like once combat ends.
--------------------------------------------------------------------------------

local function QueueApply()
    pendingApply = true

    if not regenWatcher then
        regenWatcher = CreateFrame("Frame")
        regenWatcher:SetScript("OnEvent", function(self)
            if InCombatLockdown() then return end
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            if pendingApply then
                pendingApply = false
                C_Timer.After(0, function() SmallFixes.ApplyAll() end)
            end
        end)
    end

    regenWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
end

--------------------------------------------------------------------------------
-- Frame sweeps
--------------------------------------------------------------------------------

local function TryGlobal(name)
    local frame = _G[name]
    if frame then AttachTargetFix(frame) end
end

local function ApplyCoreFrames()
    TryGlobal("PlayerFrame")
    TryGlobal("TargetFrame")
    TryGlobal("TargetFrameToT")
    TryGlobal("FocusFrame")
    TryGlobal("FocusFrameToT")
    TryGlobal("PetFrame")
    for i = 1, 5 do
        TryGlobal("Boss" .. i .. "TargetFrame")
    end
end

local function ApplyPartyFrames()
    for i = 1, 5 do
        TryGlobal("CompactPartyFrameMember" .. i)
        TryGlobal("PartyFrameMemberFrame" .. i)
    end

    local party = _G.PartyFrame
    if party then
        for i = 1, 5 do
            local member = party["MemberFrame" .. i]
            if member then AttachTargetFix(member) end
        end
    end
end

local function ApplyRaidFrames()
    for i = 1, 40 do
        TryGlobal("CompactRaidFrame" .. i)
    end
    for g = 1, 8 do
        for m = 1, 5 do
            TryGlobal(string.format("CompactRaidGroup%dMember%d", g, m))
        end
    end
end

local function ApplyArenaFrames()
    for i = 1, 5 do
        TryGlobal("ArenaEnemyFrame" .. i)
        TryGlobal("ArenaPrepFrame" .. i)
        TryGlobal("CompactArenaFrameMember" .. i)
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Applies the delegate to a secure unit button Scoot created itself. Callers
--- own the eligibility decision; the combat guard is handled here.
function SmallFixes.ApplyModifierProxies(button)
    if not button or not button.SetAttribute then return false end
    if InCombatLockdown() then return false end
    return ApplyModifiersToButton(button)
end

--- Re-sweeps every Blizzard unit frame in scope. Returns false, "combat" when
--- it had to defer.
function SmallFixes.ApplyAll()
    -- Zero-Touch: with nothing enabled and nothing previously attached there is
    -- no work and no reason to walk a single frame.
    if not AnyModifierEnabled() and next(attachedFrames) == nil then
        return true
    end

    if InCombatLockdown() then
        QueueApply()
        return false, "combat"
    end

    ApplyCoreFrames()
    ApplyPartyFrames()
    ApplyRaidFrames()
    ApplyArenaFrames()

    return true
end

--- Installs the hooks and event listeners this feature needs. Does nothing
--- until at least one modifier is enabled, so an unconfigured profile never
--- hooks anything.
function SmallFixes.EnsureHooks()
    if hooksInstalled then return end
    if not AnyModifierEnabled() then return end
    hooksInstalled = true

    -- Global function hook, not a hook on any system frame tree member.
    if type(_G.CompactUnitFrame_SetUpFrame) == "function" then
        hooksecurefunc("CompactUnitFrame_SetUpFrame", function(frame)
            if not AnyModifierEnabled() then return end
            if InCombatLockdown() then
                QueueApply()
                return
            end
            -- Deferred so the frame finishes its own setup first: attaching
            -- synchronously here disturbs private aura and buff display.
            C_Timer.After(0, function()
                if InCombatLockdown() then
                    QueueApply()
                    return
                end
                AttachTargetFix(frame)
            end)
        end)
    end

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("ARENA_OPPONENT_UPDATE")
    eventFrame:SetScript("OnEvent", function()
        if not AnyModifierEnabled() then return end
        C_Timer.After(0, function() SmallFixes.ApplyAll() end)
    end)
end

--- Setter used by the settings renderer. mod is "shift", "ctrl" or "alt".
function SmallFixes.SetModifierTargetEnabled(mod, enabled)
    local key = SETTING_KEY[mod]
    if not key then return end

    local qol = ensureQoL()
    if not qol then return end
    qol[key] = enabled and true or false

    SmallFixes.EnsureHooks()
    SmallFixes.ApplyAll()

    if addon.UnitFramesZ and addon.UnitFramesZ._RefreshClickModifiers then
        addon.UnitFramesZ._RefreshClickModifiers()
    end
end

function SmallFixes.IsModifierTargetEnabled(mod)
    return IsModifierEnabled(mod)
end

--------------------------------------------------------------------------------
-- Bootstrap
--------------------------------------------------------------------------------

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_ENTERING_WORLD")
bootstrap:SetScript("OnEvent", function()
    if not AnyModifierEnabled() then return end
    SmallFixes.EnsureHooks()
    -- Unit frames finish their own setup well after this event.
    C_Timer.After(0.5, function() SmallFixes.ApplyAll() end)
end)

return SmallFixes
