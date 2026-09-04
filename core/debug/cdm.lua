-- cdm.lua - Diagnostic dump of the CDM viewer styling pipeline state.
-- Usage: /scoot debug cdm
-- Shows, per Blizzard viewer, each gate of the styling pipeline (viewer
-- resolution, hooks, child enumeration, item-frame validity, component db,
-- Edit Mode path) so one run can locate where styling stops.
local addonName, addon = ...

-- The exact duck-type fields isValidCDMItemFrame() probes, plus lowercase icon
local FIELD_PROBES = { "Icon", "icon", "Cooldown", "ChargeCount", "Applications", "GetIconTexture" }

local function fmtBool(v) return v and "yes" or "NO" end

local function probeField(child, key)
    local ok, v = pcall(function() return child[key] end)
    if not ok then return "ERR" end
    return v ~= nil and "+" or "-"
end

local function safeShown(f)
    local ok, v = pcall(function() return f:IsShown() end)
    return ok and v == true
end

local function safeVisible(f)
    local ok, v = pcall(function() return f:IsVisible() end)
    return ok and v == true
end

local function safeSize(f)
    local ok, w, h = pcall(function() return f:GetWidth(), f:GetHeight() end)
    if ok and type(w) == "number" and type(h) == "number" then
        return string.format("%.0fx%.0f", w, h)
    end
    return "?"
end

function addon.DebugCDMState()
    local Overlays = addon.CDMOverlays
    local activeOverlays = Overlays and Overlays._activeOverlays
    local lastApply = Overlays and Overlays._lastApply
    local hookState = Overlays and Overlays._hookState
    local lines = {}
    local function push(s) table.insert(lines, s) end

    push("=== CDM Styling Pipeline State ===")
    push("")

    local now = GetTime()

    local overlayTotal = 0
    if activeOverlays then
        for _ in pairs(activeOverlays) do overlayTotal = overlayTotal + 1 end
    end
    push(string.format("Overlay system initialized: %s (active overlays: %d)",
        fmtBool(activeOverlays ~= nil), overlayTotal))
    push("Cleanup ticker started: " .. fmtBool(Overlays and Overlays._cleanupTickerStarted))
    local leoReady = addon.EditMode and addon.EditMode.IsReady and addon.EditMode.IsReady()
    push("Edit Mode override library ready: " .. fmtBool(leoReady))
    push("")

    -- CooldownFrame_Set is a global Blizzard also calls from scopes we cannot
    -- enter. Those frames arrive secret and are turned away before anything
    -- indexes them. Only counts are kept: reading identity off a secret handle
    -- is the thing being prevented.
    local hs = Overlays and Overlays._hookStats
    push("CooldownFrame_Set hook")
    if not hs then
        push("  (not installed)")
    else
        push(string.format("  total calls ...... %d", hs.calls or 0))
        push(string.format("  secret rejects ... %d", hs.rejects or 0))
        if hs.lastReject then
            push(string.format("  last reject ...... %.1fs ago", now - hs.lastReject))
            push("  last reject probe: " .. tostring(hs.lastShape or "?"))
        else
            push("  last reject ...... (none)")
        end
    end

    -- Tripwire: every live CDM cooldown frame must pass the same screen the hook
    -- applies. A non-zero rejected count means the guard is turning away frames
    -- it is supposed to be styling.
    local SS = addon.SecretSafe
    local censusOk, censusRejected = 0, 0
    for viewerName in pairs(addon.CDM_VIEWERS or {}) do
        local viewer = _G[viewerName]
        local okKids, kids = pcall(function() return { viewer:GetChildren() } end)
        if okKids then
            for _, child in ipairs(kids) do
                local cd = SS.plainFrame(child) and child.Cooldown
                if cd ~= nil then
                    if SS.plainFrame(cd) then
                        censusOk = censusOk + 1
                    else
                        censusRejected = censusRejected + 1
                    end
                end
            end
        end
    end
    push(string.format("  live CDM cooldowns: %d indexable, %d rejected", censusOk, censusRejected))
    if censusRejected > 0 then
        push("  WARNING: a rejected count above zero means the guard is over-rejecting")
    end
    push("")

    for viewerName, componentId in pairs(addon.CDM_VIEWERS or {}) do
        push(string.format("[%s] -> %s", viewerName, componentId))
        local viewer = _G[viewerName]
        if not viewer then
            push("  viewer global: MISSING")
        else
            push(string.format("  shown=%s visible=%s size=%s",
                tostring(safeShown(viewer)), tostring(safeVisible(viewer)), safeSize(viewer)))

            local component = addon.Components and addon.Components[componentId]
            if not component then
                push("  component: MISSING from addon.Components")
            elseif not component.db then
                push("  component: present, db: MISSING")
            else
                local db = component.db
                push(string.format(
                    "  component db: present (borderEnable=%s tallWideRatio=%s textCooldown=%s textStacks=%s iconZoom=%s)",
                    tostring(db.borderEnable), tostring(db.tallWideRatio),
                    tostring(db.textCooldown), tostring(db.textStacks), tostring(db.iconZoom)))
            end

            push("  viewer methods: " .. ((hookState and hookState[viewerName]) or "(no record)"))
            local rec = lastApply and lastApply[viewerName]
            if rec then
                push(string.format("  last apply: %.1fs ago -> %s", now - (rec.t or 0), rec.outcome or "?"))
            else
                push("  last apply: (never ran)")
            end

            local okKids, kids = pcall(function() return { viewer:GetChildren() } end)
            if not okKids then
                push("  GetChildren: ERROR " .. tostring(kids))
            else
                push(string.format("  GetChildren: %d children (fields = %s)",
                    #kids, table.concat(FIELD_PROBES, "/")))
                for i, child in ipairs(kids) do
                    local marks = {}
                    for _, key in ipairs(FIELD_PROBES) do
                        table.insert(marks, probeField(child, key))
                    end
                    local overlay = activeOverlays and activeOverlays[child]
                    push(string.format("    #%d shown=%s size=%s fields=%s overlay=%s",
                        i, tostring(safeShown(child)), safeSize(child),
                        table.concat(marks, "/"),
                        overlay and (safeShown(overlay) and "shown" or "hidden") or "none"))
                end
            end

            -- The 12.1 layout-children enumerator, for comparison with GetChildren
            local okIF, itemFrames = pcall(function() return viewer:GetItemFrames() end)
            if okIF and type(itemFrames) == "table" then
                push(string.format("  GetItemFrames: %d item frames", #itemFrames))
            elseif okIF then
                push("  GetItemFrames: returned " .. type(itemFrames))
            else
                push("  GetItemFrames: ERROR " .. tostring(itemFrames))
            end

            local okEM, hasEM = pcall(function()
                return addon.EditMode and addon.EditMode.HasEditModeSettings
                    and addon.EditMode.HasEditModeSettings(viewer)
            end)
            push("  Edit Mode settings reachable: " .. (okEM and tostring(hasEM) or ("ERROR " .. tostring(hasEM))))
        end
        push("")
    end

    if addon.DebugShowWindow then
        addon.DebugShowWindow("CDM Pipeline Diagnostic", table.concat(lines, "\n"))
    end
end

addon:RegisterDebugCommand({
    name = "cdm", help = "CDM styling pipeline state",
    handler = function() addon.DebugCDMState() end,
})
