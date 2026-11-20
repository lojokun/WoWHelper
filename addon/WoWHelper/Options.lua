-- WoWHelper: options panel in Game Menu > Options > AddOns.
-- Built on a canvas with the addon's own widgets so it does not depend on
-- Blizzard setting templates that may differ between client builds.
local _, ns = ...
local WH = ns.WH

local function checkbox(parent, label, get, set)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(24, 24)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb.label:SetText(label)
    cb:SetScript("OnShow", function(self) self:SetChecked(get()) end)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    return cb
end

local function stepper(parent, label, get, set, step, fmt)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(300, 24)
    local minus = WH.FlatButton(f, "-", 22, 20)
    minus:SetPoint("LEFT")
    local value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    value:SetPoint("LEFT", minus, "RIGHT", 6, 0)
    value:SetWidth(40)
    local plus = WH.FlatButton(f, "+", 22, 20)
    plus:SetPoint("LEFT", value, "RIGHT", 6, 0)
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", plus, "RIGHT", 8, 0)
    text:SetText(label)
    local function refresh() value:SetText(fmt:format(get())) end
    minus:SetScript("OnClick", function() set(get() - step) refresh() end)
    plus:SetScript("OnClick", function() set(get() + step) refresh() end)
    f:SetScript("OnShow", refresh)
    return f
end

function WH:CreateOptions()
    local db = self.db
    local p = CreateFrame("Frame")
    p.name = "WoWHelper"

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("WoWHelper " .. self.version)
    local sub = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Leveling guide window. Type /wh for commands.")

    local y = -70
    local function place(w, h)
        w:SetPoint("TOPLEFT", 16, y)
        y = y - (h or 30)
    end

    place(checkbox(p, "Lock window position", function() return db.locked end,
        function(v) WH:SetLocked(v, true) end))
    place(checkbox(p, "Place a waypoint for each step", function() return db.autoWaypoint end,
        function(v) db.autoWaypoint = v end))
    place(checkbox(p, "Track the waypoint on screen (super-track)", function() return db.superTrack end,
        function(v) db.superTrack = v end))
    place(checkbox(p, "Show coordinates", function() return db.showCoords end,
        function(v) db.showCoords = v WH:UpdateUI() end))
    place(checkbox(p, "Show step notes", function() return db.showNotes end,
        function(v) db.showNotes = v WH:UpdateUI() end))
    place(checkbox(p, "Show the window", function() return not db.hidden end,
        function(v) WH:SetShown(v) end))
    y = y - 10
    place(stepper(p, "Steps shown", function() return db.stepsShown end,
        function(v) db.stepsShown = math.max(1, math.min(10, v)) WH:UpdateUI() end, 1, "%d"))
    place(stepper(p, "Window scale", function() return db.scale end,
        function(v) WH:SetScale(math.floor(v * 10 + 0.5) / 10) end, 0.1, "%.1f"))
    place(stepper(p, "Window width", function() return db.width end,
        function(v) db.width = math.max(240, math.min(800, v)) WH:UpdateUI() end, 20, "%d"))
    y = y - 10
    local reset = WH.FlatButton(p, "Reset position (above chat)", 200, 22)
    place(reset)
    reset:SetScript("OnClick", function() WH:ResetPosition() end)
    local guides = WH.FlatButton(p, "Choose a guide...", 200, 22)
    place(guides)
    guides:SetScript("OnClick", function() WH:ToggleGuidePicker() end)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, p, "WoWHelper")
        if ok and category then
            pcall(Settings.RegisterAddOnCategory, category)
            self.settingsCategory = category
        end
    end
    self.optionsPanel = p
end

function WH:OpenOptions()
    if self.settingsCategory and Settings and Settings.OpenToCategory then
        local id = self.settingsCategory.GetID and self.settingsCategory:GetID() or self.settingsCategory.ID
        if pcall(Settings.OpenToCategory, id) then return end
    end
    self:Print("Open Game Menu > Options > AddOns > WoWHelper.")
end
