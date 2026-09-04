-- objectivetracker.lua - Objective Tracker styling: header fonts, quest text, block colors
local addonName, addon = ...

-- Targets Blizzard's Objective Tracker (`ObjectiveTrackerFrame`, Edit Mode system id 12) and provides:
-- - Edit Mode settings: Height, Opacity, Text Size
-- - Addon-only text styling (Font Face, Font Style, Font Color) for:
--   - Module header text (e.g., CampaignQuestObjectiveTracker.Header.Text)
--   - Quest name (usually block.HeaderButton's FontString; sometimes block.HeaderText)
--   - Objective text (line.Text / lastRegion.Text)
--
-- Zero‑Touch invariant:
-- - If the profile has no persisted table for this component, ApplyStyling must do nothing.
-- - Even if the component DB exists due to Edit Mode changes, text styling should only apply
--   when the specific text config tables exist (so changing Height doesn't implicitly restyle text).

-- Weak-key lookup tables to avoid writing properties to Blizzard frames
-- (which would taint them and cause secret value errors during Edit Mode operations)
local otState = setmetatable({}, { __mode = "k" })  -- frame/fs/bg/module -> state table

-- Helper to get or create state for a frame/object
local function getState(obj)
    if not obj then return nil end
    if not otState[obj] then
        otState[obj] = {}
    end
    return otState[obj]
end

-- Module-level storage for captured FontObjects (used to read live Edit Mode text size)
local _capturedFontObjects = {}

-- Capture the original FontObject BEFORE the first SetFont (which detaches
-- the fontstring). Allows reading the live text size during Edit Mode preview.
local function CaptureFontObject(fs)
    local state = getState(fs)
    if state and not state.originalFontObject then
        local ok, fontObj = pcall(fs.GetFontObject, fs)
        if ok and fontObj then
            state.originalFontObject = fontObj
            _capturedFontObjects[fontObj] = true
        end
    end
end

local function SafeSetFont(fs, face, size, flags)
    if not (fs and fs.SetFont) then return false end
    if not face or not size then return false end
    CaptureFontObject(fs)
    return pcall(fs.SetFont, fs, face, size, flags)
end

-- Read the live text size from a captured FontObject.
-- Used during Edit Mode live preview when GetSetting returns stale persisted values.
local function GetLiveTextSizeFromFontObject()
    for fontObj in pairs(_capturedFontObjects) do
        if fontObj and type(fontObj.GetFont) == "function" then
            local ok, _, size = pcall(fontObj.GetFont, fontObj)
            if ok and size and size > 0 then
                return size
            end
        end
    end
end

local function SafeSetTextColor(fs, r, g, b, a)
    if not (fs and fs.SetTextColor) then return false end
    return pcall(fs.SetTextColor, fs, r, g, b, a)
end

local function GetButtonFontString(button)
    if not button then return nil end

    if type(button.GetFontString) == "function" then
        local ok, fs = pcall(button.GetFontString, button)
        if ok and fs then return fs end
    end

    -- Common patterns: .Text, .text, .TextString
    if button.Text and type(button.Text.SetTextColor) == "function" then return button.Text end
    if button.text and type(button.text.SetTextColor) == "function" then return button.text end
    if button.TextString and type(button.TextString.SetTextColor) == "function" then return button.TextString end
end

local function BrightenRGBTowardsWhite(r, g, b, factor)
    -- Lerp each component towards 1.0 (white) to mimic Blizzard hover highlight behavior.
    -- factor: 0.0 = no change, 1.0 = white.
    factor = tonumber(factor) or 0.35
    if factor < 0 then factor = 0 elseif factor > 1 then factor = 1 end

    r = tonumber(r) or 1
    g = tonumber(g) or 1
    b = tonumber(b) or 1

    return
        r + (1 - r) * factor,
        g + (1 - g) * factor,
        b + (1 - b) * factor
end

local function ResolveQuestNameFontString(block)
    if type(block) ~= "table" then return nil end

    -- Preferred (framestack-confirmed): quest title fontstring is `block.HeaderText`.
    -- Some templates make the entire block clickable via `HeaderButton`, which can contain
    -- objective text regions; do NOT scan button regions to avoid accidentally targeting
    -- `block.lastRegion.Text` and highlight objectives.
    local fs = block.HeaderText
    if fs and type(fs.SetTextColor) == "function" then return fs end

    -- Fallback: if a template does not expose HeaderText, try the header button's own fontstring
    -- (but ONLY via explicit fontstring accessors, not region scanning).
    local btn = block.HeaderButton
    local btnFS = GetButtonFontString(btn)
    if btnFS then return btnFS end
end

local function GetCurrentFont(fs)
    if not (fs and fs.GetFont) then return nil end
    local ok, face, size, flags = pcall(fs.GetFont, fs)
    if not ok then return nil end
    return face, size, flags
end

local function IsEditModeActive()
    return addon.EditMode.IsEditModeActiveOrOpening()
end

local function GetObjectiveTrackerTextSize(componentSelf, preferLiveFontObject)
    -- Objective Tracker Text Size is owned by Edit Mode (system 12, setting 2 by default).
    --
    -- During Edit Mode live preview, the persisted values (DB and GetSetting) are stale.
    -- The live size must be read from a captured FontObject instead.
    if preferLiveFontObject or IsEditModeActive() then
        local liveSize = GetLiveTextSizeFromFontObject()
        if liveSize and liveSize > 0 then
            return liveSize
        end
    end

    -- Prefer DB value (synced from Edit Mode after Save/Exit)
    if componentSelf and type(componentSelf.db) == "table" then
        local v = tonumber(componentSelf.db.textSize)
        -- Guard: treat 0/negative as invalid (observed when some clients persist the slider as an index).
        if v and v > 0 then return v end
    end

    -- Fallback to Edit Mode API
    local frame = _G.ObjectiveTrackerFrame
    if frame and addon and addon.EditMode and type(addon.EditMode.GetSetting) == "function" then
        -- Fallback assumes stable ordering: 0=height, 1=opacity, 2=text size.
        local ok, raw = pcall(addon.EditMode.GetSetting, frame, 2)
        if ok then
            local v = tonumber(raw)
            if v and v > 0 then return v end
        end
    end

    return 12
end

local function ApplyFontFaceAndStylePreservingSize(fs, cfg, sizeOverride)
    if not fs or not cfg then return end

    -- Only apply if at least one of these fields is present.
    if cfg.fontFace == nil and cfg.style == nil then return end

    local _, curSize, curFlags = GetCurrentFont(fs)
    local size = tonumber(sizeOverride) or curSize
    if not size then
        -- As a fallback, use GameFontNormal size if available.
        local ok, _, fallbackSize = pcall(function()
            local _, s = _G.GameFontNormal:GetFont()
            return nil, s
        end)
        size = (ok and fallbackSize) or 12
    end

    local face = cfg.fontFace and (addon.ResolveFontFace and addon.ResolveFontFace(cfg.fontFace) or cfg.fontFace) or nil
    if not face then
        -- Only style is specified: keep the existing face.
        face = select(1, GetCurrentFont(fs))
    end
    if not face then return end

    if cfg.style ~= nil then
        -- Styled path: ApplyFontStyle decodes the pseudo-style, so the
        -- SHADOW*/HEAVY* half renders instead of being dropped by SetFont.
        CaptureFontObject(fs)
        addon.ApplyFontStyle(fs, face, size, cfg.style)
    else
        -- Face-only path: keep the string's current flags, sanitized.
        -- GetFont() readback can carry SLUG, which SetFont rejects as of
        -- 12.0.7, so re-feed only tokens SetFont accepts and leave the
        -- existing shadow untouched.
        local flags = nil
        if type(curFlags) == "string" and curFlags ~= "" then
            local kept = {}
            if curFlags:find("THICKOUTLINE", 1, true) then
                kept[#kept + 1] = "THICKOUTLINE"
            elseif curFlags:find("OUTLINE", 1, true) then
                kept[#kept + 1] = "OUTLINE"
            end
            if curFlags:find("MONOCHROME", 1, true) then
                kept[#kept + 1] = "MONOCHROME"
            end
            if #kept > 0 then flags = table.concat(kept, ", ") end
        end
        SafeSetFont(fs, face, size, flags)
    end
end

local function ApplyColorWithDefaultRestore(fs, cfg)
    if not fs or not cfg then return end

    -- IMPORTANT: Objective Tracker recycles (pools) block/line frames on collapse/expand.
    -- Any state cached can become stale when that fontstring is reused
    -- for a different quest/line. Clear cached color state on every pass to avoid "swapping"
    -- behavior where one item is styled and the other is not.
    local state = getState(fs)
    if state then
        state.baseColor = nil
        state.appliedCustomColor = nil
    end

    -- Color is a mode selector (Default/Custom).
    -- In Default mode, no color is set; Blizzard remains the source of truth.
    if cfg.colorMode ~= "custom" then
        return
    end

    local c = cfg.color
    if type(c) ~= "table" then return end
    if state then state.applyingColor = true end
    SafeSetTextColor(fs, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    if state then state.applyingColor = nil end
end

local function EnsureQuestNameHoverColorHook(headerText, ownerBlock)
    if not headerText then return end

    local state = getState(headerText)
    if not state then return end

    -- Keep an up-to-date reference in case blocks/fonts are recycled.
    state.questNameOwnerBlock = ownerBlock

    if state.questNameHooked then return end
    if not hooksecurefunc then return end
    if type(headerText.SetTextColor) ~= "function" then return end

    state.questNameHooked = true

    local function isOwnerHighlighted()
        local st = getState(headerText)
        local block = st and st.questNameOwnerBlock
        if type(block) ~= "table" then return false end

        if block.isHighlighted then return true end
        if block.HeaderButton and type(block.HeaderButton.IsMouseOver) == "function" then
            local ok, over = pcall(block.HeaderButton.IsMouseOver, block.HeaderButton)
            if ok and over then return true end
        end
        return false
    end

    local function enforceQuestNameColor()
        local st = getState(headerText)
        if st and st.applyingColor then return end

        -- Read current profile live to stay correct across profile switches.
        local db = addon and addon.db and addon.db.profile and addon.db.profile.components and addon.db.profile.components.objectiveTracker
        if type(db) ~= "table" then return end

        local cfg = db.textQuestName
        if type(cfg) ~= "table" then return end
        if cfg.colorMode ~= "custom" then return end

        local c = cfg.color
        if type(c) ~= "table" then return end

        local r, g, b, a = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
        if isOwnerHighlighted() then
            r, g, b = BrightenRGBTowardsWhite(r, g, b, 0.35)
        end

        if st then st.applyingColor = true end
        pcall(headerText.SetTextColor, headerText, r, g, b, a)
        if st then st.applyingColor = nil end
    end

    -- Blizzard hover logic changes quest name colors by calling SetTextColor; re-apply the styled color after.
    hooksecurefunc(headerText, "SetTextColor", enforceQuestNameColor)

    -- Some templates use SetVertexColor on fontstrings; cover both.
    if type(headerText.SetVertexColor) == "function" then
        hooksecurefunc(headerText, "SetVertexColor", enforceQuestNameColor)
    end
end

local function IterateModuleBlocks(module, fn)
    if not module or type(fn) ~= "function" then return end

    -- Preferred: linked list via firstBlock/nextBlock (observed in framestack).
    local visited = 0
    local block = module.firstBlock
    while type(block) == "table" and visited < 500 do
        visited = visited + 1
        fn(block)
        block = block.nextBlock
    end

    -- Fallback: usedBlocks table (varies by module implementation).
    if type(module.usedBlocks) == "table" then
        for _, b in pairs(module.usedBlocks) do
            if type(b) == "table" then fn(b) end
        end
    end

    -- AdventureObjectiveTracker (Collections): blocks are keyed under ContentsFrame with dynamic keys.
    -- Example frame paths:
    -- - AdventureObjectiveTracker.ContentsFrame.<dynamicKey>.HeaderText
    -- - AdventureObjectiveTracker.ContentsFrame.<dynamicKey>.objective.Text
    -- These are not exposed via firstBlock/usedBlocks on some client builds.
    local adventure = _G.AdventureObjectiveTracker
    if adventure and module == adventure then
        local contents = module.ContentsFrame
        if type(contents) == "table" then
            for _, b in pairs(contents) do
                if type(b) == "table" then
                    local hasHeader = b.HeaderText and type(b.HeaderText.SetTextColor) == "function"
                    local hasObjective = b.objective and b.objective.Text and type(b.objective.Text.SetTextColor) == "function"
                    if hasHeader or hasObjective then
                        fn(b)
                    end
                end
            end
        end
    end
end

local function IterateBlockLines(block, fn)
    if not block or type(fn) ~= "function" then return end

    if type(block.ForEachUsedLine) == "function" then
        pcall(block.ForEachUsedLine, block, function(line)
            if type(line) == "table" then fn(line) end
        end)
        return
    end

    if type(block.usedLines) == "table" then
        for _, line in pairs(block.usedLines) do
            if type(line) == "table" then fn(line) end
        end
    end
end

local function ApplyObjectiveTrackerTextStyling(self)
    local tracker = _G.ObjectiveTrackerFrame
    if not tracker then return end

    -- Zero‑Touch: if still on proxy DB, do nothing.
    if addon.IsComponentUnconfigured(self) then
        return
    end

    local db = self.db
    if type(db) ~= "table" then return end

    -- Only style text types that are explicitly present in the DB.
    -- rawget: bypass attachSettingsDefaults metatable so table-type defaults
    -- (e.g. { style = "OUTLINE" }) don't leak onto zero-touch profiles.
    local headerCfg = rawget(db, "textHeader")
    local questNameCfg = rawget(db, "textQuestName")
    local objectiveCfg = rawget(db, "textQuestObjective")
    if not headerCfg and not questNameCfg and not objectiveCfg then
        return
    end

    local modules = tracker.modules
    if type(modules) ~= "table" then return end

    -- Use the Edit Mode Text Size (live) rather than the fontstring's current size.
    -- Important: Scoot uses SetFont which detaches from FontObjects; by explicitly using the
    -- Edit Mode size here, preserving live behavior when Edit Mode updates the system.
    local textSize = GetObjectiveTrackerTextSize(self)

    -- Root header (ObjectiveTrackerFrame.Header.Text)
    if headerCfg and tracker.Header and tracker.Header.Text then
        ApplyFontFaceAndStylePreservingSize(tracker.Header.Text, headerCfg, textSize)
        ApplyColorWithDefaultRestore(tracker.Header.Text, headerCfg)
    end

    for _, module in pairs(modules) do
        if type(module) == "table" then
            -- Module header (Campaign, World Quests, etc.)
            if headerCfg and module.Header and module.Header.Text then
                ApplyFontFaceAndStylePreservingSize(module.Header.Text, headerCfg, textSize)
                ApplyColorWithDefaultRestore(module.Header.Text, headerCfg)
            end

            -- Per-quest blocks
            IterateModuleBlocks(module, function(block)
                -- Quest name
                if questNameCfg then
                    local questNameFS = ResolveQuestNameFontString(block)
                    if questNameFS then
                        EnsureQuestNameHoverColorHook(questNameFS, block)
                        ApplyFontFaceAndStylePreservingSize(questNameFS, questNameCfg, textSize)
                        ApplyColorWithDefaultRestore(questNameFS, questNameCfg)
                    end
                end

                -- Objective lines (best-effort)
                if objectiveCfg then
                    IterateBlockLines(block, function(line)
                        local fs = line.Text or line.TextString or line.text
                        if fs then
                            ApplyFontFaceAndStylePreservingSize(fs, objectiveCfg, textSize)
                            ApplyColorWithDefaultRestore(fs, objectiveCfg)
                        end
                    end)

                    -- Common fallback: lastRegion.Text observed in framestack.
                    if block.lastRegion and block.lastRegion.Text then
                        ApplyFontFaceAndStylePreservingSize(block.lastRegion.Text, objectiveCfg, textSize)
                        ApplyColorWithDefaultRestore(block.lastRegion.Text, objectiveCfg)
                    end

                    -- AdventureObjectiveTracker (Collections): per-item objective text lives at block.objective.Text.
                    if block.objective and block.objective.Text then
                        ApplyFontFaceAndStylePreservingSize(block.objective.Text, objectiveCfg, textSize)
                        ApplyColorWithDefaultRestore(block.objective.Text, objectiveCfg)
                    end
                end
            end)
        end
    end
end

local function SafeSetShown(region, shown)
    if not region then return end
    if region.SetShown then
        pcall(region.SetShown, region, shown and true or false)
        return
    end
    if shown then
        if region.Show then pcall(region.Show, region) end
    else
        if region.Hide then pcall(region.Hide, region) end
    end
end

local function CaptureObjectiveTrackerHeaderBackgroundBaseline(bg)
    if not bg then return end
    local state = getState(bg)
    if not state or state.baseBG then return end
    local base = {}
    if bg.IsShown then
        local ok, v = pcall(bg.IsShown, bg)
        if ok then base.shown = v and true or false end
    end
    if bg.GetAlpha then
        local ok, a = pcall(bg.GetAlpha, bg)
        if ok and a ~= nil then base.alpha = a end
    end
    if bg.GetVertexColor then
        local ok, r, g, b, a = pcall(bg.GetVertexColor, bg)
        if ok and r and g and b then
            base.r, base.g, base.b, base.vA = r, g, b, a
        end
    end
    state.baseBG = base
end

local function RestoreObjectiveTrackerHeaderBackground(bg)
    if not bg then return end
    local state = getState(bg)
    local base = state and state.baseBG
    if type(base) ~= "table" then return end

    if base.shown ~= nil then
        SafeSetShown(bg, base.shown)
    end
    if bg.SetAlpha and base.alpha ~= nil then
        pcall(bg.SetAlpha, bg, base.alpha)
    end
    if bg.SetVertexColor and base.r ~= nil then
        pcall(bg.SetVertexColor, bg, base.r or 1, base.g or 1, base.b or 1, base.vA)
    end
end

local function GatherObjectiveTrackerHeaderBackgrounds()
    local tracker = _G.ObjectiveTrackerFrame
    if not tracker then return {} end

    local targets = {}
    local seen = {}

    local function add(bg)
        if not bg or seen[bg] then return end
        seen[bg] = true
        table.insert(targets, bg)
    end

    -- Explicit targets requested (plus root header background)
    if tracker.Header and tracker.Header.Background then
        add(tracker.Header.Background)
    end
    local campaign = _G.CampaignQuestObjectiveTracker
    if campaign and campaign.Header and campaign.Header.Background then
        add(campaign.Header.Background)
    end
    -- Quest module header (`QuestObjectiveTracker.Header.Background`)
    -- Note: Some client builds may not expose this module inside `ObjectiveTrackerFrame.modules`,
    -- so keep an explicit reference in addition to the best-effort module scan.
    local quest = _G.QuestObjectiveTracker
    if quest and quest.Header and quest.Header.Background then
        add(quest.Header.Background)
    end
    local world = _G.WorldQuestObjectiveTracker
    if world and world.Header and world.Header.Background then
        add(world.Header.Background)
    end

    -- Best-effort: include any module header backgrounds present on this client.
    local modules = tracker.modules
    if type(modules) == "table" then
        for _, module in pairs(modules) do
            if type(module) == "table" and module.Header and module.Header.Background then
                add(module.Header.Background)
            end
        end
    end

    return targets
end

local function ApplyObjectiveTrackerHeaderBackgroundStyling(self)
    local tracker = _G.ObjectiveTrackerFrame
    if not tracker then return end

    -- Zero‑Touch: if still on proxy DB, do nothing.
    if addon.IsComponentUnconfigured(self) then
        return
    end

    local db = self.db
    if type(db) ~= "table" then return end

    -- Only act when the user has explicitly configured this section.
    -- rawget: bypass metatable so defaults don't trigger on zero-touch profiles.
    local hide = rawget(db, "hideHeaderBackgrounds")
    local tintEnable = rawget(db, "tintHeaderBackgroundEnable")
    local tintColor = rawget(db, "tintHeaderBackgroundColor")
    if hide == nil and tintEnable == nil and tintColor == nil then
        return
    end

    local targets = GatherObjectiveTrackerHeaderBackgrounds()
    if #targets == 0 then return end

    local useHide = hide and true or false
    local useTint = tintEnable and true or false
    local c = (type(tintColor) == "table") and tintColor or { 1, 1, 1, 1 }
    local r, g, b, a = c[1] or 1, c[2] or 1, c[3] or 1, c[4]

    for _, bg in ipairs(targets) do
        if bg then
            CaptureObjectiveTrackerHeaderBackgroundBaseline(bg)
            local bgState = getState(bg)

            if useHide then
                SafeSetShown(bg, false)
                if bgState then bgState.appliedHide = true end
            else
                if bgState and bgState.appliedHide then
                    -- Restore visibility to baseline when un-hiding.
                    local base = bgState.baseBG
                    if type(base) == "table" and base.shown ~= nil then
                        SafeSetShown(bg, base.shown)
                    else
                        SafeSetShown(bg, true)
                    end
                    bgState.appliedHide = nil
                end

                if useTint then
                    if bg.SetVertexColor then
                        pcall(bg.SetVertexColor, bg, r, g, b, a)
                    end
                    if bg.SetAlpha and a ~= nil then
                        pcall(bg.SetAlpha, bg, a)
                    end
                    if bgState then bgState.appliedTint = true end
                else
                    if bgState and bgState.appliedTint then
                        RestoreObjectiveTrackerHeaderBackground(bg)
                        bgState.appliedTint = nil
                    end
                end
            end
        end
    end
end

local function ClampPercent0To100(value)
    local v = tonumber(value)
    if v == nil then return nil end
    if v < 0 then v = 0 elseif v > 100 then v = 100 end
    return v
end

local PlayerInCombat = addon.Opacity.InCombat

local function PlayerInDungeonOrRaidInstance()
    if type(IsInInstance) ~= "function" then
        return false
    end

    local ok, inInstance, instanceType = pcall(IsInInstance)
    if not ok then
        return false
    end

    return (inInstance == true) and (instanceType == "party" or instanceType == "raid")
end

-- Kept off addon.Opacity.Resolve: one override with a compound gate (combat in a dungeon or raid), else the baseline.
local function ApplyObjectiveTrackerCombatOpacity(self)
    local tracker = _G.ObjectiveTrackerFrame
    if not tracker then return end

    -- Zero‑Touch: if still on proxy DB, do nothing.
    if addon.IsComponentUnconfigured(self) then
        return
    end

    local db = self.db
    if type(db) ~= "table" then return end

    local inCombat = PlayerInCombat()
    local inInstance = PlayerInDungeonOrRaidInstance()
    local configured = ClampPercent0To100(rawget(db, "opacityInInstanceCombat"))
    local shouldApply = inCombat and inInstance

    -- NOTE: Alpha is intentionally NOT set on ObjectiveTrackerFrame itself.
    -- Alpha is multiplicative through the frame tree; fading the parent means children like
    -- ScenarioObjectiveTracker (Mythic+ progress / scenario UI) could not remain at full opacity.
    --
    -- Instead, each module (Header + ContentsFrame) is faded except ScenarioObjectiveTracker.
    local function ForEachCombatOpacityTargetFrame(fn)
        -- Root header (the "Objectives" header bar) should fade along with modules.
        if tracker.Header and tracker.Header.SetAlpha then
            fn(tracker.Header)
        end

        local modules = tracker.modules
        if type(modules) ~= "table" then
            return
        end

        local scenarioModule = _G.ScenarioObjectiveTracker
        for _, module in pairs(modules) do
            if type(module) == "table" and module ~= scenarioModule then
                local header = module.Header
                if header and header.SetAlpha then
                    fn(header)
                end

                local contents = module.ContentsFrame
                if contents and contents.SetAlpha then
                    fn(contents)
                end
            end
        end
    end

    local function RestoreFrameBaseline(frame)
        if not frame then return end
        local frameState = getState(frame)
        if not frameState or not frameState.combatOpacityApplied then
            return
        end
        if frame.SetAlpha and frameState.combatOpacityBaseAlpha ~= nil then
            pcall(frame.SetAlpha, frame, frameState.combatOpacityBaseAlpha)
        end
        frameState.combatOpacityApplied = nil
        frameState.combatOpacityBaseAlpha = nil
    end

    local function ApplyFrameOverride(frame, alpha)
        if not frame or not frame.SetAlpha then
            return
        end

        local frameState = getState(frame)
        if not frameState then return end

        -- Capture baseline alpha once to allow restoring it after combat.
        if frameState.combatOpacityBaseAlpha == nil and frame.GetAlpha then
            local ok, a = pcall(frame.GetAlpha, frame)
            if ok and a ~= nil then
                frameState.combatOpacityBaseAlpha = a
            end
        end

        pcall(frame.SetAlpha, frame, alpha)
        frameState.combatOpacityApplied = true
    end

    if shouldApply then
        if configured == nil then
            -- If the user cleared the setting mid-combat, restore baseline immediately.
            ForEachCombatOpacityTargetFrame(RestoreFrameBaseline)
            return
        end

        ForEachCombatOpacityTargetFrame(function(frame)
            ApplyFrameOverride(frame, configured / 100)
        end)
        return
    end

    -- Not in qualifying combat (either out of combat, or in combat but not in a dungeon/raid):
    -- restore baseline if an override was applied previously.
    ForEachCombatOpacityTargetFrame(RestoreFrameBaseline)
end

local function ApplyObjectiveTrackerScale(self)
    local tracker = _G.ObjectiveTrackerFrame
    if not tracker or not tracker.SetScale then return end
    if addon.IsComponentUnconfigured(self) then return end
    local db = self.db
    if type(db) ~= "table" then return end
    local scale = tonumber(rawget(db, "scale"))
    if not scale then return end  -- nil = untouched (Zero-Touch)
    if scale < 0.5 then scale = 0.5 elseif scale > 1.5 then scale = 1.5 end
    pcall(tracker.SetScale, tracker, scale)
end

-- ---------------------------------------------------------------------------
-- Dungeon Tracker (ScenarioObjectiveTracker styling)
-- ---------------------------------------------------------------------------

-- Returns the dungeonTracker sub-table from the component DB, or nil if
-- the user hasn't configured anything (Zero-Touch).
local function GetDungeonTrackerDB(componentSelf)
    if addon.IsComponentUnconfigured(componentSelf) then
        return nil
    end
    local db = componentSelf.db
    if type(db) ~= "table" then return nil end
    return rawget(db, "dungeonTracker")
end

local function GetStageBlock()
    local scenario = _G.ScenarioObjectiveTracker
    if not scenario then return nil end
    return scenario.StageBlock
end

local function GetChallengeModeBlock()
    local scenario = _G.ScenarioObjectiveTracker
    if not scenario then return nil end
    return scenario.ChallengeModeBlock
end

-- Approximate Blizzard default green for ChallengeMode-TimerFill atlas.
-- The atlas bakes this green gradient into the texture; no SetStatusBarColor is used.
-- When a custom texture replaces the atlas, this color is applied to match the stock look.
local BLIZZARD_TIMER_BAR_COLOR = { 0.07, 0.76, 0.0, 1.0 }

-- Apply font/size/style/color to a FontString from a config sub-table.
-- Shared by all dungeon tracker text tabs.
local function ApplyDTTextConfig(fs, cfg)
    if not fs or type(cfg) ~= "table" then return end
    local sizeOverride = tonumber(cfg.size)
    ApplyFontFaceAndStylePreservingSize(fs, cfg, sizeOverride)
    ApplyColorWithDefaultRestore(fs, cfg)
end

local function ApplyDungeonTrackerStageTextStyling(dtDB)
    if not dtDB then return end
    local cfg = rawget(dtDB, "stageText")
    if type(cfg) ~= "table" then return end

    local stageBlock = GetStageBlock()
    if stageBlock and stageBlock.Stage then
        ApplyDTTextConfig(stageBlock.Stage, cfg)
    end
end

local function ApplyDungeonTrackerKeyLevelTextStyling(dtDB)
    if not dtDB then return end
    local cfg = rawget(dtDB, "keyLevelText")
    if type(cfg) ~= "table" then return end

    local cmBlock = GetChallengeModeBlock()
    if cmBlock and cmBlock.Level then
        ApplyDTTextConfig(cmBlock.Level, cfg)
    end
end

local function ApplyDungeonTrackerTimerTextStyling(dtDB)
    if not dtDB then return end
    local cfg = rawget(dtDB, "timerText")
    if type(cfg) ~= "table" then return end

    local cmBlock = GetChallengeModeBlock()
    if cmBlock and cmBlock.TimeLeft then
        ApplyDTTextConfig(cmBlock.TimeLeft, cfg)
    end
end

-- Helper: hide or restore a texture via alpha with baseline capture.
local function DTSetTextureHidden(tex, hidden)
    if not tex then return end
    local state = getState(tex)
    if hidden then
        if state and not state.dtBaseAlpha then
            if tex.GetAlpha then
                local ok, a = pcall(tex.GetAlpha, tex)
                if ok and a ~= nil then state.dtBaseAlpha = a end
            end
        end
        if tex.SetAlpha then pcall(tex.SetAlpha, tex, 0) end
        if state then state.dtHidden = true end
    else
        if state and state.dtHidden then
            local base = state.dtBaseAlpha
            if tex.SetAlpha then pcall(tex.SetAlpha, tex, base or 1) end
            state.dtHidden = nil
            state.dtBaseAlpha = nil
        end
    end
end

local function ApplyDungeonTrackerTrashPercentTextStyling(dtDB)
    if not dtDB then return end
    local cfg = rawget(dtDB, "trashPercentText")
    if type(cfg) ~= "table" then return end

    -- Progress bars are managed by the MODULE (ScenarioObjectiveTracker), not the block.
    -- ObjectiveTrackerModuleMixin:GetProgressBar stores them in module.usedProgressBars
    -- keyed by line objects.
    local scenario = _G.ScenarioObjectiveTracker
    if not scenario then return end

    local usedBars = scenario.usedProgressBars
    if type(usedBars) == "table" then
        for _, progressBar in pairs(usedBars) do
            if type(progressBar) == "table" and progressBar.Bar and progressBar.Bar.Label then
                ApplyDTTextConfig(progressBar.Bar.Label, cfg)
            end
        end
    end
end

local BLIZZARD_AFFIX_BORDER_ATLAS = "ChallengeMode-AffixRing-Sm"

local function ApplyDungeonTrackerAffixIconsStyling(dtDB)
    if not dtDB then return end

    local cmBlock = GetChallengeModeBlock()
    if not cmBlock or not cmBlock.affixPool then return end

    local affixScale = tonumber(rawget(dtDB, "affixIconScale"))
    local borderStyle = rawget(dtDB, "affixBorderStyle")
    local tintEnable = rawget(dtDB, "affixBorderTintEnable")
    local tintColor = rawget(dtDB, "affixBorderTintColor")

    -- Nothing configured → Zero-Touch
    if not affixScale and not borderStyle and not tintEnable then return end

    for affixFrame in cmBlock.affixPool:EnumerateActive() do
        if affixFrame then
            -- Scale
            if affixScale and affixFrame.SetScale then
                pcall(affixFrame.SetScale, affixFrame, affixScale)
            end

            -- Border style
            local border = affixFrame.Border
            if border and borderStyle then
                if borderStyle == "none" then
                    pcall(border.SetAlpha, border, 0)
                elseif borderStyle == "default" then
                    -- Restore Blizzard default: atlas + original anchoring (setAllPoints)
                    pcall(border.SetAtlas, border, BLIZZARD_AFFIX_BORDER_ATLAS, false)
                    pcall(border.ClearAllPoints, border)
                    pcall(border.SetAllPoints, border, affixFrame)
                    pcall(border.SetAlpha, border, 1)
                else
                    -- Custom border from IconBorders registry
                    local styleDef = addon.IconBorders and addon.IconBorders.GetStyle and addon.IconBorders.GetStyle(borderStyle)
                    if styleDef and styleDef.atlas then
                        pcall(border.SetAtlas, border, styleDef.atlas, false)
                        -- Expand border to account for atlas padding
                        local ex = (styleDef.expandX or 0)
                        local ey = (styleDef.expandY or 0)
                        pcall(border.ClearAllPoints, border)
                        pcall(border.SetPoint, border, "TOPLEFT", affixFrame, "TOPLEFT", -ex, ey)
                        pcall(border.SetPoint, border, "BOTTOMRIGHT", affixFrame, "BOTTOMRIGHT", ex, -ey)
                        pcall(border.SetAlpha, border, 1)
                    end
                end
            end

            -- Border tint (applies to any border style except "none")
            if border and borderStyle ~= "none" then
                if tintEnable and type(tintColor) == "table" then
                    pcall(border.SetVertexColor, border, tintColor[1] or 1, tintColor[2] or 1, tintColor[3] or 1, tintColor[4] or 1)
                else
                    pcall(border.SetVertexColor, border, 1, 1, 1, 1)
                end
            end
        end
    end
end

local function ApplyDungeonTrackerTimerBarStyling(dtDB)
    if not dtDB then return end

    local cmBlock = GetChallengeModeBlock()
    if not cmBlock then return end
    local statusBar = cmBlock.StatusBar
    if not statusBar then return end

    -- Hide Timer Bar
    local hideTimerBar = rawget(dtDB, "hideTimerBar")
    if hideTimerBar ~= nil then
        DTSetTextureHidden(statusBar, hideTimerBar)
    end

    -- Foreground texture
    local fgTexKey = rawget(dtDB, "timerBarForegroundTexture")
    local usingCustomFgTex = fgTexKey and fgTexKey ~= "default"
    if usingCustomFgTex then
        local path = addon.Media and addon.Media.ResolveBarTexturePath and addon.Media.ResolveBarTexturePath(fgTexKey)
        if path then
            pcall(statusBar.SetStatusBarTexture, statusBar, path)
        end
    end
    -- Note: "default" leaves the Blizzard atlas (ChallengeMode-TimerFill) in place.

    -- Foreground color
    -- "default"  → with default atlas: don't touch; with custom texture: apply Blizzard green
    -- "original" → white vertex color (texture shows its native colors)
    -- "custom"   → user-chosen color
    local fgColorMode = rawget(dtDB, "timerBarForegroundColorMode")
    if fgColorMode == "custom" then
        local c = rawget(dtDB, "timerBarForegroundColor")
        if type(c) == "table" then
            pcall(statusBar.SetStatusBarColor, statusBar, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        end
    elseif fgColorMode == "original" then
        pcall(statusBar.SetStatusBarColor, statusBar, 1, 1, 1, 1)
    elseif usingCustomFgTex then
        -- "default" with custom texture: tint to match stock Blizzard green
        local bc = BLIZZARD_TIMER_BAR_COLOR
        pcall(statusBar.SetStatusBarColor, statusBar, bc[1], bc[2], bc[3], bc[4])
    end
    -- else: "default" with default atlas → don't touch (atlas carries its own green)

    -- No background row: the "dark area" behind the fill is just the StatusBar's unfilled region,
    -- not a separate texture. The decorative TimerBGBack/TimerBG are handled by the Visibility tab.
end

local function ApplyDungeonTrackerVisibility(dtDB)
    if not dtDB then return end

    -- StageBlock background (NormalBG)
    local hideStageBackground = rawget(dtDB, "hideStageBackground")
    if hideStageBackground ~= nil then
        local stageBlock = GetStageBlock()
        if stageBlock and stageBlock.NormalBG then
            DTSetTextureHidden(stageBlock.NormalBG, hideStageBackground)
        end
    end

    -- ChallengeModeBlock backgrounds (timer frame artwork)
    local hideTimerBackground = rawget(dtDB, "hideTimerBackground")
    if hideTimerBackground ~= nil then
        local cmBlock = GetChallengeModeBlock()
        if cmBlock then
            -- Named background textures
            DTSetTextureHidden(cmBlock.TimerBGBack, hideTimerBackground)
            DTSetTextureHidden(cmBlock.TimerBG, hideTimerBackground)

            -- Anonymous overlay texture (atlas="challengemode-timer", setAllPoints=true).
            -- Has no parentKey, found by iterating regions.
            if not cmBlock._dtOverlayTex then
                local regions = { cmBlock:GetRegions() }
                for _, region in ipairs(regions) do
                    if region.GetObjectType and region:GetObjectType() == "Texture"
                       and region ~= cmBlock.TimerBGBack and region ~= cmBlock.TimerBG
                       and region ~= cmBlock.Level and region ~= cmBlock.TimeLeft then
                        -- The challengemode-timer overlay is the only remaining full-size texture
                        local numPoints = region.GetNumPoints and region:GetNumPoints() or 0
                        if numPoints >= 2 then
                            cmBlock._dtOverlayTex = region
                            break
                        end
                    end
                end
            end
            DTSetTextureHidden(cmBlock._dtOverlayTex, hideTimerBackground)
        end
    end
end

local function ApplyDungeonTrackerStyling(componentSelf)
    local dtDB = GetDungeonTrackerDB(componentSelf)
    if not dtDB then return end

    ApplyDungeonTrackerStageTextStyling(dtDB)
    ApplyDungeonTrackerKeyLevelTextStyling(dtDB)
    ApplyDungeonTrackerTimerTextStyling(dtDB)
    ApplyDungeonTrackerTrashPercentTextStyling(dtDB)
    ApplyDungeonTrackerAffixIconsStyling(dtDB)
    ApplyDungeonTrackerTimerBarStyling(dtDB)
    ApplyDungeonTrackerVisibility(dtDB)
end

-- Collapse all non-Scenario OT modules when an M+ key starts.
local _collapseOtherOnKeyStart_installed = false
local function InstallCollapseOtherOnKeyStart(componentSelf)
    if _collapseOtherOnKeyStart_installed then return end
    _collapseOtherOnKeyStart_installed = true

    local function onEvent(event)
        -- Check setting live each time (handles profile switches, toggle changes).
        local dtDB = GetDungeonTrackerDB(componentSelf)
        if not dtDB then return end
        local enabled = rawget(dtDB, "collapseOtherOnKeyStart")
        if not enabled then return end

        local isActive = false
        if event == "CHALLENGE_MODE_START" then
            isActive = true
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Reconnect to an in-progress M+ run
            isActive = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive()
        end
        if not isActive then return end

        local tracker = _G.ObjectiveTrackerFrame
        if not tracker or type(tracker.modules) ~= "table" then return end

        local scenarioModule = _G.ScenarioObjectiveTracker
        for _, module in pairs(tracker.modules) do
            if type(module) == "table" and module ~= scenarioModule then
                if module.SetCollapsed and not module:IsCollapsed() then
                    pcall(module.SetCollapsed, module, true)
                end
            end
        end
    end
    addon.Events.On("ObjectiveTracker", "CHALLENGE_MODE_START", onEvent)
    addon.Events.On("ObjectiveTracker", "PLAYER_ENTERING_WORLD", onEvent)
end

-- Install hooks on ScenarioObjectiveTracker so styling is re-applied after Blizzard rebuilds.
local _dungeonTrackerHooksInstalled = false
local function InstallDungeonTrackerHooks(componentSelf)
    if _dungeonTrackerHooksInstalled then return end
    _dungeonTrackerHooksInstalled = true

    -- Re-apply on ScenarioObjectiveTracker layout changes
    local scenario = _G.ScenarioObjectiveTracker
    if scenario then
        local dtApplyQueued = false
        local function requestDTApply()
            if dtApplyQueued then return end
            dtApplyQueued = true
            _G.C_Timer.After(0, function()
                dtApplyQueued = false
                ApplyDungeonTrackerStyling(componentSelf)
            end)
        end

        if type(scenario.EndLayout) == "function" then
            hooksecurefunc(scenario, "EndLayout", requestDTApply)
        end
        if type(scenario.LayoutContents) == "function" then
            hooksecurefunc(scenario, "LayoutContents", requestDTApply)
        end
    end

    -- Re-apply after StageBlock updates (when stage text / BG changes)
    local stageBlock = GetStageBlock()
    if stageBlock and type(stageBlock.UpdateStageBlock) == "function" then
        hooksecurefunc(stageBlock, "UpdateStageBlock", function()
            _G.C_Timer.After(0, function()
                ApplyDungeonTrackerStyling(componentSelf)
            end)
        end)
    end

    -- ChallengeModeBlock hooks for M+ timer display
    local cmBlock = GetChallengeModeBlock()
    if cmBlock then
        -- Re-apply key level text + visibility after Activate (M+ start / reconnect)
        if type(cmBlock.Activate) == "function" then
            hooksecurefunc(cmBlock, "Activate", function()
                _G.C_Timer.After(0, function()
                    ApplyDungeonTrackerStyling(componentSelf)
                end)
            end)
        end

        -- PERF: UpdateTime runs every frame. Only re-apply timer text color if configured.
        -- Font face/size/style are stable and only need one application (on Activate);
        -- color must be re-applied because Blizzard resets it (WHITE vs RED) in UpdateTime.
        if type(cmBlock.UpdateTime) == "function" then
            hooksecurefunc(cmBlock, "UpdateTime", function()
                local dtDB = GetDungeonTrackerDB(componentSelf)
                if not dtDB then return end
                local cfg = rawget(dtDB, "timerText")
                if type(cfg) ~= "table" then return end
                if cfg.colorMode ~= "custom" then return end
                local c = cfg.color
                if type(c) ~= "table" then return end
                -- Direct call, no C_Timer — this runs every frame
                if cmBlock.TimeLeft then
                    SafeSetTextColor(cmBlock.TimeLeft, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
                end
            end)
        end

        -- Re-apply death count styling after deaths (for future expansion)
        if type(cmBlock.UpdateDeathCount) == "function" then
            hooksecurefunc(cmBlock, "UpdateDeathCount", function()
                _G.C_Timer.After(0, function()
                    ApplyDungeonTrackerStyling(componentSelf)
                end)
            end)
        end

        -- Re-apply affix styling after affixes are set up (for future expansion)
        if type(cmBlock.SetUpAffixes) == "function" then
            hooksecurefunc(cmBlock, "SetUpAffixes", function()
                _G.C_Timer.After(0, function()
                    ApplyDungeonTrackerStyling(componentSelf)
                end)
            end)
        end
    end

    -- Install the collapse-on-key-start listener (always installed, checks setting live)
    InstallCollapseOtherOnKeyStart(componentSelf)
end

local function ApplyObjectiveTrackerStylingAll(self)
    ApplyObjectiveTrackerHeaderBackgroundStyling(self)
    ApplyObjectiveTrackerTextStyling(self)
    ApplyObjectiveTrackerScale(self)
    ApplyDungeonTrackerStyling(self)
end

local function InstallObjectiveTrackerHooks(self)
    local tracker = _G.ObjectiveTrackerFrame
    if not tracker then return end
    local trackerState = getState(tracker)
    if not trackerState or trackerState.hooked then return end
    trackerState.hooked = true

    -- Coalesce re-application to one per frame.
    -- Use a module-level variable for the queued flag since self is the component table
    local applyQueued = false
    local function requestApply()
        if applyQueued then return end
        applyQueued = true
        _G.C_Timer.After(0, function()
            applyQueued = false
            ApplyObjectiveTrackerStylingAll(self)
        end)
    end

    local function EnsureModuleEndLayoutHook(module)
        if type(module) ~= "table" then return end
        local moduleState = getState(module)
        if not moduleState or moduleState.moduleHooked then return end
        moduleState.moduleHooked = true

        if type(module.EndLayout) == "function" then
            hooksecurefunc(module, "EndLayout", requestApply)
        end
    end

    -- Re-apply after any tracker update/layout pass.
    if type(tracker.Update) == "function" then
        hooksecurefunc(tracker, "Update", requestApply)
    end
    if type(tracker.UpdateSystem) == "function" then
        hooksecurefunc(tracker, "UpdateSystem", requestApply)
    end
    if type(tracker.UpdateLayout) == "function" then
        hooksecurefunc(tracker, "UpdateLayout", requestApply)
    end

    -- Re-apply after any module-level layout pass.
    -- Critical for per-category collapse/expand (Campaign/Quest/WorldQuest): modules rebuild
    -- their blocks via EndLayout/LayoutContents and may not always trigger top-level tracker hooks.
    local modules = tracker.modules
    if type(modules) == "table" then
        for _, module in pairs(modules) do
            EnsureModuleEndLayoutHook(module)
        end
    end

    -- IMPORTANT: `ObjectiveTrackerFrame.modules` can be nil or incomplete if Scoot installs hooks
    -- before the ObjectiveTrackerManager assigns modules (e.g., early in the login flow on some clients).
    -- When modules are later added to the container, the EndLayout hook must be attached then too.
    if type(tracker.AddModule) == "function" then
        hooksecurefunc(tracker, "AddModule", function(_, module)
            EnsureModuleEndLayoutHook(module)
            -- Apply after this module's first layout completes (coalesced).
            requestApply()
        end)
    end

    -- Text Size changes are applied via UpdateSystemSettingTextSize(). If Scoot has
    -- detached fontstrings from FontObjects (via SetFont), styling must be re-applied with the new size.
    --
    -- Fires for BOTH:
    -- - Scoot slider changes (flag is set)
    -- - Edit Mode live preview (flag is NOT set, but FontObject has the live size)
    --
    -- The live size is read from the captured FontObject (which Blizzard just updated) and
    -- styling is re-applied with that size. This enables live Edit Mode preview to work.
    if type(tracker.UpdateSystemSettingTextSize) == "function" then
        hooksecurefunc(tracker, "UpdateSystemSettingTextSize", function()
            -- Always re-apply styling - the live size is read from the FontObject
            requestApply()
        end)
    end
end

addon:RegisterComponentInitializer(function(self)
    local Component = addon.ComponentPrototype

    local objectiveTracker = Component:New({
        id = "objectiveTracker",
        name = "Objective Tracker",
        frameName = "ObjectiveTrackerFrame",
        settings = {
            -- Edit Mode-managed settings
            height = { type = "editmode", settingId = 0, default = 400, ui = { hidden = true } },
            opacity = { type = "editmode", settingId = 1, default = 100, ui = { hidden = true } },
            textSize = { type = "editmode", settingId = 2, default = 12, ui = { hidden = true } },

            -- Addon-only: in-instance combat override for Objective Tracker module alpha (0..100). Nil means "disabled".
            -- Applies only when the player is in combat AND in a dungeon/raid instance.
            -- ScenarioObjectiveTracker is intentionally excluded so Mythic+/Scenario progress remains readable.
            opacityInInstanceCombat = { type = "addon", ui = { hidden = true } },

            -- Addon-only: global scale for the entire Objective Tracker frame (0.5..1.5). Nil means untouched (Zero-Touch).
            scale = { type = "addon", default = 1.0, ui = { hidden = true } },

            -- Addon-only text styling. UI is custom (tabbed section), so hide in generic renderer.
            textHeader = { type = "addon", default = {
                fontFace = "FRIZQT__",
                style = "OUTLINE",
                colorMode = "default",
                color = { 1, 1, 1, 1 },
            }, ui = { hidden = true }},
            textQuestName = { type = "addon", default = {
                fontFace = "FRIZQT__",
                style = "OUTLINE",
                colorMode = "default",
                color = { 1, 1, 1, 1 },
            }, ui = { hidden = true }},
            textQuestObjective = { type = "addon", default = {
                fontFace = "FRIZQT__",
                style = "OUTLINE",
                colorMode = "default",
                color = { 0.8, 0.8, 0.8, 1 },
            }, ui = { hidden = true }},

            -- Dungeon Tracker sub-table (all nil = Zero-Touch)
            dungeonTracker = { type = "addon", ui = { hidden = true } },
        },
        ApplyStyling = function(componentSelf)
            InstallObjectiveTrackerHooks(componentSelf)
            InstallDungeonTrackerHooks(componentSelf)
            -- Combat-safe: RefreshOpacityState calls ApplyStyling during combat.
            -- Only enforce in-combat opacity during combat; avoid applying full styling.
            ApplyObjectiveTrackerCombatOpacity(componentSelf)
            if PlayerInCombat() then
                return
            end

            ApplyObjectiveTrackerStylingAll(componentSelf)
        end,
    })

    self:RegisterComponent(objectiveTracker)
end, "objectiveTracker")



