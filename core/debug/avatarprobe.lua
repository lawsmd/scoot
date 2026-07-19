-- avatarprobe.lua - DEV-ONLY barbershop customization probe (proof-of-concept)
--
-- Purpose: capture exactly what C_BarberShop exposes about a character's applied
-- customizations, so we can design the avatar "appearance ingestion" feature.
--
-- Read-only and taint-safe: it only calls C_BarberShop *getters* and reads its own
-- fresh return tables. It never writes to, hooks, or touches any Blizzard barbershop
-- frame, so it cannot taint the barbershop UI.
--
-- Why it polls instead of just reading on an event:
--   The customization list is only valid while the barbershop's "character
--   component" is set up (roughly, while the frame is open). Blizzard populates it in
--   the frame's OnShow -- not via a global event we can hook -- and on Accept it fires
--   BARBER_SHOP_APPEARANCE_APPLIED and *immediately* tears the component down
--   (Cancel -> HideUIPanel). So any deferred read tied to Apply/Close returns nil.
--   Instead we poll GetAvailableCustomizations() while the shop is open: capture the
--   INITIAL (saved) state on the first success, and re-capture whenever the selection
--   signature changes -- so we also grab the post-change state before teardown.
--
-- Flow for the tester:
--   /scoot debug avatar          -> arm the probe (start listening)
--   (walk to a barber NPC, open the barbershop; change things and Accept if you like)
--   Close the barbershop         -> a copyable report window pops up automatically
--   /scoot debug avatar dump     -> re-open the last report window any time
--   /scoot debug avatar disarm   -> stop listening

local addonName, addon = ...

local probe = {}
addon.AvatarProbe = probe

local eventFrame
local pollTicker
local initialText   -- full report of the saved appearance when the shop opened
local finalText     -- full report of the latest selections while open
local lastSig       -- selection signature of the last full capture (change detection)
local appliedSeen   -- did BARBER_SHOP_APPEARANCE_APPLIED fire this visit?
local lastReport    -- concatenated text shown in the window

local POLL_INTERVAL = 0.15
local POLL_MAX_TICKS = 2400  -- backstop (~6 min) in case BARBER_SHOP_CLOSE never fires

-- ---------------------------------------------------------------------------
-- secret-safe scalar rendering
-- ---------------------------------------------------------------------------
local function isSecret(v)
    if issecretvalue then
        local ok, res = pcall(issecretvalue, v)
        if ok then return res end
    end
    return false
end

local function q(s)
    return '"' .. tostring(s):gsub('"', '\\"') .. '"'
end

local function scalar(v)
    if isSecret(v) then return "<secret>" end
    local t = type(v)
    if t == "nil" then return "nil" end
    if t == "boolean" then return tostring(v) end
    if t == "number" then
        if math.floor(v) == v then return tostring(v) end
        return string.format("%.4g", v)
    end
    if t == "string" then return q(v) end
    if t == "function" then return "<function>" end
    return "<" .. t .. ">"
end

-- Recognise a colorRGB / ColorMixin (own fields r,g,b as numbers).
local function asColor(v)
    if type(v) ~= "table" then return nil end
    local r, g, b = rawget(v, "r"), rawget(v, "g"), rawget(v, "b")
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
        local R = math.floor(r * 255 + 0.5)
        local G = math.floor(g * 255 + 0.5)
        local B = math.floor(b * 255 + 0.5)
        local s = string.format("RGB(%.3f, %.3f, %.3f) = #%02X%02X%02X  bytes(%d,%d,%d)",
            r, g, b, R, G, B, R, G, B)
        local a = rawget(v, "a")
        if type(a) == "number" then s = s .. string.format(" a=%.3f", a) end
        return s
    end
    return nil
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, res = pcall(fn, ...)
    if ok then return res end
    return nil
end

-- ---------------------------------------------------------------------------
-- generic recursive dump (verbatim view of whatever the API returns)
-- ---------------------------------------------------------------------------
local MAX_DEPTH = 12

local function serialize(v, indent, out, depth)
    local pad = string.rep("  ", indent)
    if depth > MAX_DEPTH then
        out[#out + 1] = pad .. "<max depth>"
        return
    end

    local n = #v
    local function emit(keyStr, item)
        local col = asColor(item)
        if col then
            out[#out + 1] = string.format("%s%s = %s", pad, keyStr, col)
        elseif type(item) == "table" then
            out[#out + 1] = string.format("%s%s = {", pad, keyStr)
            serialize(item, indent + 1, out, depth + 1)
            out[#out + 1] = pad .. "}"
        else
            out[#out + 1] = string.format("%s%s = %s", pad, keyStr, scalar(item))
        end
    end

    -- array part first
    for i = 1, n do
        emit(string.format("[%d]", i), v[i])
    end

    -- remaining (hash) keys, sorted for stable output
    local keys = {}
    for k in pairs(v) do
        if not (type(k) == "number" and k >= 1 and k <= n and math.floor(k) == k) then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        emit(tostring(k), v[k])
    end
end

-- ---------------------------------------------------------------------------
-- structured summary keyed to the known schema
-- (CharCustomizationCategory -> CharCustomizationOption -> CharCustomizationChoice)
-- ---------------------------------------------------------------------------
local function formatStructured(categories, out)
    out[#out + 1] = "===== STRUCTURED SUMMARY ====="
    for ci = 1, #categories do
        local cat = categories[ci]
        out[#out + 1] = string.format(
            "CATEGORY [%d] %s  (id=%s, orderIndex=%s, subcategory=%s, chrModelID=%s)",
            ci, tostring(cat.name), scalar(cat.id), scalar(cat.orderIndex),
            scalar(cat.subcategory), scalar(cat.chrModelID))
        local options = cat.options
        if type(options) == "table" then
            for oi = 1, #options do
                local opt = options[oi]
                local curIdx = opt.currentChoiceIndex
                local curName = "?"
                if type(curIdx) == "number" and type(opt.choices) == "table"
                    and opt.choices[curIdx] then
                    curName = tostring(opt.choices[curIdx].name)
                end
                out[#out + 1] = string.format(
                    "    OPTION %s  (id=%s, type=%s)  currentChoiceIndex=%s -> %s",
                    tostring(opt.name), scalar(opt.id), scalar(opt.optionType),
                    scalar(curIdx), curName)
                if type(opt.choices) == "table" then
                    for chi = 1, #opt.choices do
                        local ch = opt.choices[chi]
                        local sw = ""
                        local c1 = asColor(ch.swatchColor1)
                        local c2 = asColor(ch.swatchColor2)
                        if c1 then sw = "  swatch1=" .. c1 end
                        if c2 then sw = sw .. "  swatch2=" .. c2 end
                        local marker = (chi == curIdx) and "  *CURRENT*" or ""
                        out[#out + 1] = string.format("        [%d] %s (id=%s)%s%s",
                            chi, tostring(ch.name), scalar(ch.id), sw, marker)
                    end
                end
            end
        end
    end
end

-- Cheap fingerprint of all option->currentChoiceIndex pairs, for change detection.
local function signature(categories)
    local t = {}
    for ci = 1, #categories do
        local options = categories[ci].options
        if type(options) == "table" then
            for oi = 1, #options do
                local opt = options[oi]
                t[#t + 1] = tostring(opt.id) .. ":" .. tostring(opt.currentChoiceIndex)
            end
        end
    end
    return table.concat(t, ";")
end

-- Build the full copyable report text for a captured customization table.
local function buildReport(label, categories)
    local out = {}
    out[#out + 1] = "########################################"
    out[#out + 1] = "# Scoot Avatar Barbershop Probe"
    out[#out + 1] = "# " .. label
    out[#out + 1] = "########################################"

    local rn, rf, rid = UnitRace("player")
    out[#out + 1] = string.format("player=%s  race=%s (file=%s, id=%s)  UnitSex=%s",
        tostring(UnitName("player")), tostring(rn), tostring(rf),
        tostring(rid), tostring(UnitSex("player")))
    out[#out + 1] = string.format("HasAlteredForm=%s  IsViewingAlteredForm=%s",
        scalar(safeCall(C_BarberShop.HasAlteredForm)),
        scalar(safeCall(C_BarberShop.IsViewingAlteredForm)))

    local charData = safeCall(C_BarberShop.GetCurrentCharacterData)
    out[#out + 1] = ""
    out[#out + 1] = "===== GetCurrentCharacterData() ====="
    if type(charData) == "table" then
        out[#out + 1] = "{"
        serialize(charData, 1, out, 0)
        out[#out + 1] = "}"
    else
        out[#out + 1] = "  " .. scalar(charData)
    end

    out[#out + 1] = ""
    formatStructured(categories, out)
    out[#out + 1] = ""
    out[#out + 1] = "===== RAW GetAvailableCustomizations() ====="
    out[#out + 1] = "categories = {"
    serialize(categories, 1, out, 0)
    out[#out + 1] = "}"

    return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- polling while the shop is open
-- ---------------------------------------------------------------------------
local function captureFromLiveData()
    local cats = safeCall(C_BarberShop.GetAvailableCustomizations)
    if type(cats) ~= "table" or #cats == 0 then
        return false
    end
    local sig = signature(cats)
    if sig == lastSig then
        return true  -- data present, unchanged; nothing new to serialize
    end
    lastSig = sig

    if not initialText then
        initialText = buildReport("INITIAL - saved appearance when the barbershop opened", cats)
        addon:Print("|cff33ff99Avatar probe:|r captured your current appearance ("
            .. #cats .. " categories). Close the barbershop to view the report.")
    else
        finalText = buildReport("LATEST - current selections while open (reflects your changes)", cats)
    end
    return true
end

local function stopPolling()
    if pollTicker then
        pollTicker:Cancel()
        pollTicker = nil
    end
end

local function startPolling()
    if pollTicker then return end
    pollTicker = C_Timer.NewTicker(POLL_INTERVAL, function()
        captureFromLiveData()
    end, POLL_MAX_TICKS)
end

local function beginVisit()
    initialText = nil
    finalText = nil
    lastSig = nil
    appliedSeen = false
    startPolling()
end

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------
local function onEvent(_, event)
    if event == "BARBER_SHOP_OPEN" then
        beginVisit()
    elseif event == "BARBER_SHOP_FORCE_CUSTOMIZATIONS_UPDATE" then
        -- Defensive: if OPEN was missed, make sure we're polling.
        if not pollTicker then beginVisit() end
    elseif event == "BARBER_SHOP_APPEARANCE_APPLIED" then
        appliedSeen = true
        -- Best-effort synchronous grab before Blizzard tears the component down;
        -- falls back to the last polled capture if the component is already gone.
        captureFromLiveData()
    elseif event == "BARBER_SHOP_CLOSE" then
        stopPolling()
        C_Timer.After(0, function() probe.ShowReport() end)
    end
end

-- ---------------------------------------------------------------------------
-- public API (driven by /scoot debug avatar ...)
-- ---------------------------------------------------------------------------
function probe.Arm()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", onEvent)
    end
    eventFrame:RegisterEvent("BARBER_SHOP_OPEN")
    eventFrame:RegisterEvent("BARBER_SHOP_FORCE_CUSTOMIZATIONS_UPDATE")
    eventFrame:RegisterEvent("BARBER_SHOP_APPEARANCE_APPLIED")
    eventFrame:RegisterEvent("BARBER_SHOP_CLOSE")
    addon:Print("|cff33ff99Avatar probe armed.|r Visit a barber NPC and open the barbershop.")
    addon:Print("  It reads your appearance while the shop is open (and any changes you make).")
    addon:Print("  Close the barbershop to pop the copyable report (or '/scoot debug avatar dump').")
end

function probe.Disarm()
    stopPolling()
    if eventFrame then eventFrame:UnregisterAllEvents() end
    addon:Print("Avatar probe disarmed.")
end

function probe.ShowReport()
    local parts = {}
    if initialText then parts[#parts + 1] = initialText end
    if finalText and finalText ~= initialText then parts[#parts + 1] = finalText end

    if #parts == 0 then
        addon:Print("Avatar probe: no data captured. Arm, then open a barbershop and let it finish loading.")
        return
    end

    if appliedSeen then
        table.insert(parts, 1,
            "NOTE: you clicked Accept this visit, so LATEST reflects what was saved.\n")
    end

    lastReport = table.concat(parts, "\n\n\n")
    if addon.DebugShowWindow then
        addon.DebugShowWindow("Avatar Barbershop Probe", lastReport)
    else
        addon:Print("Avatar probe: copyable debug window unavailable.")
    end
end
