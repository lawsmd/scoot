--------------------------------------------------------------------------------
-- core/debug/repcolor.lua
-- ReputationColor lifecycle tracing (/scoot debug repcolor)
--
-- Background: the Target/Focus ReputationColor banner has intermittently
-- reappeared despite useCustomBorders hiding. Blizzard never writes this
-- texture's alpha or visibility (12.0 source: only SetVertexColor in
-- CheckFaction), so any visible banner means a Scoot hide pass was missed or
-- an unexpected writer set alpha back to 1. This module records both sides:
-- every alpha/visibility write on the textures (with a stack), and breadcrumbs
-- from the hide/enforce paths (including their bail reasons).
--
-- Storage is a plain addon-side ring buffer; nothing is written to Blizzard
-- frames. The trace hooks use hooksecurefunc on the textures, matching the
-- existing enforcer/SetVertexColor hook pattern on these exact objects.
--------------------------------------------------------------------------------

local addonName, addon = ...

local issecretvalue = _G.issecretvalue

local BUFFER_SIZE = 64
local buffer = {}
local writeIndex = 0

local function safeToString(v)
    local ty = type(v)
    if issecretvalue and issecretvalue(v) then
        return "<secret:" .. ty .. ">"
    end
    local ok, s = pcall(tostring, v)
    return ok and s or ("<" .. ty .. ">")
end

-- Breadcrumb entry point used by init.lua / preemptive.lua / alpha.lua.
-- Guarded at every call site (`if addon.RepColorTrace then ...`) so a missing
-- debug module is a no-op.
function addon.RepColorTrace(tag, detail)
    writeIndex = writeIndex + 1
    local slot = ((writeIndex - 1) % BUFFER_SIZE) + 1
    buffer[slot] = { t = GetTime(), seq = writeIndex, tag = tag, detail = detail }
end

local function resolveRepColor(unit)
    local root = (unit == "Target") and _G.TargetFrame or _G.FocusFrame
    return root and root.TargetFrameContent
        and root.TargetFrameContent.TargetFrameContentMain
        and root.TargetFrameContent.TargetFrameContentMain.ReputationColor
end

-- Variant for generic code paths (the alpha enforcer serves many textures);
-- records only when obj is one of the two tracked ReputationColor textures.
function addon.RepColorTraceIfTracked(obj, tag, detail)
    if not obj then return end
    if obj == resolveRepColor("Target") then
        addon.RepColorTrace(tag, "[Target] " .. detail)
    elseif obj == resolveRepColor("Focus") then
        addon.RepColorTrace(tag, "[Focus] " .. detail)
    end
end

--------------------------------------------------------------------------------
-- Trace hooks on the textures themselves
--------------------------------------------------------------------------------

local hookedTextures = setmetatable({}, { __mode = "k" })

local function shortStack()
    -- Skip this helper + the hook closure + hooksecurefunc dispatch.
    local ok, stack = pcall(debugstack, 3, 5, 0)
    if not ok or type(stack) ~= "string" then return "<no stack>" end
    -- Collapse to single line for the ring buffer.
    stack = stack:gsub("%s*\n%s*", " <- "):gsub("%s+", " ")
    return stack
end

local function installTraceHooks(unit)
    local tex = resolveRepColor(unit)
    if not tex or hookedTextures[tex] then return end
    hookedTextures[tex] = true
    local tag = "write:" .. unit

    _G.hooksecurefunc(tex, "SetAlpha", function(_, alpha)
        addon.RepColorTrace(tag, "SetAlpha(" .. safeToString(alpha) .. ") " .. shortStack())
    end)
    _G.hooksecurefunc(tex, "Show", function()
        addon.RepColorTrace(tag, "Show() " .. shortStack())
    end)
    if tex.SetShown then
        _G.hooksecurefunc(tex, "SetShown", function(_, shown)
            addon.RepColorTrace(tag, "SetShown(" .. safeToString(shown) .. ") " .. shortStack())
        end)
    end
    if tex.SetVertexColor then
        _G.hooksecurefunc(tex, "SetVertexColor", function()
            addon.RepColorTrace(tag, "SetVertexColor(...) " .. shortStack())
        end)
    end
end

addon.Events.On("Debug:RepColor", "PLAYER_ENTERING_WORLD", function()
    installTraceHooks("Target")
    installTraceHooks("Focus")
    addon.RepColorTrace("init", "trace hooks installed (PLAYER_ENTERING_WORLD)")
end)

--------------------------------------------------------------------------------
-- Watch ticker (opt-in): catches alpha transitions with no Lua SetAlpha trace
--------------------------------------------------------------------------------

local watchTicker
local lastWatchAlpha = {}

local function watchTick()
    for _, unit in ipairs({ "Target", "Focus" }) do
        local tex = resolveRepColor(unit)
        if tex then
            local ok, current = pcall(tex.GetAlpha, tex)
            if ok and type(current) == "number" and not (issecretvalue and issecretvalue(current)) then
                local last = lastWatchAlpha[unit]
                if last ~= nil and math.abs(last - current) > 0.001 then
                    addon.RepColorTrace("watch:" .. unit,
                        string.format("alpha %.2f -> %.2f (check buffer for a matching SetAlpha; none = untracked writer)", last, current))
                end
                lastWatchAlpha[unit] = current
            end
        end
    end
end

--------------------------------------------------------------------------------
-- /scoot debug repcolor [watch]
--------------------------------------------------------------------------------

local function describeCfg(unit)
    local db = addon and addon.db and addon.db.profile
    if not db then return "db.profile=nil" end
    local unitFrames = rawget(db, "unitFrames")
    if not unitFrames then return "unitFrames=nil" end
    local cfg = rawget(unitFrames, unit)
    if not cfg then return "cfg=nil" end
    return "useCustomBorders=" .. safeToString(cfg.useCustomBorders)
end

local function describeTexture(unit)
    local tex = resolveRepColor(unit)
    if not tex then return "texture=unresolved" end
    local okA, alpha = pcall(tex.GetAlpha, tex)
    local okS, shown = pcall(tex.IsShown, tex)
    local okV, visible = pcall(tex.IsVisible, tex)
    local FS = addon.FrameState
    local enforced = FS and FS.IsHooked and FS.IsHooked(tex, "alphaEnforcer") or false
    return string.format("alpha=%s shown=%s visible=%s enforcerMark=%s",
        okA and safeToString(alpha) or "<err>",
        okS and safeToString(shown) or "<err>",
        okV and safeToString(visible) or "<err>",
        tostring(enforced))
end

function addon.DebugRepColor(sub)
    if sub == "watch" then
        if watchTicker then
            watchTicker:Cancel()
            watchTicker = nil
            lastWatchAlpha = {}
            addon.RepColorTrace("watch", "ticker stopped")
            addon:Print("RepColor watch ticker stopped.")
        else
            watchTicker = C_Timer.NewTicker(0.5, watchTick)
            addon.RepColorTrace("watch", "ticker started (0.5s)")
            addon:Print("RepColor watch ticker started (0.5s).")
        end
        return
    end

    local lines = {}
    local function add(fmt, ...)
        lines[#lines + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    end

    add("ReputationColor Debug — GetTime %.3f", GetTime())
    add("")
    add("Edit Mode guard:")
    add("  IsEditModeActiveOrOpening = %s", safeToString(addon.EditMode and addon.EditMode.IsEditModeActiveOrOpening()))
    add("  _openingEditMode = %s  _exitingEditMode = %s",
        safeToString(addon.EditMode and addon.EditMode._openingEditMode),
        safeToString(addon.EditMode and addon.EditMode._exitingEditMode))
    add("")
    for _, unit in ipairs({ "Target", "Focus" }) do
        add("%s: %s", unit, describeTexture(unit))
        add("  config: %s", describeCfg(unit))
    end
    add("")
    add("Watch ticker: %s", watchTicker and "RUNNING" or "off")
    add("")
    add("Trace ring buffer (oldest first, %d max):", BUFFER_SIZE)

    local count = math.min(writeIndex, BUFFER_SIZE)
    for i = count, 1, -1 do
        local seq = writeIndex - i + 1
        local slot = ((seq - 1) % BUFFER_SIZE) + 1
        local e = buffer[slot]
        if e then
            add("[%10.3f] #%d %-14s %s", e.t, e.seq, e.tag, e.detail or "")
        end
    end
    if count == 0 then
        add("  (empty)")
    end

    addon.DebugShowWindow("Scoot Debug: RepColor", lines)
end

addon:RegisterDebugCommand({
    name = "repcolor", help = "ReputationColor banner lifecycle trace",
    usage = { "repcolor [watch]" },
    handler = function(sub) addon.DebugRepColor(sub) end,
})
