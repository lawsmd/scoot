-- fontpair.lua -- Diagnostic dump of Deep Shadow pairs: where the black copy
-- actually landed relative to the string it mirrors, and a combat capture for
-- the damage meter's name pairs, whose fault shows only mid-fight.
--
-- Draw order is the whole job of core/fontpair.lua and it is not readable from
-- a screenshot once the copy is fat enough to bury the original, so read it
-- back from the engine instead. "Copy layer" must sort BELOW "Real layer".
--
-- Usage: /scoot debug fontpair            every live pair
--        /scoot debug fontpair capture    arm: the next fight is recorded and
--                                         reported the moment it ends
--        /scoot debug fontpair probe      reopen the last capture's frozen strings
local addonName, addon = ...

local LAYER_RANK = {
    BACKGROUND = 1,
    BORDER = 2,
    ARTWORK = 3,
    OVERLAY = 4,
    HIGHLIGHT = 5,
}

local function isSecret(v)
    return type(issecretvalue) == "function" and issecretvalue(v)
end

local function plainNumber(v)
    return type(v) == "number" and not isSecret(v)
end

local function drawLayerOf(region)
    if not region or not region.GetDrawLayer then return "?", "?" end
    local ok, layer, sublevel = pcall(region.GetDrawLayer, region)
    if not ok then return "<restricted>", "?" end
    return tostring(layer), tostring(sublevel)
end

-- IsShown and GetAlpha return secret values on a string an engine binding has
-- claimed, and tostring on a secret raises, so name the secret instead.
local function boolOf(region, method)
    if not region or not region[method] then return "?" end
    local ok, value = pcall(region[method], region)
    if not ok then return "<restricted>" end
    if isSecret(value) then return "secret" end
    return tostring(value)
end

-- The taper the copy is running at (core/fontpair.lua copyAlphaFor). A copy
-- alpha still at 0.80 while the drawn alpha is below 1 means a fade path is not
-- calling RefreshInheritedAlpha, unless the text is white, where 0.80 is right
-- at every alpha.
local function taperOf(fs, companion)
    local lum, drawn, copyAlpha = "?", "?", "?"
    if fs and fs.GetTextColor then
        local ok, r, g, b = pcall(fs.GetTextColor, fs)
        if ok and plainNumber(r) and plainNumber(g) and plainNumber(b) then
            lum = string.format("%.2f", 0.2126 * r + 0.7152 * g + 0.0722 * b)
        end
    end
    local okP, parent = pcall(fs.GetParent, fs)
    if okP and parent and parent.GetEffectiveAlpha then
        local okA, a = pcall(parent.GetEffectiveAlpha, parent)
        if okA and plainNumber(a) then drawn = string.format("%.2f", a) end
    end
    if companion and companion.GetTextColor then
        local ok, _, _, _, a = pcall(companion.GetTextColor, companion)
        if ok and plainNumber(a) then copyAlpha = string.format("%.2f", a) end
    end
    return lum, drawn, copyAlpha
end

-- Every damage meter row, name clip and column cell is an anonymous frame, so
-- the immediate parent prints as a table address and no two pairs can be told
-- apart. Walk up to the first named ancestor and say how many hops that took.
local function parentNameOf(region)
    if not region or not region.GetParent then return "?" end
    local ok, parent = pcall(region.GetParent, region)
    if not ok or not parent then return "?" end
    local node, hops = parent, 0
    while node and hops < 6 do
        local okName, name = pcall(node.GetName, node)
        if okName and name then
            if hops == 0 then return name end
            return string.format("%s (+%d)", name, hops)
        end
        local okUp, up = pcall(node.GetParent, node)
        if not okUp then break end
        node = up
        hops = hops + 1
    end
    return tostring(parent):gsub("table: ", "")
end

-- The text is often secret, so report only whether it reads, never the value.
-- Pass strip for the real string: the copy is fed through StripEscapes, so a
-- name carrying a color escape is shorter in the copy by construction and the
-- two lengths would never line up.
local function textStateOf(region, strip)
    if not region or not region.GetText then return "?" end
    local ok, text = pcall(region.GetText, region)
    if not ok then return "<throws>" end
    if text == nil then return "nil" end
    if isSecret(text) then return "secret" end
    if text == "" then return "empty" end
    local s = tostring(text)
    if strip and addon.FontPair and addon.FontPair.StripEscapes then
        local okStrip, stripped = pcall(addon.FontPair.StripEscapes, s)
        if okStrip then s = stripped end
    end
    if s == "" then return "empty" end
    return string.format("plain (%d chars)", #s)
end

-- The real string and its copy must hold the same text. The copy is box-anchored
-- to the real string's rect, so one left holding an older value is drawn clipped
-- or ellipsized inside that rect: a smear rather than a shadow. Two secrets
-- cannot be compared, so that pair reports as unverifiable instead of OK.
local BLANK_STATE = { ["nil"] = true, ["empty"] = true }

local function syncOf(realState, copyState)
    if realState == "secret" and copyState == "secret" then
        return "secret on both, contents not comparable", false
    end
    if BLANK_STATE[realState] and BLANK_STATE[copyState] then
        return "OK, both blank", false
    end
    if realState == copyState then return "OK", false end
    return string.format("DESYNC -- real %s, copy %s", realState, copyState), true
end

local function DebugFontPair()
    local registry = addon.FontPair and addon.FontPair.registry
    local lines = {}

    table.insert(lines, "Deep Shadow pairs -- core/fontpair.lua")
    table.insert(lines, string.rep("=", 64))
    table.insert(lines, "The copy must sort BELOW the real string. Layer beats sublevel:")
    table.insert(lines, "BACKGROUND < BORDER < ARTWORK < OVERLAY < HIGHLIGHT.")
    table.insert(lines, "Copy alpha tapers with text luminance and drawn alpha: dark text")
    table.insert(lines, "at reduced opacity gets a lighter copy, white text never tapers.")
    table.insert(lines, "Sync compares the two text states. A DESYNC means the copy kept an")
    table.insert(lines, "older value, which draws as a smear inside the real string's box.")
    table.insert(lines, "")

    if not registry then
        table.insert(lines, "No registry -- core/fontpair.lua did not load.")
        addon.DebugShowWindow("Deep Shadow pairs", lines)
        return
    end

    local count, wrong, desynced = 0, 0, 0
    for fs, companion in pairs(registry) do
        count = count + 1
        local realLayer, realSub = drawLayerOf(fs)
        local copyLayer, copySub = drawLayerOf(companion)
        local realText, copyText = textStateOf(fs, true), textStateOf(companion)

        local verdict
        local realRank, copyRank = LAYER_RANK[realLayer], LAYER_RANK[copyLayer]
        if not realRank or not copyRank then
            verdict = "UNKNOWN (layer did not read)"
        elseif copyRank < realRank then
            verdict = "OK -- copy is behind"
        elseif copyRank > realRank then
            verdict = "WRONG -- copy is in front"
            wrong = wrong + 1
        else
            verdict = "SAME LAYER -- sublevel decides, and it does not sort two strings"
            wrong = wrong + 1
        end

        -- An inactive pair has been blanked on purpose by FontPair.Hide, so its
        -- copy is empty while the real string still reads. Not a desync.
        local active = fs.__scootPairActive and true or false
        local sync, isDesync = syncOf(realText, copyText)
        if not active then
            sync = "n/a, pair inactive"
        elseif isDesync then
            desynced = desynced + 1
        end

        table.insert(lines, string.format("[%d] parent: %s", count, parentNameOf(fs)))
        table.insert(lines, string.format("    Real layer: %s %s   shown=%s alpha=%s text=%s",
            realLayer, realSub, boolOf(fs, "IsShown"), boolOf(fs, "GetAlpha"), realText))
        table.insert(lines, string.format("    Copy layer: %s %s   shown=%s alpha=%s text=%s",
            copyLayer, copySub, boolOf(companion, "IsShown"), boolOf(companion, "GetAlpha"),
            copyText))
        local lum, drawn, copyAlpha = taperOf(fs, companion)
        table.insert(lines, string.format("    Taper: text luminance %s   drawn alpha %s   copy alpha %s",
            lum, drawn, copyAlpha))
        table.insert(lines, string.format("    Sync: %s", sync))
        table.insert(lines, string.format("    Mirrors: %d   secret writes: %d   blanks: %d",
            fs.__scootPairMirrors or 0, fs.__scootPairSecretWrites or 0, fs.__scootPairBlanks or 0))
        table.insert(lines, string.format("    Active: %s   %s",
            tostring(active), verdict))
        table.insert(lines, "")
    end

    if count == 0 then
        table.insert(lines, "No pairs built. Nothing is set to a Deep Shadow style,")
        table.insert(lines, "or the strings using one have not been styled yet.")
    else
        table.insert(lines, string.rep("-", 64))
        table.insert(lines, string.format("%d pair(s), %d misordered, %d desynced.",
            count, wrong, desynced))
    end

    addon.DebugShowWindow("Deep Shadow pairs", lines)
end

--------------------------------------------------------------------------------
-- Combat capture (/scoot debug fontpair capture)
--
-- The damage meter's Deep Shadow names go wrong only in combat and come back at
-- the regen refresh (some rows light with a thin outline, others heavy, at
-- full window opacity), so the state has to be read while the fight is on and
-- kept until someone can look. Two post-hooks on the meter's
-- own table do the reading: _PopulateBarRow hands over each row with the name
-- it was given, _RefreshBarRows marks the end of a pass. PLAYER_REGEN_ENABLED
-- closes the capture, reads the same rows again after the meter's own regen
-- refresh, and opens two windows: the report, and a probe frame whose strings
-- were fed the captured names during the fight. A FontString keeps rendering
-- a secret string after combat, so the probe freezes the look the meter rows
-- lose at regen. Three columns per row split the fault: the pair fed the
-- captured name (the meter's own recipe), the base style alone fed the same
-- name (copy or real string), and the pair fed a plain literal (the secret or
-- the row).
--------------------------------------------------------------------------------

local OWNER = "FontPairCapture"
local MAX_CAPTURED = 12
local MAX_PROBE_SLOTS = 8
local PLAIN_LITERAL = "Playername"

local capture = {
    armed = false,
    hooked = false,
    rows = {},      -- [row frame] = record
    order = {},     -- row frames, first seen first
    refreshes = 0,  -- combat passes seen across every window
    probeUsed = 0,
    startedAt = 0,
}
local probe -- the probe frame, built on first use

-- tostring of anything: "secret" for a secret, "<throws>" when even that fails.
local function str(v)
    if v == nil then return "nil" end
    if isSecret(v) then return "secret" end
    local ok, s = pcall(tostring, v)
    if not ok then return "<throws>" end
    return s
end

local function num(v, fmt)
    if plainNumber(v) then return string.format(fmt or "%.2f", v) end
    return str(v)
end

local function call(region, method, ...)
    local fn = region and region[method]
    if not fn then return false end
    return pcall(fn, region, ...)
end

-- A getter annotated SecretReturnsForAspect = ObjectSecrets returns a secret
-- when the object holds any secret aspect, so a secret here is itself the
-- answer: IsAnchoringSecret reports the object's own secrets, not its anchors.
local function aspectOf(region, method)
    local ok, v = call(region, method)
    if not ok then return "<throws>" end
    if isSecret(v) then return "secret(yes)" end
    return tostring(v)
end

local function fontOf(region)
    local ok, face, size, flags = call(region, "GetFont")
    if not ok then return "<throws>" end
    local base = str(face)
    if base ~= "secret" and base ~= "nil" then base = base:match("[^\\/]+$") or base end
    return string.format("%s %s %s", base, num(size, "%.1f"), str(flags))
end

local function colorOf(region)
    local ok, r, g, b, a = call(region, "GetTextColor")
    if not ok then return "<throws>" end
    return string.format("%s,%s,%s,%s", num(r), num(g), num(b), num(a))
end

local function rectOf(region)
    local ok, l, b, w, h = call(region, "GetRect")
    if not ok then return "<throws>" end
    return string.format("l=%s b=%s w=%s h=%s",
        num(l, "%.1f"), num(b, "%.1f"), num(w, "%.1f"), num(h, "%.1f"))
end

local function stringSizeOf(region)
    local okW, w = call(region, "GetStringWidth")
    local okH, h = call(region, "GetStringHeight")
    return string.format("%s x %s",
        okW and num(w, "%.1f") or "<throws>", okH and num(h, "%.1f") or "<throws>")
end

local function parentAlphaOf(region)
    local ok, parent = call(region, "GetParent")
    if not ok or not parent then return "?" end
    local okA, a = call(parent, "GetEffectiveAlpha")
    if not okA then return "<throws>" end
    return num(a)
end

-- One string's state on one line.
local function describe(region, strip)
    if not region then return "(none)" end
    local layer, sub = drawLayerOf(region)
    return string.format(
        "text=%s  font=%s  layer=%s %s  color=%s  alpha=%s  shown=%s  aspects=%s  anchoring=%s  rect=%s  string=%s",
        textStateOf(region, strip), fontOf(region), layer, sub, colorOf(region),
        boolOf(region, "GetAlpha"), boolOf(region, "IsShown"),
        aspectOf(region, "HasAnySecretAspect"), aspectOf(region, "IsAnchoringSecret"),
        rectOf(region), stringSizeOf(region))
end

local function snapshotPair(fs)
    if not fs then return nil end
    return {
        real = describe(fs, true),
        copy = describe(fs.__scootPair, false),
        parentAlpha = parentAlphaOf(fs),
        active = fs.__scootPairActive and true or false,
        mirrors = fs.__scootPairMirrors or 0,
        secretWrites = fs.__scootPairSecretWrites or 0,
        blanks = fs.__scootPairBlanks or 0,
    }
end

local function rowLabel(row)
    local DMY = addon.DamageMetersY
    if not (DMY and DMY._windows) then return "row ?" end
    for wi = 1, (DMY.MAX_WINDOWS or 0) do
        local win = DMY._windows[wi]
        if win then
            if win.pinnedRow == row then return string.format("window %d pinned", wi) end
            for r = 1, (DMY.MAX_POOL or 0) do
                if win.barRows and win.barRows[r] == row then
                    return string.format("window %d row %d", wi, r)
                end
            end
        end
    end
    return "row ?"
end

local function recordFor(row)
    local rec = capture.rows[row]
    if rec then return rec end
    if #capture.order >= MAX_CAPTURED then return nil end
    rec = {
        row = row,
        index = #capture.order + 1,
        label = rowLabel(row),
        windowIndex = row._windowIndex,
        populates = 0,
        combatRefreshes = 0,
        missed = 0,
    }
    capture.rows[row] = rec
    capture.order[#capture.order + 1] = row
    return rec
end

-- Font the meter's names run on, straight from its settings.
local function meterNameFont()
    local DMY = addon.DamageMetersY
    local cfg = DMY and DMY._comp and addon:ResolveComponentSubTable(DMY._comp, "textNames")
    return addon.ResolveTextFont(cfg or {}, { longKeys = true, size = 12 })
end

local PROBE_COLS = { B = 160, C = 340, D = 520 }
local PROBE_ROW_H = 30
local PROBE_TOP = 62

local function buildProbe()
    local f = CreateFrame("Frame", "ScootFontPairProbe", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(700, PROBE_TOP + MAX_PROBE_SLOTS * PROBE_ROW_H + 12)
    f:SetPoint("TOP", UIParent, "TOP", 0, -60)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("LEFT", f.TitleBg, "LEFT", 6, 0)
    f.title:SetText("Deep Shadow capture")

    f.legend = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.legend:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -30)
    f.legend:SetJustifyH("LEFT")
    f.legend:SetText("B: the pair, fed the captured name (the meter's recipe).   "
        .. "C: the base style alone, same name.   D: the pair, fed a plain literal.")

    f.slots = {}
    for i = 1, MAX_PROBE_SLOTS do
        local y = -(PROBE_TOP + (i - 1) * PROBE_ROW_H)
        local slot = {}
        slot.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        slot.label:SetPoint("TOPLEFT", f, "TOPLEFT", 12, y - 6)
        slot.label:SetJustifyH("LEFT")
        slot.label:SetTextColor(0.7, 0.7, 0.7, 1)
        for key, x in pairs(PROBE_COLS) do
            local fs = f:CreateFontString(nil, "OVERLAY")
            fs:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            slot[key] = fs
        end
        f.slots[i] = slot
    end
    return f
end

-- The meter's own order: style at styling time, then SetText, then SetTextColor
-- on every refresh (damagemetersY/layout.lua _PopulateBarRow).
local function fillProbeSlot(rec, player)
    local slotIndex = capture.probeUsed + 1
    if slotIndex > MAX_PROBE_SLOTS then return end
    capture.probeUsed = slotIndex
    rec.probeSlot = slotIndex

    probe = probe or buildProbe()
    local slot = probe.slots[slotIndex]
    local face, size, style = meterNameFont()
    local base = addon.FontStyles and addon.FontStyles.Unpaired and addon.FontStyles.Unpaired(style) or style
    local cc = addon.GetClassColorObj and addon.GetClassColorObj(player.classFilename)
    local r, g, b = 1, 1, 1
    if cc then r, g, b = cc.r or 1, cc.g or 1, cc.b or 1 end
    local name = player.name

    slot.label:SetText(string.format("%d  %s  %s", slotIndex, rec.label, rec.nameState))
    addon.ApplyFontStyle(slot.B, face, size, style)
    pcall(slot.B.SetText, slot.B, name)
    slot.B:SetTextColor(r, g, b, 1)
    addon.ApplyFontStyle(slot.C, face, size, base)
    pcall(slot.C.SetText, slot.C, name)
    slot.C:SetTextColor(r, g, b, 1)
    addon.ApplyFontStyle(slot.D, face, size, style)
    slot.D:SetText(PLAIN_LITERAL)
    slot.D:SetTextColor(r, g, b, 1)
    probe.title:SetText(string.format("Deep Shadow capture  --  %s %s %s",
        str(face):match("[^\\/]+$") or str(face), num(size, "%.0f"), str(style)))
end

local function onPopulate(row, player, key, cfg, merged, numColumns, inCombat)
    if not capture.armed or not inCombat or type(player) ~= "table" then return end
    local rec = recordFor(row)
    if not rec then return end
    rec.populates = rec.populates + 1
    rec.class = str(player.classFilename)
    rec.isLocal = str(player.isLocalPlayer)
    -- Short-circuit keeps the nil compare off a secret.
    rec.nameState = isSecret(player.name) and "secret" or (player.name == nil and "nil" or "plain")
    if not rec.probeSlot then fillProbeSlot(rec, player) end
end

-- End of a combat pass over one window: the rows it just wrote are read now,
-- and a name pair whose mirror count did not move since the last pass was a
-- SetText the hook never saw.
local function onRefresh(windowIndex, comp)
    local DMY = addon.DamageMetersY
    if not capture.armed or not DMY or not DMY._inCombat then return end
    capture.refreshes = capture.refreshes + 1
    for _, row in ipairs(capture.order) do
        local rec = capture.rows[row]
        if rec and rec.windowIndex == windowIndex then
            local okShown, shown = pcall(row.IsShown, row)
            if okShown and shown then
                local fs = row.nameText
                local mirrors = fs and fs.__scootPairMirrors or 0
                if rec.lastMirrors ~= nil and mirrors == rec.lastMirrors then
                    rec.missed = rec.missed + 1
                end
                rec.lastMirrors = mirrors
                rec.combatRefreshes = rec.combatRefreshes + 1
                rec.combatAt = GetTime()
                rec.combat = snapshotPair(fs)
                rec.combatValue = snapshotPair(row.valueTexts and row.valueTexts[1])
                rec.combatRank = snapshotPair(row.rankText)
            end
        end
    end
end

local function pairLines(push, label, snap)
    if not snap then
        push("    %s: not captured", label)
        return
    end
    push("    %s real  %s", label, snap.real)
    push("    %s copy  %s", string.rep(" ", #label), snap.copy)
    push("    %s       parent alpha %s   active=%s   mirrors=%d   secret writes=%d   blanks=%d",
        string.rep(" ", #label), snap.parentAlpha, tostring(snap.active),
        snap.mirrors, snap.secretWrites, snap.blanks)
end

local function showReport()
    local DMY = addon.DamageMetersY
    local lines, push = addon.DebugLines("Deep Shadow capture -- the damage meter's name pairs through one fight")
    push(string.rep("=", 64))
    local face, size, style = meterNameFont()
    push("Names font: %s %s %s", str(face):match("[^\\/]+$") or str(face), num(size, "%.0f"), str(style))
    if DMY and DMY._comp and addon.Opacity then
        local opts = { combatMin = 50, inCombat = true }
        local inA = addon.Opacity.Resolve(DMY._comp.db, addon.Opacity.Keys.CombatOnly, opts)
        opts.inCombat = false
        local outA = addon.Opacity.Resolve(DMY._comp.db, addon.Opacity.Keys.CombatOnly, opts)
        push("Window alpha: combat %.2f   out of combat %.2f", inA, outA)
    end
    push("Combat passes seen: %d   rows captured: %d   fight length: %.0fs",
        capture.refreshes, #capture.order, GetTime() - capture.startedAt)
    push("")
    push("Reading it:")
    push("  missed > 0        a combat pass wrote the row and the SetText hook did not run: the copy is stale")
    push("  blanks climbing   the copy's SetText failed and the copy was blanked")
    push("  copy font differs the copy lost its face, size or flags")
    push("  copy color alpha  0.80 is the full copy; lower is the taper (needs parent alpha below 1)")
    push("  aspects/anchoring secret(yes) means the string holds a secret and its rect reads secret")
    push("  'combat' is the last combat pass; 'after' is the same row once the regen refresh ran")
    push("")

    for _, row in ipairs(capture.order) do
        local rec = capture.rows[row]
        push("[%d] %s   class=%s   local=%s   name=%s   probe slot=%s",
            rec.index, rec.label, rec.class or "?", rec.isLocal or "?", rec.nameState or "?",
            rec.probeSlot and tostring(rec.probeSlot) or "none")
        push("    populated %d times, %d combat passes read, missed mirrors %d",
            rec.populates, rec.combatRefreshes, rec.missed)
        push("  combat%s", rec.combatAt and string.format(" (last pass at +%.0fs)", rec.combatAt - capture.startedAt) or "")
        pairLines(push, "name ", rec.combat)
        pairLines(push, "value", rec.combatValue)
        pairLines(push, "rank ", rec.combatRank)
        push("  after (in combat again: %s)", tostring(rec.afterInCombat))
        pairLines(push, "name ", rec.after)
        pairLines(push, "value", rec.afterValue)
        pairLines(push, "rank ", rec.afterRank)
        push("")
    end

    if #capture.order == 0 then
        push("No rows were written in combat. The meter did not refresh, or the window was hidden.")
    end
    push("The probe window holds the captured names; /scoot debug fontpair probe reopens it.")
    addon.DebugShowWindow("Deep Shadow capture", lines)
end

local function finishCapture()
    if not capture.armed then return end
    capture.armed = false
    local DMY = addon.DamageMetersY
    for _, row in ipairs(capture.order) do
        local rec = capture.rows[row]
        rec.after = snapshotPair(row.nameText)
        rec.afterValue = snapshotPair(row.valueTexts and row.valueTexts[1])
        rec.afterRank = snapshotPair(row.rankText)
        rec.afterInCombat = DMY and DMY._inCombat or false
    end
    showReport()
    if probe and capture.probeUsed > 0 then probe:Show() end
end

local function armCapture()
    local DMY = addon.DamageMetersY
    local lines, push = addon.DebugLines("Deep Shadow capture")
    if not (DMY and DMY._PopulateBarRow and DMY._RefreshBarRows) then
        push("The Modern damage meter is not loaded, and the capture reads its rows.")
        addon.DebugShowWindow("Deep Shadow capture", lines)
        return
    end
    if not capture.hooked then
        capture.hooked = true
        hooksecurefunc(DMY, "_PopulateBarRow", onPopulate)
        hooksecurefunc(DMY, "_RefreshBarRows", onRefresh)
        -- The meter's own regen refresh runs synchronously on the same event;
        -- half a second later the rows hold what it wrote.
        addon.Events.On(OWNER, "PLAYER_REGEN_ENABLED", function()
            if capture.armed then C_Timer.After(0.5, finishCapture) end
        end)
    end
    wipe(capture.rows)
    wipe(capture.order)
    capture.refreshes = 0
    capture.probeUsed = 0
    capture.startedAt = GetTime()
    capture.armed = true
    if probe then probe:Hide() end
    push("Armed. Fight with the Modern damage meter on screen.")
    push("The report and the probe window open on their own when combat ends.")
    push("Nothing is recorded until the meter refreshes in combat.")
    addon.DebugShowWindow("Deep Shadow capture", lines)
end

local function showProbe()
    if probe and capture.probeUsed > 0 then
        probe:Show()
        return
    end
    addon.DebugShowWindow("Deep Shadow capture",
        { "No capture yet. Arm one with /scoot debug fontpair capture, then fight." })
end

addon:RegisterDebugCommand({
    name = "fontpair", help = "Deep Shadow copy draw order and text sync",
    default = "dump",
    verbs = {
        { word = "dump", help = "every live pair: layers, taper, text sync", fn = DebugFontPair },
        { word = "capture", help = "record the damage meter's name pairs through the next fight", fn = armCapture },
        { word = "probe", help = "reopen the last capture's frozen strings", fn = showProbe },
    },
})
