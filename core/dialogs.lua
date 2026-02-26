-- dialogs.lua - Base dialog module for Scoot
-- The TUI Dialog.lua wraps these methods when the v2 UI is active
local addonName, addon = ...

addon.Dialogs = {}
addon.Dialogs._registry = {}

function addon.Dialogs:Register(name, definition)
    if name and definition then
        self._registry[name] = definition
    end
end

function addon.Dialogs:Show(name, options)
    -- Base implementation - will be overridden by Dialog.lua
    -- If TUI isn't loaded yet, this provides a fallback
    options = options or {}
    local def = self._registry[name] or {}

    local text = options.text or def.text or "Dialog"
    local formatArgs = options.formatArgs or def.formatArgs
    if formatArgs and type(formatArgs) == "table" and #formatArgs > 0 then
        text = string.format(text, unpack(formatArgs))
    end

    -- Use StaticPopup as fallback
    StaticPopupDialogs["SCOOT_FALLBACK"] = {
        text = text,
        button1 = options.acceptText or def.acceptText or OKAY,
        button2 = options.cancelText or def.cancelText or CANCEL,
        hasEditBox = options.hasEditBox or def.hasEditBox,
        maxLetters = options.maxLetters or def.maxLetters or 32,
        OnAccept = function(self, data)
            local editText = self.editBox and self.editBox:GetText()
            if options.onAccept then
                options.onAccept(data, editText)
            end
        end,
        OnCancel = function(self, data)
            if options.onCancel then
                options.onCancel(data)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("SCOOT_FALLBACK", nil, nil, options.data)
end

function addon.Dialogs:Confirm(message, onAccept, onCancel)
    return self:Show(nil, {
        text = message,
        onAccept = onAccept,
        onCancel = onCancel,
    })
end

function addon.Dialogs:Info(message, onDismiss)
    return self:Show(nil, {
        text = message,
        onAccept = onDismiss,
        infoOnly = true,
    })
end

function addon.Dialogs:Hide()
    StaticPopup_Hide("SCOOT_FALLBACK")
end
