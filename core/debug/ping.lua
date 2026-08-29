-- ping.lua — /scoot debug ping
--
-- Answers one question: "is this Scoot frame ready to receive a 12.1 ping?"
--
-- It cannot answer "did the ping land". C_PingSecure is SecureOnly, so nothing
-- in the addon can call GetTargetPingReceiver, send a ping, or read back what
-- the engine decided. What it CAN do is check every half of the contract Scoot
-- controls, which is where a failure will be:
--
--   1. The frame carries the "ping-receiver" attribute, so the C-side hit test
--      can find it, and a "unit" attribute for the unit-frame mixin to read.
--   2. The three mixin methods resolve, and GetTargetInfo returns something the
--      secure gather can securecopy. A SECRET guid in there is the known hard
--      failure: it errors at the secure boundary and wedges the ping listener.
--   3. No .unit FIELD, which would shadow the attribute with a tainted read.
--   4. The receiver's rect actually contains the cursor, and the click overlay's
--      reserve around it does not (the pass-through band is deliberate).
--
-- Usage: /scoot debug ping        -- 5s to park the cursor, then reports
--        /scoot debug ping 10     -- longer arming window
local addonName, addon = ...

local DEFAULT_DELAY = 5

--------------------------------------------------------------------------------
-- Secret-safe accessors (type() -> issecretvalue() -> use; never compare raw)
--------------------------------------------------------------------------------

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

-- Classifies a value for the report without ever comparing or concatenating a
-- secret. The whole point of the tool is to spot a secret before it reaches the
-- securecopy, so it must survive meeting one.
local function describe(v)
    local t = type(v)
    if t == "nil" then return "nil" end
    if issecretvalue and issecretvalue(v) then return "SECRET " .. t end
    if t == "string" or t == "number" or t == "boolean" then return tostring(v) end
    return t
end

local function frameName(frame)
    local n = safe(frame.GetName, frame)
    if type(n) == "string" and n ~= "" then return n end
    return "<unnamed>"
end

local function rectOf(frame)
    local l = safe(frame.GetLeft, frame)
    local r = safe(frame.GetRight, frame)
    local b = safe(frame.GetBottom, frame)
    local t = safe(frame.GetTop, frame)
    if type(l) ~= "number" or type(r) ~= "number"
        or type(b) ~= "number" or type(t) ~= "number" then
        return nil
    end
    return l, r, b, t
end

-- Cursor coordinates come back in screen space; a frame's rect is in UI space.
local function containsCursor(frame, ux, uy)
    local l, r, b, t = rectOf(frame)
    if not l then return false end
    return ux >= l and ux <= r and uy >= b and uy <= t
end

--------------------------------------------------------------------------------
-- Per-receiver report
--------------------------------------------------------------------------------

local function reportReceiver(out, label, frame, ux, uy)
    if not frame then
        table.insert(out, string.format("  %s: NO FRAME", label))
        return
    end

    local attr = safe(frame.GetAttribute, frame, "ping-receiver")
    local unitAttr = safe(frame.GetAttribute, frame, "unit")
    local shown = safe(frame.IsShown, frame)
    local methods = (type(frame.GetIsPingable) == "function")
        and (type(frame.GetAllowRadialWheel) == "function")
        and (type(frame.GetTargetInfo) == "function")

    table.insert(out, string.format("  %s  [%s]", label, frameName(frame)))
    table.insert(out, string.format("    shown=%s  ping-receiver=%s  unit-attr=%s  methods=%s",
        tostring(shown), describe(attr), describe(unitAttr), tostring(methods)))

    -- A .unit FIELD shadows the attribute inside Blizzard's mixin and is the
    -- documented way to break pings under identity restrictions.
    local okField, unitField = pcall(rawget, frame, "unit")
    if okField and unitField ~= nil then
        table.insert(out, "    RULE VIOLATION: carries a .unit FIELD (must use the attribute only)")
    end

    local l, r, b, t = rectOf(frame)
    if l then
        table.insert(out, string.format("    rect=%.0f,%.0f  %.0fx%.0f  cursorInside=%s",
            l, b, r - l, t - b, tostring(containsCursor(frame, ux, uy))))
    else
        table.insert(out, "    rect=NONE (zero-size or unanchored: the engine cannot hit it)")
    end

    if not methods then return end

    local pingable = safe(frame.GetIsPingable, frame)
    local wheel = safe(frame.GetAllowRadialWheel, frame)
    table.insert(out, string.format("    GetIsPingable=%s  GetAllowRadialWheel=%s",
        describe(pingable), describe(wheel)))
    if pingable == false then
        table.insert(out, "    NOTE: an unpingable receiver BLOCKS the ping, it does not pass it through")
    end

    local info = safe(frame.GetTargetInfo, frame)
    if type(info) ~= "table" then
        table.insert(out, "    GetTargetInfo: " .. describe(info))
        return
    end
    local parts = {}
    for _, key in ipairs({ "guid", "spellID", "itemID", "spellCategoryID", "isPlayerResource" }) do
        if info[key] ~= nil then
            table.insert(parts, key .. "=" .. describe(info[key]))
        end
    end
    if #parts == 0 then
        table.insert(out, "    GetTargetInfo: {} (no target: the ping falls back to a world ping)")
    else
        table.insert(out, "    GetTargetInfo: " .. table.concat(parts, "  "))
    end
    if info.guid ~= nil and issecretvalue and issecretvalue(info.guid) then
        table.insert(out, "    HAZARD: secret guid reaches securecopy; expect a hard error and a wedged listener")
    end
end

--------------------------------------------------------------------------------
-- Report
--------------------------------------------------------------------------------

local function buildReport(ux, uy)
    local out = {}
    table.insert(out, "=== Scoot ping receivers ===")
    table.insert(out, string.format("cursor (UI space): %.0f, %.0f", ux, uy))
    table.insert(out, "")

    table.insert(out, "Client:")
    table.insert(out, string.format("  PingableType_UnitFrameMixin=%s  PingListenerFrame=%s",
        tostring(PingableType_UnitFrameMixin ~= nil), tostring(_G.PingListenerFrame ~= nil)))
    -- Nothing here can land if the player switched pings off, is solo, or set
    -- the ping target to Environment only.
    for _, cvar in ipairs({ "enablePings", "pingTarget", "showPingsInChat", "pingMode" }) do
        local v = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(cvar)
        table.insert(out, string.format("  %s=%s", cvar, tostring(v)))
    end
    table.insert(out, string.format("  inGroup=%s   (pings need a group)",
        tostring(IsInGroup and IsInGroup() or false)))
    table.insert(out, "")

    table.insert(out, "Unit Frames Z:")
    local UFZ = addon.UnitFramesZ
    local any = false
    if UFZ and UFZ._instances then
        for frameKey, inst in pairs(UFZ._instances) do
            any = true
            reportReceiver(out, frameKey, inst.pingReceiver, ux, uy)
            -- The player's radial-wheel carve-out. Everything outside it sends
            -- the resource callout, which is PlayerFrame's own rule inverted
            -- around the portrait.
            local nb = inst.pingNameBox
            if nb then
                local over = safe(nb.IsMouseOver, nb)
                local nl, nr, nbm, nt = rectOf(nb)
                table.insert(out, string.format(
                    "    nameBox rect=%s  IsMouseOver=%s  -> %s",
                    nl and string.format("%.0f,%.0f %.0fx%.0f", nl, nbm, nr - nl, nt - nbm) or "NONE",
                    describe(over),
                    (over == true) and "name row: plain self ping + wheel"
                        or "resource callout, no wheel"))
                if issecretvalue and issecretvalue(over) then
                    table.insert(out, "    HAZARD: the name proxy answered SECRET; it must be plain")
                end
            end
            -- The reserve is the whole point of a content-sized receiver: inside
            -- the envelope, outside the receiver, a ping should reach the world.
            if inst.frame and inst.pingReceiver then
                local inEnv = containsCursor(inst.frame, ux, uy)
                local inRec = containsCursor(inst.pingReceiver, ux, uy)
                if inEnv and not inRec then
                    table.insert(out, "    cursor is in the click-only reserve (ping passes through by design)")
                end
            end
        end
    end
    if not any then table.insert(out, "  (no instances built)") end
    table.insert(out, "")

    table.insert(out, "CDM Custom Groups:")
    local CG = addon.CustomGroups
    any = false
    if CG and CG._activeIcons then
        for groupIndex, icons in ipairs(CG._activeIcons) do
            for i, icon in ipairs(icons) do
                any = true
                reportReceiver(out, string.format("group %d icon %d", groupIndex, i), icon, ux, uy)
            end
        end
    end
    if not any then table.insert(out, "  (no active icons)") end

    return table.concat(out, "\n")
end

--------------------------------------------------------------------------------
-- Entry point
--------------------------------------------------------------------------------

local armed = false

function addon.DebugPing(arg)
    if armed then
        addon:Print("Ping probe already armed.")
        return
    end
    local delay = tonumber(arg) or DEFAULT_DELAY
    if delay < 1 then delay = 1 elseif delay > 60 then delay = 60 end

    armed = true
    addon:Print(string.format(
        "Ping probe armed: park the cursor over a Scoot frame. Reporting in %d seconds.", delay))

    C_Timer.After(delay, function()
        armed = false
        local cx, cy = GetCursorPosition()
        if type(cx) ~= "number" or type(cy) ~= "number" then
            addon:Print("Could not read the cursor position.")
            return
        end
        -- Rects are in UI space; the raw cursor is in screen space.
        local scale = UIParent:GetEffectiveScale()
        if type(scale) ~= "number" or scale == 0 then scale = 1 end

        local text = buildReport(cx / scale, cy / scale)
        if addon.DebugShowWindow then
            addon.DebugShowWindow("Ping Receivers", text)
        else
            addon:Print("DebugShowWindow not available.")
        end
    end)
end
