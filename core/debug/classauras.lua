local addonName, addon = ...

--[[----------------------------------------------------------------------------
    Class Auras: UNIT_AURA event counter (lightweight diagnostic)

    Purpose:
      Tracks how many UNIT_AURA events fire per unit token since login/reload.
      Displayed in the Class Auras debug dump to confirm events are reaching us.
----------------------------------------------------------------------------]]--

local caUnitAuraCounts = {}   -- [unitToken] = count
local caUnitAuraFrame = CreateFrame("Frame")
caUnitAuraFrame:RegisterEvent("UNIT_AURA")
caUnitAuraFrame:SetScript("OnEvent", function(_, _, unit)
    if unit then
        caUnitAuraCounts[unit] = (caUnitAuraCounts[unit] or 0) + 1
    end
end)

--[[----------------------------------------------------------------------------
    Class Auras debug dump

    Purpose:
      Diagnostic dump for the Class Auras system, showing registered auras,
      CDM borrow state, and CDM Tracked Buffs probe results.

    Usage:
      /scoot debug classauras
      /scoot debug ca
----------------------------------------------------------------------------]]--

function addon.DebugDumpClassAuras()
    local CA = addon.ClassAuras
    if not CA then
        addon.DebugShowWindow("Class Auras Debug", "Class Auras module not loaded.")
        return
    end

    local lines = {}
    local function push(s) table.insert(lines, s) end

    push("=== Class Auras Debug ===")
    push("")

    -- Player info
    local _, playerClass = UnitClass("player")
    push("Player Class: " .. tostring(playerClass))

    -- Target info
    local targetName = UnitName("target")
    local targetGUID = UnitGUID("target")
    if targetName and targetGUID then
        push("Current Target: " .. tostring(targetName) .. " (GUID: " .. tostring(targetGUID) .. ")")
    else
        push("Current Target: No Target")
    end

    -- Secret restrictions
    local hasSecrets = C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions()
    push("Secrets Restricted: " .. tostring(hasSecrets or false))
    push("In Combat: " .. tostring(InCombatLockdown()))

    -- CDM Borrow state
    local cdmBorrowState = CA._cdmBorrow
    push("CDM borrow mixin-hook install ran: " .. tostring(cdmBorrowState and cdmBorrowState.hookInstalled or false))
    push("")

    -- Registered auras
    local classAuras = CA._classAuras and CA._classAuras[playerClass]
    if not classAuras or #classAuras == 0 then
        push("--- No Registered Auras for " .. tostring(playerClass) .. " ---")
    else
        push("--- Registered Auras ---")
        push("")

        for _, aura in ipairs(classAuras) do
            push("[" .. tostring(aura.id) .. "] " .. tostring(aura.label))

            -- Aura definition
            push("  spellId: " .. tostring(aura.auraSpellId) .. " | cdmSpellId: " .. tostring(aura.cdmSpellId or "same as auraSpellId") .. " | unit: " .. tostring(aura.unit) .. " | filter: " .. tostring(aura.filter))

            -- DB state
            local comp = addon.Components and addon.Components["classAura_" .. aura.id]
            local db = comp and comp.db
            push("  enabled: " .. tostring(db and db.enabled))

            -- Container state
            local state = CA._activeAuras and CA._activeAuras[aura.id]
            if state and state.container then
                local shown = state.container:IsShown()
                local scale = state.container:GetScale()
                push("  container: exists, shown=" .. tostring(shown) .. ", scale=" .. tostring(scale))

                -- Position
                local ok, point, _, _, x, y = pcall(state.container.GetPoint, state.container, 1)
                if ok and point then
                    push("  position: " .. tostring(point) .. " " .. tostring(math.floor((x or 0) + 0.5)) .. ", " .. tostring(math.floor((y or 0) + 0.5)))
                else
                    push("  position: unknown")
                end

                -- Element state
                if state.elements then
                    for _, elem in ipairs(state.elements) do
                        if elem.type == "text" then
                            local textOk, text = pcall(function() return elem.widget:GetText() end)
                            local textStr = (not textOk and "<error>") or (issecretvalue and issecretvalue(text) and "<SECRET>") or tostring(text or "")
                            push("  text element [" .. tostring(elem.def.source or "?") .. "]: " .. textStr)
                        elseif elem.type == "texture" then
                            push("  texture element: shown=" .. tostring(elem.widget:IsShown()))
                        end
                    end
                end
            else
                push("  container: NOT created")
            end

            -- CDM Borrow state
            push("  cdmBorrow: " .. tostring(aura.cdmBorrow or false))
            if aura.cdmBorrow then
                local itemFrame = CA._rescanForCDMBorrow and nil -- don't trigger rescan
                -- Read-only probe for CDM item
                pcall(function()
                    local viewer = _G.BuffIconCooldownViewer
                    local cdmId = aura.cdmSpellId or aura.auraSpellId
                    if viewer then
                        local children = { viewer:GetChildren() }
                        for _, child in ipairs(children) do
                            local idOk, childSpellId = pcall(function() return child:GetBaseSpellID() end)
                            if idOk and childSpellId == cdmId then
                                local shown = child:IsShown()
                                push("  CDM icon found: YES (shown=" .. tostring(shown) .. ")")
                                return
                            end
                        end
                    end
                    push("  CDM icon found: NO — Ensure the spell (or its passive) is in CDM > Tracked Buffs")
                end)
            end

            push("")
        end
    end

    -- ================================================================
    -- Slot Engine (12.1 AuraContainer path)
    -- ================================================================
    push("--- Slot Engine (12.1 AuraContainer path) ---")
    push("")
    if not CA.Engine then
        push("Engine module not loaded.")
        push("")
    else
        local anyEngine = false
        if classAuras then
            for _, aura in ipairs(classAuras) do
                if CA.Engine.IsEngineDriven(aura) then
                    anyEngine = true
                    local entry = CA.Engine._entries and CA.Engine._entries[aura.id]
                    local parts = { "[" .. tostring(aura.id) .. "] engine-driven" }
                    if not entry then
                        table.insert(parts, "built=no (zero-touch or not yet enabled)")
                    else
                        table.insert(parts, "built=" .. (entry.container and "yes" or "FAILED"))
                        table.insert(parts, "wired=" .. tostring(entry.wired or false))
                        table.insert(parts, "desiredEnabled=" .. tostring(entry.desiredEnabled))
                        if entry.enabledDirty then table.insert(parts, "enabledDirty=true") end
                    end
                    if CA.Engine._pendingApply and CA.Engine._pendingApply[aura.id] then
                        table.insert(parts, "PENDING APPLY (flushes at regen)")
                    end
                    push(table.concat(parts, " | "))
                end
            end
        end
        if not anyEngine then
            push("No engine-driven auras for this class.")
        end
        push("")
        local keys = {}
        for k in pairs(CA.Engine._results or {}) do table.insert(keys, k) end
        table.sort(keys)
        if #keys > 0 then
            push("Engine observations:")
            for _, k in ipairs(keys) do
                push("  " .. k .. " = " .. tostring(CA.Engine._results[k]))
            end
        else
            push("Engine observations: (none recorded)")
        end
        push("")
        local logEntries = {}
        for _, rec in pairs(CA.Engine._log or {}) do
            if rec and rec.seq then table.insert(logEntries, rec) end
        end
        table.sort(logEntries, function(a, b) return a.seq < b.seq end)
        if #logEntries > 0 then
            push("Engine log (oldest first):")
            for _, rec in ipairs(logEntries) do
                push(string.format("  #%d %s: %s", rec.seq, tostring(rec.tag), tostring(rec.detail)))
            end
        end
        push("")
    end

    -- ================================================================
    -- CDM Viewer Full Dump — list ALL items with all spell ID fields
    -- ================================================================
    push("")
    push("--- CDM Viewer Full Dump ---")
    push("")

    for _, viewerName in ipairs({ "BuffIconCooldownViewer", "BuffBarCooldownViewer" }) do
        local viewer = _G[viewerName]
        if not viewer then
            push("[" .. viewerName .. "] NOT FOUND (global is nil)")
        else
            push("[" .. viewerName .. "]")
            local ok, children = pcall(function() return { viewer:GetChildren() } end)
            if not ok then
                push("  GetChildren() FAILED: " .. tostring(children))
            elseif not children or #children == 0 then
                push("  No children (empty viewer)")
            else
                push("  Children count: " .. #children)
                -- Secret-safe tostring: returns "<SECRET>" instead of propagating taint
                local function safeStr(val)
                    if issecretvalue and issecretvalue(val) then return "<SECRET>" end
                    return tostring(val)
                end

                for i, child in ipairs(children) do
                    local line = "  [" .. i .. "] "

                    -- GetBaseSpellID (plain table read: cooldownInfo.spellID)
                    local baseOk, baseId = pcall(function() return child:GetBaseSpellID() end)
                    if baseOk then
                        line = line .. "baseSpellID=" .. safeStr(baseId)
                    else
                        line = line .. "baseSpellID=ERROR"
                    end

                    -- GetSpellID (resolution chain: aura → linked → override → base)
                    local spellOk, spellId = pcall(function() return child:GetSpellID() end)
                    if spellOk then
                        line = line .. " | spellID=" .. safeStr(spellId)
                    else
                        line = line .. " | spellID=ERROR"
                    end

                    -- cooldownInfo deep dump (plain table reads)
                    local ciOk, ciDump = pcall(function()
                        local ci = child:GetCooldownInfo()
                        if not ci then return "nil" end
                        local parts = {}
                        table.insert(parts, "spellID=" .. safeStr(ci.spellID))
                        if ci.linkedSpellIDs then
                            local ids = {}
                            for _, lid in ipairs(ci.linkedSpellIDs) do
                                table.insert(ids, safeStr(lid))
                            end
                            table.insert(parts, "linkedSpellIDs={" .. table.concat(ids, ",") .. "}")
                        end
                        if ci.linkedSpellID then
                            table.insert(parts, "linkedSpellID=" .. safeStr(ci.linkedSpellID))
                        end
                        if ci.overrideSpellID then
                            table.insert(parts, "overrideSpellID=" .. safeStr(ci.overrideSpellID))
                        end
                        if ci.overrideTooltipSpellID then
                            table.insert(parts, "overrideTooltipSpellID=" .. safeStr(ci.overrideTooltipSpellID))
                        end
                        return table.concat(parts, " | ")
                    end)
                    if ciOk and type(ciDump) == "string" then
                        line = line .. " | ci={" .. ciDump .. "}"
                    end

                    -- Shown state
                    local shownOk, isShown = pcall(child.IsShown, child)
                    if shownOk then
                        line = line .. " | shown=" .. tostring(isShown)
                    end

                    push(line)
                end
            end
        end
        push("")
    end

    -- Match tries (replay the exact logic from FindCDMItemForSpell)
    push("--- Match Replay for Registered Auras ---")
    push("")
    if classAuras then
        for _, aura in ipairs(classAuras) do
            if aura.cdmBorrow then
                local cdmId = aura.cdmSpellId or aura.auraSpellId
                push("[" .. aura.id .. "] Searching for cdmSpellId=" .. tostring(aura.cdmSpellId) .. ", auraSpellId=" .. tostring(aura.auraSpellId))

                -- Replay primary search (per-child pcall so one secret doesn't abort the loop)
                local primaryFrame = nil
                for _, viewerName in ipairs({ "BuffIconCooldownViewer", "BuffBarCooldownViewer" }) do
                    local viewer = _G[viewerName]
                    if viewer then
                        local childOk, children = pcall(function() return { viewer:GetChildren() } end)
                        if childOk and children then
                            for ci, child in ipairs(children) do
                                local idOk, baseId = pcall(function() return child:GetBaseSpellID() end)
                                if idOk then
                                    local isSecret = issecretvalue and issecretvalue(baseId)
                                    if isSecret then
                                        push("  " .. viewerName .. " child[" .. ci .. "] baseSpellID=<SECRET> — skipped")
                                    elseif baseId == cdmId then
                                        push("  PRIMARY MATCH: " .. viewerName .. " child[" .. ci .. "] baseSpellID=" .. tostring(baseId) .. " == " .. tostring(cdmId))
                                        primaryFrame = child
                                    end
                                end
                            end
                        end
                    end
                end
                if not primaryFrame then
                    push("  PRIMARY: no match for " .. tostring(cdmId))
                end

                -- Replay fallback search
                if not primaryFrame and aura.cdmSpellId and aura.auraSpellId then
                    local fallbackFrame = nil
                    for _, viewerName in ipairs({ "BuffIconCooldownViewer", "BuffBarCooldownViewer" }) do
                        local viewer = _G[viewerName]
                        if viewer then
                            local childOk, children = pcall(function() return { viewer:GetChildren() } end)
                            if childOk and children then
                                for ci, child in ipairs(children) do
                                    local idOk, baseId = pcall(function() return child:GetBaseSpellID() end)
                                    if idOk then
                                        local isSecret = issecretvalue and issecretvalue(baseId)
                                        if isSecret then
                                            -- already reported above
                                        elseif baseId == aura.auraSpellId then
                                            push("  FALLBACK MATCH: " .. viewerName .. " child[" .. ci .. "] baseSpellID=" .. tostring(baseId) .. " == " .. tostring(aura.auraSpellId))
                                            fallbackFrame = child
                                        end
                                    end
                                end
                            end
                        end
                    end
                    if not fallbackFrame then
                        push("  FALLBACK: no match for " .. tostring(aura.auraSpellId))
                    end
                end
                push("")
            end
        end
    end

    -- safePush: guards against secret/tainted values leaking into the lines table.
    -- tostring(secret) produces a tainted string that passes normal string ops
    -- but fails in table.concat. Use table.concat itself as the definitive test.
    local function safePush(s)
        local ok = pcall(function()
            if type(s) ~= "string" then s = tostring(s) end
            table.concat({s}) -- definitive test: fails on tainted strings
        end)
        if ok and type(s) == "string" then
            table.insert(lines, s)
        else
            table.insert(lines, "<secret value>")
        end
    end

    -- ================================================================
    -- UNIT_AURA Event Counter
    -- ================================================================
    safePush("")
    safePush("--- UNIT_AURA Event Counter (since reload) ---")
    safePush("")
    local hasAny = false
    for unit, count in pairs(caUnitAuraCounts) do
        safePush("  " .. tostring(unit) .. ": " .. tostring(count) .. " events")
        hasAny = true
    end
    if not hasAny then
        safePush("  (no UNIT_AURA events received yet)")
    end

    -- ================================================================
    -- A. ForEachAura Probe
    -- ================================================================
    safePush("")
    safePush("--- ForEachAura Probe ---")
    safePush("")

    -- Test ForEachAura directly
    local feaOk, feaErr = pcall(function()
        AuraUtil.ForEachAura("target", "HARMFUL", nil, function(auraData)
            return true -- stop after first
        end)
    end)
    safePush("AuraUtil.ForEachAura(target, HARMFUL): " .. (feaOk and "OK" or ("FAILED: " .. tostring(feaErr))))

    -- Test GetAuraSlots directly to isolate the failure point
    local gasOk, gasErr = pcall(function()
        if C_UnitAuras and C_UnitAuras.GetAuraSlots then
            local slots = C_UnitAuras.GetAuraSlots("target", "HARMFUL")
            return slots
        end
        return "API not found"
    end)
    if gasOk then
        safePush("C_UnitAuras.GetAuraSlots(target, HARMFUL): OK (returned: " .. type(gasErr) .. ")")
    else
        safePush("C_UnitAuras.GetAuraSlots(target, HARMFUL): FAILED: " .. tostring(gasErr))
    end

    -- ================================================================
    -- B. Alternative API Probes
    -- ================================================================
    safePush("")
    safePush("--- Alternative API Probes ---")
    safePush("")

    -- Probe: GetAuraDataByIndex (AllowedWhenTainted)
    safePush("[GetAuraDataByIndex] Scanning target HARMFUL slots 1-40:")
    local gadiFound = 0
    local gadiSpell1221389 = false
    for i = 1, 40 do
        local ok, result = pcall(function()
            return C_UnitAuras.GetAuraDataByIndex("target", i, "HARMFUL")
        end)
        if ok and result then
            gadiFound = gadiFound + 1
            local spellOk, spellId = pcall(function() return result.spellId end)
            local nameOk, spellName = pcall(function() return result.name end)
            local stackOk, stacks = pcall(function() return result.applications end)

            local isSecretSpell = spellOk and issecretvalue and issecretvalue(spellId)
            local isSecretName = nameOk and issecretvalue and issecretvalue(spellName)
            local isSecretStack = stackOk and issecretvalue and issecretvalue(stacks)

            local spellIdStr = (not spellOk and "<error>") or (isSecretSpell and "<SECRET>") or tostring(spellId)
            local nameStr = (not nameOk and "<error>") or (isSecretName and "<SECRET>") or tostring(spellName)
            local stackStr = (not stackOk and "<error>") or (isSecretStack and "<SECRET>") or tostring(stacks)

            safePush("  [" .. i .. "] spellId=" .. spellIdStr .. (isSecretSpell and " (SECRET)" or "") .. " name=" .. nameStr .. " stacks=" .. stackStr)

            -- Check for our target spell
            if spellOk and not isSecretSpell then
                pcall(function()
                    if spellId == 1221389 then gadiSpell1221389 = true end
                end)
            end
        elseif ok then
            break -- nil result = no more auras
        else
            safePush("  [" .. i .. "] ERROR: " .. tostring(result))
            break
        end
    end
    safePush("  Total found: " .. gadiFound .. " | Spell 1221389 found: " .. tostring(gadiSpell1221389))

    -- Probe: GetDebuffDataByIndex (AllowedWhenTainted)
    safePush("")
    safePush("[GetDebuffDataByIndex] Scanning target PLAYER slots 1-40:")
    local gddiFound = 0
    local gddiSpell1221389 = false
    for i = 1, 40 do
        local ok, result = pcall(function()
            return C_UnitAuras.GetDebuffDataByIndex("target", i, "PLAYER")
        end)
        if ok and result then
            gddiFound = gddiFound + 1
            local spellOk, spellId = pcall(function() return result.spellId end)
            local nameOk, spellName = pcall(function() return result.name end)
            local stackOk, stacks = pcall(function() return result.applications end)

            local isSecretSpell = spellOk and issecretvalue and issecretvalue(spellId)
            local isSecretName = nameOk and issecretvalue and issecretvalue(spellName)
            local isSecretStack = stackOk and issecretvalue and issecretvalue(stacks)

            local spellIdStr = (not spellOk and "<error>") or (isSecretSpell and "<SECRET>") or tostring(spellId)
            local nameStr = (not nameOk and "<error>") or (isSecretName and "<SECRET>") or tostring(spellName)
            local stackStr = (not stackOk and "<error>") or (isSecretStack and "<SECRET>") or tostring(stacks)

            safePush("  [" .. i .. "] spellId=" .. spellIdStr .. (isSecretSpell and " (SECRET)" or "") .. " name=" .. nameStr .. " stacks=" .. stackStr)

            if spellOk and not isSecretSpell then
                pcall(function()
                    if spellId == 1221389 then gddiSpell1221389 = true end
                end)
            end
        elseif ok then
            break
        else
            safePush("  [" .. i .. "] ERROR: " .. tostring(result))
            break
        end
    end
    safePush("  Total found: " .. gddiFound .. " | Spell 1221389 found: " .. tostring(gddiSpell1221389))

    -- Probe: GetUnitAuraBySpellID (AllowedWhenTainted + RequiresNonSecretAura)
    safePush("")
    safePush("[GetUnitAuraBySpellID] Direct lookup for spell 1221389 on target:")
    local byIdOk, byIdResult = pcall(function()
        return C_UnitAuras.GetUnitAuraBySpellID("target", 1221389)
    end)
    if byIdOk then
        if byIdResult then
            local nameOk, spellName = pcall(function() return byIdResult.name end)
            local stackOk, stacks = pcall(function() return byIdResult.applications end)
            local nameStr = (not nameOk and "<error>") or (issecretvalue and issecretvalue(spellName) and "<SECRET>") or tostring(spellName)
            local stackStr = (not stackOk and "<error>") or (issecretvalue and issecretvalue(stacks) and "<SECRET>") or tostring(stacks)
            safePush("  Result: FOUND | name=" .. nameStr .. " stacks=" .. stackStr)

            -- Check if fields are secret
            local fields = { "spellId", "name", "applications", "duration", "expirationTime" }
            local secretFields = {}
            for _, field in ipairs(fields) do
                pcall(function()
                    local val = byIdResult[field]
                    if val ~= nil and issecretvalue and issecretvalue(val) then
                        table.insert(secretFields, field)
                    end
                end)
            end
            if #secretFields > 0 then
                safePush("  Secret fields: " .. table.concat(secretFields, ", "))
            else
                safePush("  Secret fields: none detected")
            end
        else
            safePush("  Result: nil (aura not present or API returned nothing)")
        end
    else
        safePush("  Result: FAILED: " .. tostring(byIdResult))
    end

    -- ================================================================
    -- CDM Tracked Buffs Probe
    -- ================================================================
    safePush("")
    safePush("--- CDM Tracked Buffs Probe ---")
    safePush("")

    -- Check BuffIconCooldownViewer existence
    local cdmViewer = _G.BuffIconCooldownViewer
    safePush("BuffIconCooldownViewer: " .. (cdmViewer and "exists" or "NOT FOUND"))

    if cdmViewer then
        -- Enumerate children
        local cdmChildrenOk, cdmChildren = pcall(function() return { cdmViewer:GetChildren() } end)
        if cdmChildrenOk and cdmChildren then
            safePush("Children count: " .. tostring(#cdmChildren))
            safePush("")

            local freezingFound = false
            for i, child in ipairs(cdmChildren) do
                -- GetBaseSpellID() probe
                local spellIdOk, spellId = pcall(function() return child:GetBaseSpellID() end)
                local isSecret = spellIdOk and issecretvalue and issecretvalue(spellId)
                local spellIdStr = (not spellIdOk and "<error>") or (isSecret and "<SECRET>") or tostring(spellId)

                -- cooldownInfo.spellID direct table access probe
                local directOk, directSpellId = pcall(function()
                    return child.cooldownInfo and child.cooldownInfo.spellID
                end)
                local isDirectSecret = directOk and issecretvalue and issecretvalue(directSpellId)
                local directStr = (not directOk and "<error>") or (isDirectSecret and "<SECRET>") or tostring(directSpellId)

                -- GetApplicationsFontString() probe
                local fsOk, appFS = pcall(function() return child:GetApplicationsFontString() end)
                local fsStr = fsOk and (appFS and "exists" or "nil") or "<error>"

                -- Applications text GetText() probe
                local textStr = "<N/A>"
                if fsOk and appFS then
                    local textOk, text = pcall(function() return appFS:GetText() end)
                    if textOk then
                        local textSecretCheck = false
                        pcall(function()
                            if issecretvalue and text and issecretvalue(text) then
                                textSecretCheck = true
                            end
                        end)
                        if textSecretCheck then
                            textStr = "<SECRET>"
                        else
                            textStr = tostring(text or "")
                        end
                    else
                        textStr = "<error: " .. tostring(text) .. ">"
                    end
                end

                -- IsShown() probe
                local shownOk, isShown = pcall(function() return child:IsShown() end)
                local shownStr = shownOk and tostring(isShown) or "<error>"

                safePush("  [" .. i .. "] GetBaseSpellID()=" .. spellIdStr .. (isSecret and " (SECRET)" or "") ..
                    " | direct=" .. directStr ..
                    " | AppFS=" .. fsStr ..
                    " | text=" .. textStr ..
                    " | shown=" .. shownStr)

                -- Check for Freezing (1221389)
                if spellIdOk and not isSecret then
                    pcall(function()
                        if spellId == 1221389 then
                            freezingFound = true
                            safePush("    ^^ FREEZING (1221389) MATCH ^^")
                        end
                    end)
                end
            end

            safePush("")
            safePush("Freezing (1221389) found in CDM: " .. tostring(freezingFound))
        else
            safePush("GetChildren() failed: " .. tostring(cdmChildren))
        end
    end

    -- Mixin globals check
    safePush("")
    safePush("Mixin globals:")
    safePush("  CooldownViewerBuffIconItemMixin: " .. ((_G.CooldownViewerBuffIconItemMixin and "EXISTS") or "NOT FOUND"))
    safePush("  CooldownViewerItemMixin: " .. ((_G.CooldownViewerItemMixin and "EXISTS") or "NOT FOUND"))

    local buffMixin = _G.CooldownViewerBuffIconItemMixin
    if buffMixin then
        safePush("  .RefreshData: " .. (buffMixin.RefreshData and "exists" or "NOT FOUND"))
        safePush("  .GetBaseSpellID: " .. (buffMixin.GetBaseSpellID and "exists" or "NOT FOUND"))
        safePush("  .GetApplicationsFontString: " .. (buffMixin.GetApplicationsFontString and "exists" or "NOT FOUND"))
    end

    local baseMixin = _G.CooldownViewerItemMixin
    if baseMixin then
        safePush("  .OnAuraInstanceInfoCleared: " .. (baseMixin.OnAuraInstanceInfoCleared and "exists" or "NOT FOUND"))
    end

    -- ================================================================
    -- C. Secret Predicate Checks
    -- ================================================================
    safePush("")
    safePush("--- Secret Predicate Checks ---")
    safePush("")

    local hasRestrictions = false
    pcall(function()
        hasRestrictions = C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions()
    end)
    safePush("C_Secrets.HasSecretRestrictions(): " .. tostring(hasRestrictions))

    local aurasSecret = "N/A"
    pcall(function()
        if C_Secrets and C_Secrets.ShouldAurasBeSecret then
            aurasSecret = tostring(C_Secrets.ShouldAurasBeSecret())
        end
    end)
    safePush("C_Secrets.ShouldAurasBeSecret(): " .. aurasSecret)

    local issecretAvailable = (type(issecretvalue) == "function") and "yes" or "no"
    safePush("issecretvalue() available: " .. issecretAvailable)

    addon.DebugShowWindow("Class Auras Debug", table.concat(lines, "\n"))
end

--[[----------------------------------------------------------------------------
    Alter Time Health % Debug

    Purpose:
      Diagnostic dump for the Alter Time health % snapshot system.
      Probes every step of the pipeline: FontString creation, health APIs,
      snapshot state, anchoring, and visibility.

    Usage:
      /scoot debug altertime
      /scoot debug at
----------------------------------------------------------------------------]]--

function addon.DebugAlterTimeHealth()
    local CA = addon.ClassAuras
    if not CA then
        addon.DebugShowWindow("Alter Time Health Debug", "Class Auras module not loaded.")
        return
    end

    local lines = {}
    local function push(s) table.insert(lines, s) end

    -- Secret-safe tostring
    local function safe(val)
        if val == nil then return "nil" end
        local ok, result = pcall(function()
            if issecretvalue and issecretvalue(val) then return "<SECRET>" end
            return tostring(val)
        end)
        return ok and result or "<error>"
    end

    push("=== Alter Time Health % Debug ===")
    push("")

    -- ================================================================
    -- A. Aura Definition Integrity
    -- ================================================================
    push("--- A. Aura Definition ---")
    push("")

    local auraDef = CA._registry and CA._registry["alterTime"]
    push("CA._registry[\"alterTime\"]: " .. (auraDef and "EXISTS" or "NOT FOUND"))
    if auraDef then
        push("  auraSpellId: " .. safe(auraDef.auraSpellId))
        push("  cdmSpellId: " .. safe(auraDef.cdmSpellId))
        push("  unit: " .. safe(auraDef.unit))
        push("  filter: " .. safe(auraDef.filter))
        push("  onContainerCreated: " .. (auraDef.onContainerCreated and "assigned" or "NIL"))
        push("  onAuraFound: " .. (auraDef.onAuraFound and "assigned" or "NIL"))
        push("  onAuraMissing: " .. (auraDef.onAuraMissing and "assigned" or "NIL"))
        push("  onEditModeEnter: " .. (auraDef.onEditModeEnter and "assigned" or "NIL"))
        push("  onEditModeExit: " .. (auraDef.onEditModeExit and "assigned" or "NIL"))
        push("  additionalTabs: " .. (auraDef.additionalTabs and "assigned" or "NIL"))
    end

    -- DB state
    local comp = addon.Components and addon.Components["classAura_alterTime"]
    local db = comp and comp.db
    push("  Component DB: " .. (db and "exists" or "NOT FOUND"))
    if db then
        push("  enabled: " .. safe(db.enabled))
        push("  hideHealthText: " .. safe(db.hideHealthText))
        push("  healthTextFont: " .. safe(db.healthTextFont))
        push("  healthTextSize: " .. safe(db.healthTextSize))
        push("  healthTextPosition: " .. safe(db.healthTextPosition))
        push("  healthTextOuterAnchor: " .. safe(db.healthTextOuterAnchor))
        push("  healthTextInnerAnchor: " .. safe(db.healthTextInnerAnchor))
    end
    push("")

    -- ================================================================
    -- B. Container & FontString State
    -- ================================================================
    push("--- B. Container & FontString State ---")
    push("")

    local state = CA._activeAuras and CA._activeAuras["alterTime"]
    push("CA._activeAuras[\"alterTime\"]: " .. (state and "EXISTS" or "NOT FOUND"))

    if state then
        -- Container
        local c = state.container
        push("  container: " .. (c and "exists" or "NIL"))
        if c then
            local sok, shown = pcall(c.IsShown, c)
            push("  container:IsShown(): " .. (sok and safe(shown) or "<error>"))
            local aok, alpha = pcall(c.GetAlpha, c)
            push("  container:GetAlpha(): " .. (aok and safe(alpha) or "<error>"))
            local scok, scale = pcall(c.GetScale, c)
            push("  container:GetScale(): " .. (scok and safe(scale) or "<error>"))
        end

        -- Elements inventory
        if state.elements then
            push("  elements count: " .. #state.elements)
            for i, elem in ipairs(state.elements) do
                local eShown = pcall(elem.widget.IsShown, elem.widget) and elem.widget:IsShown()
                push("  elem[" .. i .. "]: type=" .. safe(elem.type) .. " key=" .. safe(elem.def and elem.def.key) .. " shown=" .. safe(eShown))
            end
        end

        -- Health % FontString
        local fs = state._healthPctFS
        push("")
        push("  _healthPctFS: " .. (fs and "EXISTS" or "*** NIL — onContainerCreated did NOT create it ***"))

        if fs then
            -- Shown
            local fsOk, fsShown = pcall(fs.IsShown, fs)
            push("  fs:IsShown(): " .. (fsOk and safe(fsShown) or "<error>"))

            -- Text
            local tOk, text = pcall(fs.GetText, fs)
            if tOk then
                local isSecret = issecretvalue and issecretvalue(text)
                push("  fs:GetText(): " .. (isSecret and "<SECRET>" or ('"' .. safe(text) .. '"')))
            else
                push("  fs:GetText(): <error>")
            end

            -- Alpha
            local aOk2, fsAlpha = pcall(fs.GetAlpha, fs)
            push("  fs:GetAlpha(): " .. (aOk2 and safe(fsAlpha) or "<error>"))

            -- Font
            local fOk, fontPath, fontSize, fontFlags = pcall(fs.GetFont, fs)
            if fOk then
                push("  fs:GetFont(): path=" .. safe(fontPath) .. " size=" .. safe(fontSize) .. " flags=" .. safe(fontFlags))
            else
                push("  fs:GetFont(): <error — font not set?>")
            end

            -- Dimensions
            local wOk, strW = pcall(fs.GetStringWidth, fs)
            local hOk2, strH = pcall(fs.GetStringHeight, fs)
            push("  fs:GetStringWidth(): " .. (wOk and safe(strW) or "<error>"))
            push("  fs:GetStringHeight(): " .. (hOk2 and safe(strH) or "<error>"))

            -- Anchor points
            local npOk, numPts = pcall(fs.GetNumPoints, fs)
            push("  fs:GetNumPoints(): " .. (npOk and safe(numPts) or "<error>"))
            if npOk and numPts and numPts > 0 then
                for pt = 1, numPts do
                    local ptOk, point, relTo, relPoint, xOfs, yOfs = pcall(fs.GetPoint, fs, pt)
                    if ptOk then
                        local relName = "nil"
                        if relTo then
                            local rnOk, rn = pcall(relTo.GetName, relTo)
                            relName = rnOk and safe(rn) or safe(tostring(relTo))
                        end
                        push("  anchor[" .. pt .. "]: " .. safe(point) .. " -> " .. relName .. ":" .. safe(relPoint) .. " (" .. safe(xOfs) .. ", " .. safe(yOfs) .. ")")
                    end
                end
            end

            -- TextColor
            local cOk, cR, cG, cB, cA = pcall(fs.GetTextColor, fs)
            if cOk then
                push("  fs:GetTextColor(): r=" .. safe(cR) .. " g=" .. safe(cG) .. " b=" .. safe(cB) .. " a=" .. safe(cA))
            else
                push("  fs:GetTextColor(): <error>")
            end
        end

        -- Snapshot state (engine path: own-cast toggle + timer + regen reconcile)
        push("")
        push("  _snapshotShown: " .. safe(state._snapshotShown))
        push("  _snapshotTimer: " .. (state._snapshotTimer and "running" or "nil"))
    end
    push("")

    -- ================================================================
    -- D. Health API Probe
    -- ================================================================
    push("--- D. Health API Probe ---")
    push("")

    -- UnitHealth
    local uhOk, uhVal = pcall(UnitHealth, "player")
    if uhOk then
        local isSecret = issecretvalue and issecretvalue(uhVal)
        push("UnitHealth(\"player\"): type=" .. type(uhVal) .. " value=" .. (isSecret and "<SECRET>" or safe(uhVal)) .. " secret=" .. safe(isSecret))
    else
        push("UnitHealth(\"player\"): ERROR — " .. safe(uhVal))
    end

    -- UnitHealthMax
    local umOk, umVal = pcall(UnitHealthMax, "player")
    if umOk then
        local isSecret = issecretvalue and issecretvalue(umVal)
        push("UnitHealthMax(\"player\"): type=" .. type(umVal) .. " value=" .. (isSecret and "<SECRET>" or safe(umVal)) .. " secret=" .. safe(isSecret))
    else
        push("UnitHealthMax(\"player\"): ERROR — " .. safe(umVal))
    end

    -- Computed percentage
    if uhOk and umOk and uhVal and umVal then
        local pctOk, pctVal = pcall(function()
            if issecretvalue and (issecretvalue(uhVal) or issecretvalue(umVal)) then return "<SECRET>" end
            if umVal == 0 then return "maxHealth=0" end
            return tostring(uhVal / umVal)
        end)
        push("Computed %: " .. (pctOk and safe(pctVal) or "<error>"))
    end

    -- UnitHealthPercent existence
    push("")
    push("UnitHealthPercent global: " .. (UnitHealthPercent and "EXISTS (type=" .. type(UnitHealthPercent) .. ")" or "*** NOT FOUND ***"))

    -- UnitHealthPercent without curve
    if UnitHealthPercent then
        local uhpOk, uhpVal = pcall(UnitHealthPercent, "player", true)
        if uhpOk then
            local isSecret = issecretvalue and issecretvalue(uhpVal)
            push("UnitHealthPercent(\"player\", true): type=" .. type(uhpVal) .. " value=" .. (isSecret and "<SECRET>" or safe(uhpVal)) .. " secret=" .. safe(isSecret))
        else
            push("UnitHealthPercent(\"player\", true): ERROR — " .. safe(uhpVal))
        end
    end

    -- Color curve
    local curve = addon.BarsTextures and addon.BarsTextures.getHealthValueCurve and addon.BarsTextures.getHealthValueCurve()
    push("")
    push("addon.BarsTextures.getHealthValueCurve(): " .. (curve and ("EXISTS (type=" .. type(curve) .. ")") or "*** NIL ***"))

    -- UnitHealthPercent with curve
    if UnitHealthPercent and curve then
        local ucOk, ucVal = pcall(UnitHealthPercent, "player", true, curve)
        if ucOk then
            local isSecret = issecretvalue and issecretvalue(ucVal)
            local hasGetRGB = ucVal and type(ucVal) ~= "number" and ucVal.GetRGB and true or false
            push("UnitHealthPercent(\"player\", true, curve): type=" .. type(ucVal) .. " secret=" .. safe(isSecret) .. " hasGetRGB=" .. safe(hasGetRGB))
            if hasGetRGB then
                local rgbOk, r, g, b = pcall(ucVal.GetRGB, ucVal)
                if rgbOk then
                    push("  GetRGB(): r=" .. safe(r) .. " g=" .. safe(g) .. " b=" .. safe(b))
                else
                    push("  GetRGB(): ERROR")
                end
            end
        else
            push("UnitHealthPercent(\"player\", true, curve): ERROR — " .. safe(ucVal))
        end
    end

    -- ================================================================
    -- E. Secret Operations Lab
    -- ================================================================
    push("")
    push("--- E. Secret Operations Lab ---")
    push("")

    -- Get the secret pct for testing
    local labPct = nil
    pcall(function() labPct = UnitHealthPercent("player", true) end)
    push("labPct = UnitHealthPercent(\"player\", true): " .. (labPct and ("got value, type=" .. type(labPct)) or "nil"))
    if not labPct then
        push("  Cannot run lab tests without a secret value.")
    else
        -- Create a temporary test FontString
        local labFrame = CreateFrame("Frame", nil, UIParent)
        local labFS = labFrame:CreateFontString(nil, "OVERLAY")
        labFS:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
        labFS:Hide()

        -- Test 1: SetText(secretNumber) directly
        local t1ok = pcall(function() labFS:SetText(labPct) end)
        local t1text = ""
        if t1ok then
            local gtOk, gtVal = pcall(labFS.GetText, labFS)
            t1text = gtOk and (issecretvalue and issecretvalue(gtVal) and "<SECRET_TEXT>" or safe(gtVal)) or "<GetText error>"
        end
        push("Test 1 - SetText(secretPct):            " .. (t1ok and "OK" or "FAILED") .. "  GetText=" .. t1text)

        -- Test 2: tostring(secretPct)
        local t2ok, t2val = pcall(function() return tostring(labPct) end)
        local t2info = ""
        if t2ok then
            t2info = issecretvalue and issecretvalue(t2val) and "<SECRET_STRING>" or safe(t2val)
        end
        push("Test 2 - tostring(secretPct):            " .. (t2ok and "OK" or "FAILED") .. "  result=" .. (t2ok and t2info or safe(t2val)))

        -- Test 3: math.floor(secretPct)
        local t3ok, t3val = pcall(function() return math.floor(labPct) end)
        push("Test 3 - math.floor(secretPct):          " .. (t3ok and "OK" or "FAILED") .. (not t3ok and "  err=" .. safe(t3val) or ""))

        -- Test 4: secretPct * 100
        local t4ok, t4val = pcall(function() return labPct * 100 end)
        push("Test 4 - secretPct * 100:                " .. (t4ok and "OK" or "FAILED") .. (not t4ok and "  err=" .. safe(t4val) or ""))

        -- Test 5: SetFormattedText("%.0f", secretPct)
        local t5ok = pcall(function() labFS:SetFormattedText("%.0f", labPct) end)
        local t5text = ""
        if t5ok then
            local gtOk, gtVal = pcall(labFS.GetText, labFS)
            t5text = gtOk and (issecretvalue and issecretvalue(gtVal) and "<SECRET_TEXT>" or safe(gtVal)) or "<GetText error>"
        end
        push("Test 5 - SetFormattedText('%.0f', pct):  " .. (t5ok and "OK" or "FAILED") .. "  GetText=" .. t5text)

        -- Test 6: SetFormattedText("%d", secretPct)
        local t6ok = pcall(function() labFS:SetFormattedText("%d", labPct) end)
        local t6text = ""
        if t6ok then
            local gtOk, gtVal = pcall(labFS.GetText, labFS)
            t6text = gtOk and (issecretvalue and issecretvalue(gtVal) and "<SECRET_TEXT>" or safe(gtVal)) or "<GetText error>"
        end
        push("Test 6 - SetFormattedText('%d', pct):    " .. (t6ok and "OK" or "FAILED") .. "  GetText=" .. t6text)

        -- Test 7: string.format("%.0f", secretPct)
        local t7ok, t7val = pcall(function() return string.format("%.0f", labPct) end)
        push("Test 7 - string.format('%.0f', pct):     " .. (t7ok and "OK" or "FAILED") .. (not t7ok and "  err=" .. safe(t7val) or ""))

        -- Test 8: SetText(tostring(secretPct)) if tostring worked
        if t2ok then
            local t8ok = pcall(function() labFS:SetText(tostring(labPct)) end)
            local t8text = ""
            if t8ok then
                local gtOk, gtVal = pcall(labFS.GetText, labFS)
                t8text = gtOk and (issecretvalue and issecretvalue(gtVal) and "<SECRET_TEXT>" or safe(gtVal)) or "<GetText error>"
            end
            push("Test 8 - SetText(tostring(pct)):         " .. (t8ok and "OK" or "FAILED") .. "  GetText=" .. t8text)
        end

        -- Test 9: Concatenation: "HP: " .. secretPct
        local t9ok, t9val = pcall(function() return "HP: " .. labPct end)
        push("Test 9 - \"HP: \" .. secretPct:            " .. (t9ok and "OK" or "FAILED") .. (not t9ok and "  err=" .. safe(t9val) or ""))

        -- Test 10-14: String manipulation on secret strings (key to extracting percentage)
        push("")
        push("-- String manipulation tests --")
        local fmtOk, fmtStr = pcall(function() return string.format("%.4f", labPct) end)
        push("Test 10 - string.format('%.4f', pct):    " .. (fmtOk and "OK" or "FAILED"))
        if fmtOk and fmtStr then
            local isSecret = issecretvalue and issecretvalue(fmtStr)
            push("  result type=" .. type(fmtStr) .. " secret=" .. safe(isSecret))

            -- Test 11: string.sub on the formatted secret string
            local t11ok, t11val = pcall(function() return string.sub(fmtStr, 3, 4) end)
            push("Test 11 - string.sub(formatted, 3, 4):   " .. (t11ok and "OK" or "FAILED") .. (t11ok and ("  result=" .. safe(t11val)) or ("  err=" .. safe(t11val))))

            -- Test 12: string.match on the formatted secret string
            local t12ok, t12val = pcall(function() return string.match(fmtStr, "^0%.(%d%d)") end)
            push("Test 12 - string.match('^0%%.(%d%d)'):   " .. (t12ok and "OK" or "FAILED") .. (t12ok and ("  result=" .. safe(t12val)) or ("  err=" .. safe(t12val))))

            -- Test 13: string.len on secret string
            local t13ok, t13val = pcall(function() return string.len(fmtStr) end)
            push("Test 13 - string.len(formatted):         " .. (t13ok and "OK" or "FAILED") .. (t13ok and ("  result=" .. safe(t13val)) or ""))

            -- Test 14: Full extraction approach - format → manipulate → SetText
            local t14ok = pcall(function()
                local raw = string.format("%.4f", labPct)  -- e.g., "0.8500" or "1.0000"
                local firstChar = string.sub(raw, 1, 1)
                local pctText
                if firstChar == "1" then
                    pctText = "100"
                elseif firstChar == "0" then
                    pctText = string.sub(raw, 3, 4)  -- extract "85" from "0.8500"
                    -- Remove leading zero: "05" → "5"
                    if string.sub(pctText, 1, 1) == "0" then
                        pctText = string.sub(pctText, 2, 2)
                    end
                else
                    pctText = "?"
                end
                labFS:SetText(pctText)
            end)
            local t14text = ""
            if t14ok then
                local gtOk, gtVal = pcall(labFS.GetText, labFS)
                t14text = gtOk and (issecretvalue and issecretvalue(gtVal) and "<SECRET_TEXT>" or safe(gtVal)) or "<GetText error>"
            end
            push("Test 14 - Full extract + SetText:         " .. (t14ok and "OK" or "FAILED") .. "  GetText=" .. t14text)
        end

        -- Cleanup
        labFS:Hide()
        labFrame:Hide()
    end

    -- ================================================================
    -- F. Player UF Health Text Probe
    -- ================================================================
    push("")
    push("--- F. Player UF Health Text Probe ---")
    push("")

    -- Scoot's cached health text FontStrings
    local ufCache = addon._ufHealthTextFonts and addon._ufHealthTextFonts["player"]
    push("addon._ufHealthTextFonts[\"player\"]: " .. (ufCache and "EXISTS" or "nil"))
    if ufCache then
        for key, fs in pairs(ufCache) do
            local tOk, text = pcall(fs.GetText, fs)
            local textStr = "?"
            if tOk then
                textStr = (issecretvalue and issecretvalue(text)) and "<SECRET>" or safe(text)
            end
            push("  [" .. safe(key) .. "] GetText=" .. textStr .. " IsShown=" .. safe(pcall(fs.IsShown, fs) and fs:IsShown()))
        end
    end

    -- Blizzard PlayerFrame health text
    local pf = _G.PlayerFrame
    push("PlayerFrame: " .. (pf and "EXISTS" or "nil"))
    if pf then
        -- Try common health text children
        for _, path in ipairs({"PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar.HealthBarText",
                               "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar.RightText",
                               "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar.LeftText"}) do
            local obj = pf
            local parts = {strsplit(".", path)}
            for i = 2, #parts do  -- skip "PlayerFrame"
                if obj then obj = obj[parts[i]] end
            end
            if obj and obj.GetText then
                local tOk, text = pcall(obj.GetText, obj)
                local textStr = tOk and ((issecretvalue and issecretvalue(text)) and "<SECRET>" or safe(text)) or "<error>"
                local sOk, shown = pcall(obj.IsShown, obj)
                push("  " .. path .. ": text=" .. textStr .. " shown=" .. (sOk and safe(shown) or "?"))
            end
        end
    end

    push("")
    push("=== End of Alter Time Health Debug ===")

    addon.DebugShowWindow("Alter Time Health Debug", table.concat(lines, "\n"))
end
