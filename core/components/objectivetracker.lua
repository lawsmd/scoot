local addonName, addon = ...

-- Objective Tracker Component
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

local function SafeSetFont(fs, face, size, flags)
    if not (fs and fs.SetFont) then return false end
    if not face or not size then return false end

    -- Capture the original FontObject BEFORE calling SetFont (which detaches the fontstring).
    -- This allows us to read the live text size during Edit Mode preview.
    local state = getState(fs)
    if state and not state.originalFontObject then
        local ok, fontObj = pcall(fs.GetFontObject, fs)
        if ok and fontObj then
            state.originalFontObject = fontObj
            _capturedFontObjects[fontObj] = true
        end
    end

    return pcall(fs.SetFont, fs, face, size, flags)
end

-- Read the live text size from a captured FontObject.
-- This is used during Edit Mode live preview when GetSetting returns stale persisted values.
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
    local mgr = _G.EditModeManagerFrame
    if not mgr then return false end
    if mgr.IsEditModeActive then
        local ok, active = pcall(mgr.IsEditModeActive, mgr)
        if ok then return active == true end
    end
    if mgr.IsShown then
        local ok, shown = pcall(mgr.IsShown, mgr)
        if ok then return shown == true end
    end
    return false
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
    local flags = cfg.style or curFlags or nil
    if face then
        SafeSetFont(fs, face, size, flags)
    elseif cfg.style ~= nil then
        -- If only style is specified, keep existing face and just update flags.
        local curFace = select(1, GetCurrentFont(fs))
        if curFace then
            SafeSetFont(fs, curFace, size, flags)
        end
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

    -- Blizzard hover logic changes quest name colors by calling SetTextColor; re-apply ours after.
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
    if self._ScootDBProxy and self.db == self._ScootDBProxy then
        return
    end

    local db = self.db
    if type(db) ~= "table" then return end

    -- Only style text types that are explicitly present in the DB.
    local headerCfg = type(db.textHeader) == "table" and db.textHeader or nil
    local questNameCfg = type(db.textQuestName) == "table" and db.textQuestName or nil
    local objectiveCfg = type(db.textQuestObjective) == "table" and db.textQuestObjective or nil
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
    -- Quest module header (per docs: `QuestObjectiveTracker.Header.Background`)
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
    if self._ScootDBProxy and self.db == self._ScootDBProxy then
        return
    end

    local db = self.db
    if type(db) ~= "table" then return end

    -- Only act when the user has explicitly configured this section.
    -- (nil means "untouched" to preserve Zero‑Touch behavior.)
    local hide = db.hideHeaderBackgrounds
    local tintEnable = db.tintHeaderBackgroundEnable
    local tintColor = db.tintHeaderBackgroundColor
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

local function PlayerInCombat()
    if addon and addon.ComponentsUtil and type(addon.ComponentsUtil.PlayerInCombat) == "function" then
        return addon.ComponentsUtil.PlayerInCombat()
    end
    if InCombatLockdown() then
        return true
    end
    return UnitAffectingCombat("player") and true or false
end

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

local function ApplyObjectiveTrackerCombatOpacity(self)
    local tracker = _G.ObjectiveTrackerFrame
    if not tracker then return end

    -- Zero‑Touch: if still on proxy DB, do nothing.
    if self._ScootDBProxy and self.db == self._ScootDBProxy then
        return
    end

    local db = self.db
    if type(db) ~= "table" then return end

    local inCombat = PlayerInCombat()
    local inInstance = PlayerInDungeonOrRaidInstance()
    local configured = ClampPercent0To100(db.opacityInInstanceCombat)
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
    if self._ScootDBProxy and self.db == self._ScootDBProxy then return end
    local db = self.db
    if type(db) ~= "table" then return end
    local scale = tonumber(db.scale)
    if not scale then return end  -- nil = untouched (Zero-Touch)
    if scale < 0.5 then scale = 0.5 elseif scale > 1.5 then scale = 1.5 end
    pcall(tracker.SetScale, tracker, scale)
end

local function ApplyObjectiveTrackerStylingAll(self)
    ApplyObjectiveTrackerHeaderBackgroundStyling(self)
    ApplyObjectiveTrackerTextStyling(self)
    ApplyObjectiveTrackerScale(self)
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
    -- This hook fires for BOTH:
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
        },
        ApplyStyling = function(componentSelf)
            InstallObjectiveTrackerHooks(componentSelf)
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
end)



