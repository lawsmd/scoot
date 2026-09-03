-- base/utilities.lua - Shared component utilities: opacity, visibility, combat deferral, frame helpers
local addonName, addon = ...

local getState = addon.ComponentsUtil._getState
local getProp = addon.ComponentsUtil._getProp
local setProp = addon.ComponentsUtil._setProp

local Util = addon.ComponentsUtil

-- 12.1 secrecy gate: true when aura data is secret for addon code right now
-- (any combat, encounters, M+, PvP). Fail-closed: a missing probe result or a
-- secret return is treated as secret. Aura getters THROW from addon context
-- while this is true, so callers must bail before scanning, not after.
function addon.AurasSecretNow()
    local fn = C_Secrets and C_Secrets.ShouldAurasBeSecret
    if type(fn) ~= "function" then return false end
    local ok, secret = pcall(fn)
    if not ok then return true end
    if issecretvalue and issecretvalue(secret) then return true end
    return secret == true
end

--------------------------------------------------------------------------------
-- Aura identity expansion (shared by every AuraContainer consumer)
--------------------------------------------------------------------------------
-- candidateFilters.includeSpellIDs matches on the exact spell ID the engine
-- sees, and that is not always the ID a user picked: talent overrides, rank
-- variants and tooltip proxies all carry their own IDs. Cooldown Manager
-- config data stays fully readable in 12.1 even when aura data does not, so it
-- is the ground truth for which IDs are aliases of each other.
--
-- No early return anywhere in the walk. Blizzard keys several CDM entries on
-- one hidden base spell and only some of them carry the real aura as a linked
-- spell: Flame Shock's CDM base is 470411 (the debuff, 188389, is never a base
-- anywhere), and on Elemental the Essential entry lists no linked spells at all
-- while the Tracked Bar entry links 188389. Stopping at the first match built
-- {470411, 470057} and the tracker never fired. Union every matching entry.

addon.AuraIds = addon.AuraIds or {}
local AuraIds = addon.AuraIds

-- Enumerated rather than listed: 12.1 added categories 4-8 (GroupBuff,
-- SpecAgnostic*, EquipSlot*) and a hardcoded list would silently miss them.
local CDM_CATEGORIES = (function()
    local cat = Enum and Enum.CooldownViewerCategory
    if cat then
        local out = {}
        for _, v in pairs(cat) do
            if type(v) == "number" then table.insert(out, v) end
        end
        table.sort(out)
        if #out > 0 then return out end
    end
    return { 0, 1, 2, 3 }
end)()

-- Secret-safe numeric read: anything secret, non-numeric or non-positive
-- becomes nil.
local function PlainId(v)
    if type(v) == "number" and not issecretvalue(v) and v > 0 then return v end
    return nil
end
AuraIds.PlainId = PlainId

--- Unions every CDM alias of `lookupSpellId` into the `include` set.
--- @param include table set of [spellId] = true, mutated in place
--- @param lookupSpellId number the picked spell ID
function AuraIds.ExpandFromCDM(include, lookupSpellId)
    if not include or not lookupSpellId or not C_CooldownViewer then return end
    if not C_CooldownViewer.GetCooldownViewerCategorySet
        or not C_CooldownViewer.GetCooldownViewerCooldownInfo then
        return
    end
    for _, category in ipairs(CDM_CATEGORIES) do
        local ok, cooldownIDs = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, true)
        if ok and type(cooldownIDs) == "table" and not issecretvalue(cooldownIDs) then
            for _, cooldownID in ipairs(cooldownIDs) do
                if not issecretvalue(cooldownID) then
                    local iok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
                    if iok and type(info) == "table" and not issecretvalue(info) then
                        local sid = PlainId(info.spellID)
                        local oid = PlainId(info.overrideSpellID)
                        local tid = PlainId(info.overrideTooltipSpellID)
                        if sid == lookupSpellId or oid == lookupSpellId or tid == lookupSpellId then
                            if sid then include[sid] = true end
                            if oid then include[oid] = true end
                            if tid then include[tid] = true end
                            local linked = info.linkedSpellIDs
                            if type(linked) == "table" and not issecretvalue(linked) then
                                for _, lid in ipairs(linked) do
                                    lid = PlainId(lid)
                                    if lid then include[lid] = true end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- The walk above is not cheap: no early return, every category, one
-- GetCooldownViewerCooldownInfo per entry in each. It used to run once per
-- container build. It now also answers "could the engine's filter match this
-- id" for every spell description, so the expansion is memoised per spell and
-- the whole memo is dropped whenever the catalog itself can move. The
-- invalidator lives here rather than in a component because both ScootAuras
-- and the group-frame aura tracker read it and either module may be off.
local expansionCache = {}
local expansionVersion = 1

--- Bumps the epoch and drops every memoised expansion.
function AuraIds.InvalidateIncludeSets()
    expansionCache = {}
    expansionVersion = expansionVersion + 1
end

--- The current epoch, for callers memoising anything derived from an expansion
-- (scootauras/missing.lua IdSet holds ids, range and provider verdicts).
function AuraIds.GetVersion()
    return expansionVersion
end

--- The memoised CDM alias set for one spell, as [spellId] = true. Read-only;
-- a caller that needs a table of its own goes through BuildIncludeSet.
function AuraIds.GetExpansion(spellId)
    if type(spellId) ~= "number" then return nil end
    local set = expansionCache[spellId]
    if set then return set end
    set = { [spellId] = true }
    pcall(AuraIds.ExpandFromCDM, set, spellId)
    expansionCache[spellId] = set
    return set
end

--- True when `id` is one of the ids a filter built for `spellId` would match.
-- Allocates nothing, so it is safe on a per-description path.
function AuraIds.IncludesId(spellId, id)
    if type(id) ~= "number" then return false end
    if spellId == id then return true end
    local set = AuraIds.GetExpansion(spellId)
    return (set and set[id]) and true or false
end

--- Builds a fresh includeSpellIDs set for one tracked spell.
--- @param spellId number
--- @param extraIds table|nil array of additional IDs (linked registry variants)
--- @return table set of [spellId] = true
function AuraIds.BuildIncludeSet(spellId, extraIds)
    -- A fresh table every call: the result goes straight to the engine as
    -- candidateFilters.includeSpellIDs, and two live containers must never
    -- share one. extraIds stays out of the memo for the same reason, since
    -- only the group-frame tracker passes any.
    local include = {}
    local set = AuraIds.GetExpansion(spellId)
    if set then
        for id in pairs(set) do include[id] = true end
    elseif spellId then
        include[spellId] = true
    end
    if type(extraIds) == "table" then
        for _, id in ipairs(extraIds) do
            if type(id) == "number" then include[id] = true end
        end
    end
    return include
end

-- The catalog moves on these and nothing else.
-- COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED is deliberately absent: it reports one
-- spell being substituted, not the catalog changing, and invalidating there
-- would drop the whole memo every time a player shifts form.
local function onCatalogEvent(event, arg1)
    -- PLAYER_SPECIALIZATION_CHANGED fires for party and raid members too.
    if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 and arg1 ~= "player" then
        return
    end
    AuraIds.InvalidateIncludeSets()
end
-- Events.On tolerates names this client build rejects (returns a dead handle),
-- covering the COOLDOWN_VIEWER_* PTR drift the old pcall loop guarded against.
for _, event in ipairs({
    "COOLDOWN_VIEWER_DATA_LOADED",
    "COOLDOWN_VIEWER_TABLE_HOTFIXED",
    "TRAIT_CONFIG_UPDATED",
    "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_ENTERING_WORLD",
}) do
    addon.Events.On("AuraIds", event, onCatalogEvent)
end

-- Defers FullPowerFrame reapplies to avoid taint during combat. The frame is
-- the queue key; the payload re-reads the FrameState props at drain time so the
-- newest applyState closure runs, as the old pending-set watcher did.
local function queueFullPowerFrameReapply(fullPowerFrame)
    if not fullPowerFrame then return end
    addon.Events.RunOutOfCombat(function()
        local applyState = getProp(fullPowerFrame, "fullPowerApplyState")
        if getProp(fullPowerFrame, "fullPowerPendingReapply") and applyState then
            setProp(fullPowerFrame, "fullPowerPendingReapply", nil)
            applyState()
        end
    end, fullPowerFrame)
end

local function HideDefaultBarTextures(barFrame, restore)
    if not barFrame or not barFrame.GetRegions then return end
    local function matchesDefaultTexture(region)
        if not region or not region.GetObjectType or region:GetObjectType() ~= "Texture" then return false end
        local tex = region.GetTexture and region:GetTexture()
        if type(tex) == "string" and tex:find("UI%-HUD%-CoolDownManager") then
            return true
        end
        if region.GetAtlas then
            local atlas = region:GetAtlas()
            if type(atlas) == "string" and atlas:find("UI%-HUD%-CoolDownManager") then
                return true
            end
        end
        return false
    end
    local mediaState = addon.Media and addon.Media.GetBarFrameState and addon.Media.GetBarFrameState(barFrame)
    local scootBG = (mediaState and mediaState.bg) or getProp(barFrame, "ScootBG")
    local borderHolder = (addon.BarBorders and addon.BarBorders.GetBorderHolder and addon.BarBorders.GetBorderHolder(barFrame)) or barFrame.ScootStyledBorder
    for _, region in ipairs({ barFrame:GetRegions() }) do
        if region and region ~= scootBG and region ~= borderHolder and region ~= (borderHolder and borderHolder.Texture) then
            if region.GetObjectType and region:GetObjectType() == "Texture" then
                local layer = region:GetDrawLayer()
                if layer == "OVERLAY" or layer == "ARTWORK" or layer == "BORDER" then
                    if matchesDefaultTexture(region) then
                        region:SetAlpha(restore and 1 or 0)
                    end
                end
            end
        end
    end
end
Util.HideDefaultBarTextures = HideDefaultBarTextures

local function ToggleDefaultIconOverlay(iconFrame, restore)
    if not iconFrame or not iconFrame.GetRegions then return end
    for _, region in ipairs({ iconFrame:GetRegions() }) do
        if region and region.GetObjectType and region:GetObjectType() == "Texture" then
            if region.GetAtlas and region:GetAtlas() == "UI-HUD-CoolDownManager-IconOverlay" then
                region:SetAlpha(restore and 1 or 0)
            end
        end
    end
end
Util.ToggleDefaultIconOverlay = ToggleDefaultIconOverlay

local function PlayerInCombat()
    if InCombatLockdown() then
        return true
    end
    if UnitAffectingCombat("player") then
        return true
    end
    return false
end
Util.PlayerInCombat = PlayerInCombat

local function ClampOpacity(value, minValue)
    local v = tonumber(value) or 100
    local minClamp = tonumber(minValue) or 50
    if v < minClamp then
        v = minClamp
    elseif v > 100 then
        v = 100
    end
    return v
end
Util.ClampOpacity = ClampOpacity

local function ApplyFullPowerSpikeScale(ownerFrame, heightScale)
    if not ownerFrame or type(ownerFrame) ~= "table" then
        return
    end

    local fullPowerFrame = ownerFrame.FullPowerFrame
    if not fullPowerFrame or (fullPowerFrame.IsForbidden and fullPowerFrame:IsForbidden()) then
        return
    end

    local scaleY = tonumber(heightScale) or 1
    if scaleY <= 0 then
        scaleY = 1
    end
    if scaleY < 0.25 then
        scaleY = 0.25
    elseif scaleY > 6 then
        scaleY = 6
    end

    local spikeFrame = fullPowerFrame.SpikeFrame
    local pulseFrame = fullPowerFrame.PulseFrame

    local function captureDimensions(target)
        if not target or (target.IsForbidden and target:IsForbidden()) then
            return
        end
        local st = getState(target)
        if not st then return end
        if not st.fullPowerOrigWidth then
            if target.GetWidth then
                local ok, w = pcall(target.GetWidth, target)
                if ok and w and w > 0 then
                    st.fullPowerOrigWidth = w
                end
            end
        end
        if not st.fullPowerOrigHeight then
            if target.GetHeight then
                local ok, h = pcall(target.GetHeight, target)
                if ok and h and h > 0 then
                    st.fullPowerOrigHeight = h
                end
            end
        end
        if not st.fullPowerOrigScale then
            if target.GetScale then
                local ok, s = pcall(target.GetScale, target)
                if ok and s and s > 0 then
                    st.fullPowerOrigScale = s
                end
            end
        end
        if st.fullPowerOrigAlpha == nil and target.GetAlpha then
            local ok, a = pcall(target.GetAlpha, target)
            if ok and a ~= nil then
                st.fullPowerOrigAlpha = a
            end
        end
    end

    local function applySize(target, desiredScale)
        if not target or (target.IsForbidden and target:IsForbidden()) then
            return
        end
        local st = getState(target)
        if not st then return end
        local baseWidth = st.fullPowerOrigWidth
        local baseHeight = st.fullPowerOrigHeight
        local baseScale = st.fullPowerOrigScale

        if baseWidth and baseHeight and target.SetSize then
            local newHeight = math.max(1, baseHeight * desiredScale)
            pcall(target.SetSize, target, baseWidth, newHeight)
            return
        end

        local applied = false
        if baseHeight and target.SetHeight then
            local newHeight = math.max(1, baseHeight * desiredScale)
            pcall(target.SetHeight, target, newHeight)
            applied = true
        end
        if baseWidth and target.SetWidth then
            pcall(target.SetWidth, target, baseWidth)
            applied = true
        end

        if not applied and baseScale and target.SetScale then
            local newScale = baseScale * desiredScale
            if newScale < 0.25 then
                newScale = 0.25
            elseif newScale > 6 then
                newScale = 6
            end
            pcall(target.SetScale, target, newScale)
        end
    end

    local function applyHiddenState(target, hidden)
        if not target or (target.IsForbidden and target:IsForbidden()) then
            return
        end
        if hidden then
            if target.Hide then pcall(target.Hide, target) end
            if target.SetAlpha then pcall(target.SetAlpha, target, 0) end
        else
            if target.Show then pcall(target.Show, target) end
            local restoreAlpha = getProp(target, "fullPowerOrigAlpha")
            if restoreAlpha == nil then
                -- Default baseline: AlertSpikeStay/BigSpikeGlow start at alpha 0.
                restoreAlpha = 0
            end
            if target.SetAlpha then pcall(target.SetAlpha, target, restoreAlpha) end
        end
    end

    local function ensureCaptured()
        if getProp(fullPowerFrame, "fullPowerCaptured") then
            return
        end
        setProp(fullPowerFrame, "fullPowerCaptured", true)
        captureDimensions(fullPowerFrame)
        captureDimensions(spikeFrame)
        if spikeFrame then
            captureDimensions(spikeFrame.AlertSpikeStay)
            captureDimensions(spikeFrame.BigSpikeGlow)
        end
        captureDimensions(pulseFrame)
        if pulseFrame then
            captureDimensions(pulseFrame.YellowGlow)
            captureDimensions(pulseFrame.SoftGlow)
        end
    end

    local function applyAll(desiredScale, hidden)
        ensureCaptured()
        if hidden then
            if spikeFrame and spikeFrame.SpikeAnim and spikeFrame.SpikeAnim.Stop then
                pcall(spikeFrame.SpikeAnim.Stop, spikeFrame.SpikeAnim)
            end
            if fullPowerFrame.FadeoutAnim and fullPowerFrame.FadeoutAnim.Stop then
                pcall(fullPowerFrame.FadeoutAnim.Stop, fullPowerFrame.FadeoutAnim)
            end
            if fullPowerFrame.PulseFrame and fullPowerFrame.PulseFrame.PulseAnim and fullPowerFrame.PulseFrame.PulseAnim.Stop then
                pcall(fullPowerFrame.PulseFrame.PulseAnim.Stop, fullPowerFrame.PulseFrame.PulseAnim)
            end
        end
        applySize(fullPowerFrame, desiredScale)
        if spikeFrame then
            applySize(spikeFrame, desiredScale)
            applySize(spikeFrame.AlertSpikeStay, desiredScale)
            applySize(spikeFrame.BigSpikeGlow, desiredScale)
        end
        if pulseFrame then
            applySize(pulseFrame, desiredScale)
            applySize(pulseFrame.YellowGlow, desiredScale)
            applySize(pulseFrame.SoftGlow, desiredScale)
        end

        applyHiddenState(spikeFrame and spikeFrame.AlertSpikeStay, hidden)
        applyHiddenState(spikeFrame and spikeFrame.BigSpikeGlow, hidden)
        if pulseFrame then
            applyHiddenState(pulseFrame, hidden)
            applyHiddenState(pulseFrame.YellowGlow, hidden)
            applyHiddenState(pulseFrame.SoftGlow, hidden)
        end
    end

    local function applyState()
        ensureCaptured()
        local storedScale = getProp(fullPowerFrame, "fullPowerLatestScale") or 1
        local hidden = not not getProp(fullPowerFrame, "fullPowerHidden")
        applyAll(storedScale, hidden)
    end

    setProp(fullPowerFrame, "fullPowerLatestScale", scaleY)
    if getProp(fullPowerFrame, "fullPowerHidden") == nil then
        setProp(fullPowerFrame, "fullPowerHidden", false)
    end
    setProp(fullPowerFrame, "fullPowerApplyState", applyState)
    -- CRITICAL: Frame modifications during combat taint the execution context. Defer to PLAYER_REGEN_ENABLED.
    if InCombatLockdown and InCombatLockdown() then
        setProp(fullPowerFrame, "fullPowerPendingReapply", true)
        queueFullPowerFrameReapply(fullPowerFrame)
    else
        applyState()
    end

    if not getProp(fullPowerFrame, "fullPowerHooks") then
        setProp(fullPowerFrame, "fullPowerHooks", true)
        -- CRITICAL: Frame modifications during combat taint the execution context. Defer to PLAYER_REGEN_ENABLED.
        local function reapply()
            if InCombatLockdown and InCombatLockdown() then
                setProp(fullPowerFrame, "fullPowerPendingReapply", true)
                queueFullPowerFrameReapply(fullPowerFrame)
                return
            end
            applyState()
        end
        if fullPowerFrame.Initialize then
            hooksecurefunc(fullPowerFrame, "Initialize", reapply)
        end
        if fullPowerFrame.RemoveAnims then
            hooksecurefunc(fullPowerFrame, "RemoveAnims", reapply)
        end
        if fullPowerFrame.StartAnimIfFull then
            hooksecurefunc(fullPowerFrame, "StartAnimIfFull", reapply)
        end
        if spikeFrame and spikeFrame.SpikeAnim and spikeFrame.SpikeAnim.HookScript then
            spikeFrame.SpikeAnim:HookScript("OnPlay", reapply)
            spikeFrame.SpikeAnim:HookScript("OnFinished", reapply)
        end
        if pulseFrame and pulseFrame.PulseAnim and pulseFrame.PulseAnim.HookScript then
            pulseFrame.PulseAnim:HookScript("OnPlay", reapply)
            pulseFrame.PulseAnim:HookScript("OnFinished", reapply)
        end
    end
end
Util.ApplyFullPowerSpikeScale = ApplyFullPowerSpikeScale

local function SetFullPowerSpikeHidden(ownerFrame, hidden)
    if not ownerFrame or type(ownerFrame) ~= "table" then
        return
    end
    local fullPowerFrame = ownerFrame.FullPowerFrame
    if not fullPowerFrame or (fullPowerFrame.IsForbidden and fullPowerFrame:IsForbidden()) then
        return
    end
    setProp(fullPowerFrame, "fullPowerHidden", not not hidden)
    -- CRITICAL: Defer to after combat to avoid taint.
    if InCombatLockdown and InCombatLockdown() then
        -- Just store the hidden state; it will be applied after combat via queued reapply
        setProp(fullPowerFrame, "fullPowerPendingReapply", true)
        queueFullPowerFrameReapply(fullPowerFrame)
        return
    end
    if getProp(fullPowerFrame, "fullPowerHidden") then
        if fullPowerFrame.SpikeFrame and fullPowerFrame.SpikeFrame.SpikeAnim and fullPowerFrame.SpikeFrame.SpikeAnim.Stop then
            pcall(fullPowerFrame.SpikeFrame.SpikeAnim.Stop, fullPowerFrame.SpikeFrame.SpikeAnim)
        end
        if fullPowerFrame.PulseFrame and fullPowerFrame.PulseFrame.PulseAnim and fullPowerFrame.PulseFrame.PulseAnim.Stop then
            pcall(fullPowerFrame.PulseFrame.PulseAnim.Stop, fullPowerFrame.PulseFrame.PulseAnim)
        end
        if fullPowerFrame.FadeoutAnim and fullPowerFrame.FadeoutAnim.Stop then
            pcall(fullPowerFrame.FadeoutAnim.Stop, fullPowerFrame.FadeoutAnim)
        end
    end
    local applyState = getProp(fullPowerFrame, "fullPowerApplyState")
    if applyState then
        applyState()
    else
        Util.ApplyFullPowerSpikeScale(ownerFrame, getProp(fullPowerFrame, "fullPowerLatestScale") or 1)
        local applyState2 = getProp(fullPowerFrame, "fullPowerApplyState")
        if applyState2 then
            applyState2()
        end
    end
end
Util.SetFullPowerSpikeHidden = SetFullPowerSpikeHidden

-- Hide/show the Power Bar FeedbackFrame (Builder/Spender animation that flashes when power is spent/gained)
-- This frame shows a quick flash representing the amount of energy/mana/etc. spent or gained.
-- ownerFrame: the ManaBar or ClassNameplateManaBarFrame that contains the FeedbackFrame child
-- hidden: boolean - true to hide the feedback animation, false to restore it
local function SetPowerFeedbackHidden(ownerFrame, hidden)
    if not ownerFrame or type(ownerFrame) ~= "table" then
        return
    end
    local feedbackFrame = ownerFrame.FeedbackFrame
    if not feedbackFrame or (feedbackFrame.IsForbidden and feedbackFrame:IsForbidden()) then
        return
    end

    setProp(feedbackFrame, "powerFeedbackHidden", not not hidden)

    if feedbackFrame.SetAlpha then
        feedbackFrame:SetAlpha(hidden and 0 or 1)
    end
end
Util.SetPowerFeedbackHidden = SetPowerFeedbackHidden

-- Hide/show the Power Bar Spark (e.g., Elemental Shaman Maelstrom indicator)
-- Frame: ManaBar.Spark
-- ownerFrame: the ManaBar frame that contains the Spark child
-- hidden: boolean - true to hide the spark, false to restore it
--
-- IMPORTANT: SetAlpha(0) instead of Hide() to avoid taint during combat.
local function SetPowerBarSparkHidden(ownerFrame, hidden)
    if not ownerFrame or type(ownerFrame) ~= "table" then
        return
    end
    local sparkFrame = ownerFrame.Spark
    if not sparkFrame or (sparkFrame.IsForbidden and sparkFrame:IsForbidden()) then
        return
    end

    if hidden then
        setProp(sparkFrame, "powerBarSparkHidden", true)
        if sparkFrame.SetAlpha then
            pcall(sparkFrame.SetAlpha, sparkFrame, 0)
        end

        if _G.hooksecurefunc and not getProp(sparkFrame, "sparkVisibilityHooked") then
            setProp(sparkFrame, "sparkVisibilityHooked", true)

            _G.hooksecurefunc(sparkFrame, "Show", function(self)
                if getProp(self, "powerBarSparkHidden") and self.SetAlpha then
                    pcall(self.SetAlpha, self, 0)
                end
            end)

            if sparkFrame.UpdateShown then
                _G.hooksecurefunc(sparkFrame, "UpdateShown", function(self)
                    if getProp(self, "powerBarSparkHidden") and self.SetAlpha then
                        pcall(self.SetAlpha, self, 0)
                    end
                end)
            end

            -- CRITICAL: Use immediate re-enforcement with recursion guard, NOT C_Timer.After(0)
            -- Deferring causes visible flickering (texture visible for one frame before hiding)
            _G.hooksecurefunc(sparkFrame, "SetAlpha", function(self, alpha)
                if getProp(self, "powerBarSparkHidden") and alpha and alpha > 0 then
                    if not getProp(self, "settingAlpha") then
                        setProp(self, "settingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "settingAlpha", nil)
                    end
                end
            end)
        end
    else
        setProp(sparkFrame, "powerBarSparkHidden", false)
        if sparkFrame.SetAlpha then
            pcall(sparkFrame.SetAlpha, sparkFrame, 1)
        end
        if sparkFrame.UpdateShown then
            pcall(sparkFrame.UpdateShown, sparkFrame)
        end
    end
end
Util.SetPowerBarSparkHidden = SetPowerBarSparkHidden

-- Hide/show the Mana Cost Prediction overlay bar (Player only)
-- This bar shows the predicted mana/power cost of the currently casting spell.
-- Frame: ManaBar.ManaCostPredictionBar
-- ownerFrame: the ManaBar frame that contains the ManaCostPredictionBar child
-- hidden: boolean - true to hide the prediction bar, false to restore it
local function SetManaCostPredictionHidden(ownerFrame, hidden)
    if not ownerFrame or type(ownerFrame) ~= "table" then
        return
    end
    local predictionBar = ownerFrame.ManaCostPredictionBar
    if not predictionBar or (predictionBar.IsForbidden and predictionBar:IsForbidden()) then
        return
    end

    if hidden then
        setProp(predictionBar, "manaCostPredictionHidden", true)
        if predictionBar.SetAlpha then
            pcall(predictionBar.SetAlpha, predictionBar, 0)
        end

        if _G.hooksecurefunc and not getProp(predictionBar, "manaCostPredictionHooked") then
            setProp(predictionBar, "manaCostPredictionHooked", true)

            _G.hooksecurefunc(predictionBar, "Show", function(self)
                if getProp(self, "manaCostPredictionHidden") and self.SetAlpha then
                    pcall(self.SetAlpha, self, 0)
                end
            end)

            _G.hooksecurefunc(predictionBar, "SetAlpha", function(self, alpha)
                if getProp(self, "manaCostPredictionHidden") and alpha and alpha > 0 then
                    if not getProp(self, "settingAlpha") then
                        setProp(self, "settingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "settingAlpha", nil)
                    end
                end
            end)
        end
    else
        setProp(predictionBar, "manaCostPredictionHidden", false)
        if predictionBar.SetAlpha then
            pcall(predictionBar.SetAlpha, predictionBar, 1)
        end
    end
end
Util.SetManaCostPredictionHidden = SetManaCostPredictionHidden

-- Hide/show only the Power Bar textures (fill + background) while keeping text visible
-- ownerFrame: the ManaBar/PowerBar frame
-- hidden: boolean - true to hide textures only, false to restore them
--
-- IMPORTANT: Uses SetAlpha(0) with persistent hooks to survive combat and Blizzard updates.
-- SetAlpha is cosmetic and safe during combat.
local function SetPowerBarTextureOnlyHidden(ownerFrame, hidden)
    if not ownerFrame or type(ownerFrame) ~= "table" then
        return
    end

    local fillTex = ownerFrame.texture or (ownerFrame.GetStatusBarTexture and ownerFrame:GetStatusBarTexture())
    local bgTex = ownerFrame.Background
    -- Frame path (player): PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.ManaBarArea.ManaBar.ManaCostPredictionBar
    local manaCostPredictionBar = ownerFrame.ManaCostPredictionBar

    local function installAlphaHook(tex, flagName)
        if not tex then return end
        local st = getState(tex)
        if not st then return end
        local hookKey = flagName .. "Hooked"
        if st[hookKey] then return end
        st[hookKey] = true

        if _G.hooksecurefunc and tex.SetAlpha then
            _G.hooksecurefunc(tex, "SetAlpha", function(self, alpha)
                if getProp(self, flagName) and alpha and alpha > 0 then
                    if not getProp(self, "settingAlpha") then
                        setProp(self, "settingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "settingAlpha", nil)
                    end
                end
            end)
        end

        if _G.hooksecurefunc and tex.Show then
            _G.hooksecurefunc(tex, "Show", function(self)
                if getProp(self, flagName) and self.SetAlpha then
                    if not getProp(self, "settingAlpha") then
                        setProp(self, "settingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "settingAlpha", nil)
                    end
                end
            end)
        end
    end

    if hidden then
        if fillTex then
            setProp(fillTex, "powerBarFillHidden", true)
            if fillTex.SetAlpha then pcall(fillTex.SetAlpha, fillTex, 0) end
            installAlphaHook(fillTex, "powerBarFillHidden")
        end

        if bgTex then
            setProp(bgTex, "powerBarBGHidden", true)
            if bgTex.SetAlpha then pcall(bgTex.SetAlpha, bgTex, 0) end
            installAlphaHook(bgTex, "powerBarBGHidden")
        end

        if manaCostPredictionBar then
            setProp(manaCostPredictionBar, "powerBarManaCostPredHidden", true)
            if manaCostPredictionBar.SetAlpha then
                pcall(manaCostPredictionBar.SetAlpha, manaCostPredictionBar, 0)
            end
            installAlphaHook(manaCostPredictionBar, "powerBarManaCostPredHidden")
        end

        do
            local scBG = getProp(ownerFrame, "ScootBG")
            if scBG then
                setProp(scBG, "powerBarScootBGHidden", true)
                if scBG.SetAlpha then pcall(scBG.SetAlpha, scBG, 0) end
                installAlphaHook(scBG, "powerBarScootBGHidden")
            end
        end

        -- Also hide the power foreground overlay if present
        local st = getState(ownerFrame)
        if st and st.powerFill then
            st.powerFill:Hide()
        end
    else
        if fillTex then
            setProp(fillTex, "powerBarFillHidden", false)
            if fillTex.SetAlpha then pcall(fillTex.SetAlpha, fillTex, 1) end
        end

        if bgTex then
            setProp(bgTex, "powerBarBGHidden", false)
            if bgTex.SetAlpha then pcall(bgTex.SetAlpha, bgTex, 1) end
        end

        if manaCostPredictionBar then
            setProp(manaCostPredictionBar, "powerBarManaCostPredHidden", false)
            if manaCostPredictionBar.SetAlpha then
                pcall(manaCostPredictionBar.SetAlpha, manaCostPredictionBar, 1)
            end
        end

        do
            local scBG = getProp(ownerFrame, "ScootBG")
            if scBG then
                setProp(scBG, "powerBarScootBGHidden", false)
                -- Don't restore alpha here - let the background styling code handle it
            end
        end

        -- Restore power foreground overlay if it's active
        local st = getState(ownerFrame)
        if st and st.powerFill and st.powerOverlayActive then
            st.powerFill:Show()
        end
    end
end
Util.SetPowerBarTextureOnlyHidden = SetPowerBarTextureOnlyHidden

-- Resolve the TempMaxHealthLoss sibling StatusBar from a HealthBar.
-- TempMaxHealthLoss is a child of HealthBarsContainer (same parent as HealthBar).
local function resolveTempMaxHealthLoss(healthBar)
    if not healthBar then return nil end
    local parent = healthBar:GetParent()
    if not parent then return nil end
    if parent.TempMaxHealthLoss then return parent.TempMaxHealthLoss end
    if parent.PlayerFrameTempMaxHealthLoss then return parent.PlayerFrameTempMaxHealthLoss end
    return nil
end

-- Hide/restore the Health Bar fill texture and background while keeping text overlays visible.
local function SetHealthBarTextureOnlyHidden(ownerFrame, hidden)
    if not ownerFrame or type(ownerFrame) ~= "table" then
        return
    end

    -- OPT-33: Skip redundant work when the bar is already in the requested
    -- hidden state. The enforcement hooks (SetAlpha/Show/SetStatusBarColor)
    -- already maintain visibility, so repeated pcall operations are wasted.
    -- Exception 1: if a ScootBG was created since the last call (styling
    -- re-apply path), fall through so it gets hidden too.
    -- Exception 2: if the fill texture object was replaced (e.g. by
    -- SetStatusBarTexture in applyToBar), the new texture has no hooks.
    -- Verify the current fill texture still carries the hidden flag.
    if hidden then
        if getProp(ownerFrame, "healthBarColorHidden") then
            local currentFill = ownerFrame.texture or (ownerFrame.GetStatusBarTexture and ownerFrame:GetStatusBarTexture())
            if currentFill and not getProp(currentFill, "healthBarFillHidden") then
                -- Texture was replaced — fall through to re-hook the new one
            else
                local scBG = getProp(ownerFrame, "ScootBG")
                if not scBG or getProp(scBG, "healthBarScootBGHidden") then
                    return
                end
            end
        end
    end

    local fillTex = ownerFrame.texture or (ownerFrame.GetStatusBarTexture and ownerFrame:GetStatusBarTexture())
    local bgTex = ownerFrame.Background or ownerFrame.background

    -- Prediction/absorb StatusBar children that render on top of HealthBar.
    -- Leaving these visible while the main bar is hidden produces residual
    -- visuals (e.g. TotalAbsorbBar shield overlay on boss frames).
    local PREDICTION_BAR_KEYS = {
        "TotalAbsorbBar",
        "HealAbsorbBar",
        "MyHealPredictionBar",
        "OtherHealPredictionBar",
    }

    local function installAlphaHook(tex, flagName)
        if not tex then return end
        local st = getState(tex)
        if not st then return end
        local hookKey = flagName .. "Hooked"
        if st[hookKey] then return end
        st[hookKey] = true

        if _G.hooksecurefunc and tex.SetAlpha then
            _G.hooksecurefunc(tex, "SetAlpha", function(self, alpha)
                if getProp(self, flagName) and alpha and alpha > 0 then
                    if not getProp(self, "settingAlpha") then
                        setProp(self, "settingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "settingAlpha", nil)
                    end
                end
            end)
        end

        if _G.hooksecurefunc and tex.Show then
            _G.hooksecurefunc(tex, "Show", function(self)
                if getProp(self, flagName) and self.SetAlpha then
                    if not getProp(self, "settingAlpha") then
                        setProp(self, "settingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        pcall(self.Hide, self)
                        setProp(self, "settingAlpha", nil)
                    end
                end
            end)
        end
    end

    local function installBarColorHook(bar)
        if not bar then return end
        local st = getState(bar)
        if not st then return end
        if st.healthBarColorHooked then return end
        st.healthBarColorHooked = true

        if _G.hooksecurefunc and bar.SetStatusBarColor then
            _G.hooksecurefunc(bar, "SetStatusBarColor", function(self, r, g, b, a)
                if getProp(self, "healthBarColorHidden") and (not a or a > 0) then
                    if not getProp(self, "settingBarColor") then
                        setProp(self, "settingBarColor", true)
                        pcall(self.SetStatusBarColor, self, r or 0, g or 0, b or 0, 0)
                        setProp(self, "settingBarColor", nil)
                    end
                end
            end)
        end
    end

    if hidden then
        if fillTex then
            setProp(fillTex, "healthBarFillHidden", true)
            if fillTex.SetAlpha then pcall(fillTex.SetAlpha, fillTex, 0) end
            pcall(fillTex.Hide, fillTex)
            installAlphaHook(fillTex, "healthBarFillHidden")
        end

        if bgTex then
            setProp(bgTex, "healthBarBGHidden", true)
            if bgTex.SetAlpha then pcall(bgTex.SetAlpha, bgTex, 0) end
            pcall(bgTex.Hide, bgTex)
            installAlphaHook(bgTex, "healthBarBGHidden")
        end

        do
            local scBG = getProp(ownerFrame, "ScootBG")
            if scBG then
                setProp(scBG, "healthBarScootBGHidden", true)
                if scBG.SetAlpha then pcall(scBG.SetAlpha, scBG, 0) end
                pcall(scBG.Hide, scBG)
                installAlphaHook(scBG, "healthBarScootBGHidden")
            end
        end

        -- Hide the StatusBar fill color at the engine level
        setProp(ownerFrame, "healthBarColorHidden", true)
        if ownerFrame.SetStatusBarColor and ownerFrame.GetStatusBarColor then
            local r, g, b = ownerFrame:GetStatusBarColor()
            pcall(ownerFrame.SetStatusBarColor, ownerFrame, r, g, b, 0)
        end
        installBarColorHook(ownerFrame)

        -- Hide the TempMaxHealthLoss sibling (purple max health reduction bar)
        do
            local tmhl = resolveTempMaxHealthLoss(ownerFrame)
            if tmhl then
                setProp(tmhl, "tempMaxHealthLossHidden", true)
                local tmhlFill = tmhl.GetStatusBarTexture and tmhl:GetStatusBarTexture()
                if tmhlFill then
                    setProp(tmhlFill, "healthBarFillHidden", true)
                    if tmhlFill.SetAlpha then pcall(tmhlFill.SetAlpha, tmhlFill, 0) end
                    pcall(tmhlFill.Hide, tmhlFill)
                    installAlphaHook(tmhlFill, "healthBarFillHidden")
                end
                setProp(tmhl, "healthBarColorHidden", true)
                if tmhl.SetStatusBarColor and tmhl.GetStatusBarColor then
                    local r, g, b = tmhl:GetStatusBarColor()
                    pcall(tmhl.SetStatusBarColor, tmhl, r, g, b, 0)
                end
                installBarColorHook(tmhl)
            end
        end

        -- Hide prediction/absorb StatusBar children of the HealthBar
        for _, key in ipairs(PREDICTION_BAR_KEYS) do
            local bar = ownerFrame[key]
            if bar and not (bar.IsForbidden and bar:IsForbidden()) then
                setProp(bar, "predictionBarHidden", true)
                setProp(bar, "healthBarColorHidden", true)
                if bar.SetAlpha then pcall(bar.SetAlpha, bar, 0) end
                local barFill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
                if barFill then
                    setProp(barFill, "healthBarFillHidden", true)
                    if barFill.SetAlpha then pcall(barFill.SetAlpha, barFill, 0) end
                    pcall(barFill.Hide, barFill)
                    installAlphaHook(barFill, "healthBarFillHidden")
                end
                installAlphaHook(bar, "predictionBarHidden")
                installBarColorHook(bar)
            end
        end
    else
        -- Restore the StatusBar fill color
        setProp(ownerFrame, "healthBarColorHidden", false)
        if ownerFrame.SetStatusBarColor and ownerFrame.GetStatusBarColor then
            local r, g, b = ownerFrame:GetStatusBarColor()
            pcall(ownerFrame.SetStatusBarColor, ownerFrame, r, g, b, 1)
        end

        if fillTex then
            setProp(fillTex, "healthBarFillHidden", false)
            if fillTex.SetAlpha then pcall(fillTex.SetAlpha, fillTex, 1) end
            pcall(fillTex.Show, fillTex)
        end

        if bgTex then
            setProp(bgTex, "healthBarBGHidden", false)
            if bgTex.SetAlpha then pcall(bgTex.SetAlpha, bgTex, 1) end
            pcall(bgTex.Show, bgTex)
        end

        do
            local scBG = getProp(ownerFrame, "ScootBG")
            if scBG then
                setProp(scBG, "healthBarScootBGHidden", false)
                pcall(scBG.Show, scBG)
            end
        end

        -- Restore the TempMaxHealthLoss sibling
        do
            local tmhl = resolveTempMaxHealthLoss(ownerFrame)
            if tmhl then
                setProp(tmhl, "tempMaxHealthLossHidden", false)
                local tmhlFill = tmhl.GetStatusBarTexture and tmhl:GetStatusBarTexture()
                if tmhlFill then
                    setProp(tmhlFill, "healthBarFillHidden", false)
                    if tmhlFill.SetAlpha then pcall(tmhlFill.SetAlpha, tmhlFill, 1) end
                    pcall(tmhlFill.Show, tmhlFill)
                end
                setProp(tmhl, "healthBarColorHidden", false)
                if tmhl.SetStatusBarColor and tmhl.GetStatusBarColor then
                    local r, g, b = tmhl:GetStatusBarColor()
                    pcall(tmhl.SetStatusBarColor, tmhl, r, g, b, 1)
                end
            end
        end

        -- Restore prediction/absorb StatusBar children. Only restore alpha —
        -- Blizzard's own update functions drive Show/Hide based on real state.
        for _, key in ipairs(PREDICTION_BAR_KEYS) do
            local bar = ownerFrame[key]
            if bar and not (bar.IsForbidden and bar:IsForbidden()) then
                setProp(bar, "predictionBarHidden", false)
                setProp(bar, "healthBarColorHidden", false)
                if bar.SetAlpha then pcall(bar.SetAlpha, bar, 1) end
                local barFill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
                if barFill then
                    setProp(barFill, "healthBarFillHidden", false)
                    if barFill.SetAlpha then pcall(barFill.SetAlpha, barFill, 1) end
                    pcall(barFill.Show, barFill)
                end
            end
        end
    end
end
Util.SetHealthBarTextureOnlyHidden = SetHealthBarTextureOnlyHidden

-- Hide/show the Over Absorb Glow on the Player Health Bar
-- Frame: PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar.OverAbsorbGlow
-- ownerFrame: the HealthBar frame that contains the OverAbsorbGlow child
-- hidden: boolean - true to hide the glow, false to restore it
local function SetOverAbsorbGlowHidden(ownerFrame, hidden)
    if not ownerFrame or type(ownerFrame) ~= "table" then
        return
    end
    local glowFrame = ownerFrame.OverAbsorbGlow
    if not glowFrame or (glowFrame.IsForbidden and glowFrame:IsForbidden()) then
        return
    end
    setProp(glowFrame, "overAbsorbGlowHidden", not not hidden)

    if glowFrame.GetAlpha and getProp(glowFrame, "overAbsorbGlowOrigAlpha") == nil then
        local ok, a = pcall(glowFrame.GetAlpha, glowFrame)
        setProp(glowFrame, "overAbsorbGlowOrigAlpha", ok and (a or 1) or 1)
    end

    -- IMPORTANT: Do NOT call Hide()/Show() on this frame.
    -- Hide/Show on protected unitframe children is taint-prone and can later surface as blocked
    -- calls in unrelated Blizzard code paths (e.g., AlternatePowerBar:Hide()).
    --
    -- Uses SetAlpha(0) with persistent hooks.
    if getProp(glowFrame, "overAbsorbGlowHidden") then
        if glowFrame.SetAlpha then
            pcall(glowFrame.SetAlpha, glowFrame, 0)
        end

        if _G.hooksecurefunc and not getProp(glowFrame, "overAbsorbGlowVisibilityHooked") then
            setProp(glowFrame, "overAbsorbGlowVisibilityHooked", true)

            _G.hooksecurefunc(glowFrame, "Show", function(self)
                if getProp(self, "overAbsorbGlowHidden") and self.SetAlpha then
                    if not getProp(self, "settingAlpha") then
                        setProp(self, "settingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "settingAlpha", nil)
                    end
                end
            end)

            _G.hooksecurefunc(glowFrame, "SetAlpha", function(self, alpha)
                if getProp(self, "overAbsorbGlowHidden") and alpha and alpha > 0 and self.SetAlpha then
                    if not getProp(self, "settingAlpha") then
                        setProp(self, "settingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "settingAlpha", nil)
                    end
                end
            end)
        end
    else
        if glowFrame.SetAlpha then
            local restoreAlpha = getProp(glowFrame, "overAbsorbGlowOrigAlpha")
            if restoreAlpha == nil then restoreAlpha = 1 end
            pcall(glowFrame.SetAlpha, glowFrame, restoreAlpha)
        end
    end
end
Util.SetOverAbsorbGlowHidden = SetOverAbsorbGlowHidden

-- Hide/show the Heal Prediction bar on the Player Health Bar
-- Frame: PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar.MyHealPredictionBar
-- ownerFrame: the HealthBar frame that contains the MyHealPredictionBar child
-- hidden: boolean - true to hide the bar, false to restore it
local function SetHealPredictionHidden(ownerFrame, hidden)
    if not ownerFrame or type(ownerFrame) ~= "table" then
        return
    end
    local predictionFrame = ownerFrame.MyHealPredictionBar
    if not predictionFrame or (predictionFrame.IsForbidden and predictionFrame:IsForbidden()) then
        return
    end
    setProp(predictionFrame, "healPredictionHidden", not not hidden)

    if predictionFrame.GetAlpha and getProp(predictionFrame, "healPredictionOrigAlpha") == nil then
        local ok, a = pcall(predictionFrame.GetAlpha, predictionFrame)
        setProp(predictionFrame, "healPredictionOrigAlpha", ok and (a or 1) or 1)
    end

    -- IMPORTANT: Do NOT call Hide()/Show() on this frame.
    -- Hide/Show on protected unitframe children is taint-prone and can later surface as blocked
    -- calls in unrelated Blizzard code paths.
    --
    -- Uses SetAlpha(0) with persistent hooks.
    if getProp(predictionFrame, "healPredictionHidden") then
        if predictionFrame.SetAlpha then
            pcall(predictionFrame.SetAlpha, predictionFrame, 0)
        end

        if _G.hooksecurefunc and not getProp(predictionFrame, "healPredictionVisibilityHooked") then
            setProp(predictionFrame, "healPredictionVisibilityHooked", true)

            _G.hooksecurefunc(predictionFrame, "Show", function(self)
                if getProp(self, "healPredictionHidden") and self.SetAlpha then
                    if not getProp(self, "settingAlpha") then
                        setProp(self, "settingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "settingAlpha", nil)
                    end
                end
            end)

            _G.hooksecurefunc(predictionFrame, "SetAlpha", function(self, alpha)
                if getProp(self, "healPredictionHidden") and alpha and alpha > 0 and self.SetAlpha then
                    if not getProp(self, "settingAlpha") then
                        setProp(self, "settingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "settingAlpha", nil)
                    end
                end
            end)
        end
    else
        if predictionFrame.SetAlpha then
            local restoreAlpha = getProp(predictionFrame, "healPredictionOrigAlpha")
            if restoreAlpha == nil then restoreAlpha = 1 end
            pcall(predictionFrame.SetAlpha, predictionFrame, restoreAlpha)
        end
    end
end
Util.SetHealPredictionHidden = SetHealPredictionHidden

--- Hide/show the Health Loss Animation bar on the Player Health Bar
--- Frame: PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.PlayerFrameHealthBarAnimatedLoss
--- ownerFrame: the HealthBar frame whose parent (HealthBarsContainer) contains the AnimatedLoss sibling
--- hidden: boolean - true to hide the bar, false to restore it
local function SetHealthLossAnimationHidden(ownerFrame, hidden)
    if not ownerFrame or type(ownerFrame) ~= "table" then
        return
    end
    local parent = ownerFrame.GetParent and ownerFrame:GetParent()
    local animatedLossBar = parent and parent.PlayerFrameHealthBarAnimatedLoss
    if not animatedLossBar or (animatedLossBar.IsForbidden and animatedLossBar:IsForbidden()) then
        return
    end
    setProp(animatedLossBar, "healthLossAnimHidden", not not hidden)

    if animatedLossBar.GetAlpha and getProp(animatedLossBar, "healthLossAnimOrigAlpha") == nil then
        local ok, a = pcall(animatedLossBar.GetAlpha, animatedLossBar)
        setProp(animatedLossBar, "healthLossAnimOrigAlpha", ok and (a or 1) or 1)
    end

    -- IMPORTANT: Do NOT call Hide()/Show() on this frame.
    -- Hide/Show on protected unitframe children is taint-prone and can later surface as blocked
    -- calls in unrelated Blizzard code paths.
    --
    -- Uses SetAlpha(0) with persistent hooks.
    if getProp(animatedLossBar, "healthLossAnimHidden") then
        if animatedLossBar.SetAlpha then
            pcall(animatedLossBar.SetAlpha, animatedLossBar, 0)
        end

        if _G.hooksecurefunc and not getProp(animatedLossBar, "healthLossAnimVisibilityHooked") then
            setProp(animatedLossBar, "healthLossAnimVisibilityHooked", true)

            _G.hooksecurefunc(animatedLossBar, "Show", function(self)
                if getProp(self, "healthLossAnimHidden") and self.SetAlpha then
                    pcall(self.SetAlpha, self, 0)
                end
            end)

            _G.hooksecurefunc(animatedLossBar, "SetAlpha", function(self, alpha)
                if getProp(self, "healthLossAnimHidden") and alpha and alpha > 0 then
                    if not getProp(self, "healthLossAnimSettingAlpha") then
                        setProp(self, "healthLossAnimSettingAlpha", true)
                        pcall(self.SetAlpha, self, 0)
                        setProp(self, "healthLossAnimSettingAlpha", nil)
                    end
                end
            end)
        end
    else
        if animatedLossBar.SetAlpha then
            local restoreAlpha = getProp(animatedLossBar, "healthLossAnimOrigAlpha")
            if restoreAlpha == nil then restoreAlpha = 1 end
            pcall(animatedLossBar.SetAlpha, animatedLossBar, restoreAlpha)
        end
    end
end
Util.SetHealthLossAnimationHidden = SetHealthLossAnimationHidden

-- Hook frame[method] exactly once, tracked via FrameState.IsHooked/MarkHooked.
-- hookKey defaults to "hooked_<method>". Returns true if installed, false if already hooked.
local function HookOnce(frame, method, hookFn, hookKey)
    if not frame or not method or not hookFn then return false end
    local FS = addon.FrameState
    if not FS then return false end
    hookKey = hookKey or ("hooked_" .. method)
    if FS.IsHooked(frame, hookKey) then return false end
    if not frame[method] then return false end
    hooksecurefunc(frame, method, hookFn)
    FS.MarkHooked(frame, hookKey)
    return true
end
Util.HookOnce = HookOnce
