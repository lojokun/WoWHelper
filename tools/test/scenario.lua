-- Test scenario run by tools/test/run_tests.py after the addon is loaded.
local WH = WoWHelper
local passed, failed = 0, 0

local function check(cond, msg)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. msg)
    end
end

local function cur()
    local s, i = WH:GetCurrentStep()
    return s, i
end

-- JSON decoder
do
    local J = ADDON_NS.JSON
    local v = J.decode('{"a":[1,2.5,-3e2,true,false,null,"x\\u00e9\\n\\"q\\""],"b":{"c":{}}}')
    check(v and v.a[1] == 1 and v.a[2] == 2.5 and v.a[3] == -300, "json numbers")
    check(v and v.a[4] == true and v.a[5] == false and v.a[6] == nil, "json literals")
    check(v and v.a[7] == "x\195\169\n\"q\"", "json string escapes")
    check(v and type(v.b.c) == "table", "json nested objects")
    local bad, err = J.decode('{"a":1,}')
    check(bad == nil and err ~= nil, "json rejects trailing comma")
    local bad2 = J.decode('[1 2]')
    check(bad2 == nil, "json rejects missing comma")
    check(J.decode('"\\ud83d\\ude00"') == "\240\159\152\128", "json surrogate pairs")
end

-- Login
MOCK.fire("ADDON_LOADED", "WoWHelper")
MOCK.fire("PLAYER_LOGIN")
MOCK.runTimers()

check(#WH.guideOrder == 9, "9 guides loaded (got " .. #WH.guideOrder .. ")")
check(WH.char.guideId == "undead-01-tirisfal", "level 1 Undead starts in Tirisfal")
check(WH.zonesByName["Tirisfal Glades"] == 1420, "zones loaded")
check(WH:ResolveMapId("The Riverglades") == 2001, "unknown Forever zone resolved by name")
check(WH.frame ~= nil and WH.frame._shown, "window created and shown")
local p = WH.frame
check(MOCK.printed[1] == nil or not tostring(MOCK.printed[1]):find("failed"), "no load errors printed")

local s, i = cur()
check(i == 1 and s.action == "note", "step 1 is the opening note")
WH:CompleteCurrentStep()
s, i = cur()
check(s.action == "accept" and s.questId == 363, "step 2 accept Rude Awakening")
check(MOCK.waypoint and math.abs(MOCK.waypoint.x - 0.3021) < 1e-6, "waypoint placed for the step")

MOCK.accept(363, "Rude Awakening")
s = cur()
check(s.action == "turnin" and s.questId == 363, "accept advances to the turn-in")
MOCK.turnin(363)
s = cur()
check(s.action == "accept" and s.questId == 364, "turn-in advances to The Mindless Ones")

MOCK.accept(364, "The Mindless Ones")
s = cur()
check(s.questId == 3901, "next is Rattling the Rattlecages (got " .. tostring(s.quest) .. ")")

-- Picking up several quests out of order
MOCK.accept(376, "The Damned")
MOCK.accept(3901, "Rattling the Rattlecages")
MOCK.accept(1470, "Piercing the Veil")
s = cur()
check(s.action == "complete" and s.questId == 364, "all accepts done, now complete Mindless Ones")
MOCK.finish(364)
s = cur()
check(s.action == "turnin" and s.questId == 364, "objective finished -> turn in")
MOCK.turnin(364)
s = cur()
check(s.action == "accept" and s.questId == 3099, "class letter comes after The Mindless Ones; warlock gets only the Tainted Scroll (got " .. tostring(s.quest) .. ")")
MOCK.accept(3099, "Tainted Scroll")
s = cur()
check(s.action == "turnin" and s.questId == 3099, "paladin note skipped for a warlock")
MOCK.turnin(3099)
s = cur()
check(s.action == "train", "class scroll turned in -> train step (got " .. s.action .. ")")
MOCK.fire("TRAINER_CLOSED")
MOCK.runTimers()
s = cur()
check(s.action == "complete" and s.questId == 3901, "trainer closed completes the train step")

-- UI renders rows
WH:UpdateUI()
local shown = 0
for _, row in ipairs(p.rows) do if row._shown then shown = shown + 1 end end
check(shown == WH.db.stepsShown, "window shows " .. WH.db.stepsShown .. " rows (got " .. shown .. ")")
check(p.rows[1].text._text:find("Rattling the Rattlecages", 1, true) ~= nil, "first row names the quest (got " .. tostring(p.rows[1].text._text) .. ")")

-- Distance / location steps
MOCK.map, MOCK.x, MOCK.y = 1420, 0.33, 0.616
local d = WH:GetStepDistance(cur())
check(d and d < 1, "distance computed on the same map (got " .. tostring(d) .. ")")
WH:UpdateDistance()
check(p.dist._text:find("yd") ~= nil, "footer shows yards")

-- Title fallback: Forever quest with a different ID than the guide
local g = WH:GetGuide()
local rgIndex
for idx, st in ipairs(g.steps) do
    if st.action == "accept" and st.quest == "Rear Guard Patrol" then rgIndex = idx break end
end
WH.char.progress[g.id] = rgIndex
WH:Refresh()
s, i = cur()
check(s.quest == "Rear Guard Patrol", "jumped to Rear Guard Patrol")
MOCK.accept(356, "Rear Guard Patrol")
s, i = cur()
check(i > rgIndex, "accept matched by title despite a different quest ID")

-- Step back and forward
local before = i
WH:PreviousStep()
local _, back = cur()
check(back < before, "previous step goes back")
WH:CompleteCurrentStep()
local _, again = cur()
check(again >= before, "next step returns forward")

-- sethearth via event
for idx, st in ipairs(g.steps) do
    if st.action == "sethearth" then WH.char.progress[g.id] = idx break end
end
WH.holdIndex = nil
WH:Refresh()
s = cur()
check(s.action == "sethearth", "at the sethearth step")
MOCK.fire("HEARTHSTONE_BOUND")
MOCK.runTimers()
s = cur()
check(s.action ~= "sethearth", "HEARTHSTONE_BOUND completes the sethearth step")

-- level step + guide chaining
WH.char.progress[g.id] = #g.steps
MOCK.level = 12
WH:Refresh()
check(WH.char.guideId == "undead-02-silverpine", "finishing a guide moves to its 'next' guide")

-- Level-based start: /wh auto at level 29 lands in the 22-30 guide, past its level 28 checkpoint
MOCK.level = 29
WH:AutoSelectGuide()
check(WH.char.guideId == "undead-04-horde-22-30", "level 29 picks the 22-30 guide (got " .. tostring(WH.char.guideId) .. ")")
local g4 = WH.guides["undead-04-horde-22-30"]
local cp
for idx, st in ipairs(g4.steps) do if st.action == "level" and st.level == 28 then cp = idx end end
local _, i4 = cur()
check(cp and i4 > cp, "resume skips past the level 28 checkpoint (step " .. tostring(i4) .. ", checkpoint " .. tostring(cp) .. ")")

-- Resume past quests already turned in
MOCK.completed[6461] = true   -- Blood Feeders
MOCK.completed[1069] = true   -- Deepmoss Spider Eggs
MOCK.level = 22
check(WH:FindResumeStep(g4) == 4, "resume starts after the last turned-in quest (got " .. WH:FindResumeStep(g4) .. ")")

-- Optional quests not in the log are skipped
local optIdx
for idx, st in ipairs(g4.steps) do
    if st.optional and st.action == "turnin" then optIdx = idx break end
end
check(optIdx and WH:IsStepDone(g4, optIdx, true), "optional turn-in not in the log is skipped")

-- Fly step without coordinates completes on the subzone name
local flyIdx
for idx, st in ipairs(g4.steps) do
    if st.action == "fly" and not st.x and st.location == "Thunder Bluff" then flyIdx = idx break end
end
MOCK.subzone, MOCK.zoneText = "Spirit Rise", "Elwynn"
check(flyIdx and not WH:IsStepDone(g4, flyIdx, true), "fly step waits until you arrive")
MOCK.zoneText = "Thunder Bluff"
check(flyIdx and WH:IsStepDone(g4, flyIdx, true), "fly step completes on arrival")

-- Outlevel warning
WH.char.guideId = "undead-01-tirisfal"
MOCK.level = 20
local before_n = #MOCK.printed
WH:CheckOutleveled()
check(#MOCK.printed > before_n and MOCK.printed[#MOCK.printed]:find("/wh auto", 1, true), "outleveled guide prints a /wh auto hint")

-- Import
local ok = WH:ImportGuide('{"id":"test-import","title":"Test","races":["Undead"],"steps":[{"action":"note","text":"hi"},{"action":"goto","zone":"Silverpine Forest","x":10,"y":20}]}')
check(ok and WH.guides["test-import"] and WH.db.customGuides["test-import"], "import stores the guide")
check(WH.guides["test-import"].steps[2].mapId == 1421, "imported step resolves its map")
local bad, err = WH:ImportGuide('{"id":"x","title":"x","steps":[{"action":"dance"}]}')
check(bad == nil and err:find("unknown action"), "import rejects bad actions")

-- Slash commands don't error
for _, cmd in ipairs({ "", "", "lock", "unlock", "reset", "next", "prev", "guides", "import", "where", "where accept Some Quest", "waypoint", "options", "help" }) do
    local okc, e = pcall(SlashCmdList.WOWHELPER, cmd)
    check(okc, "slash '/wh " .. cmd .. "' ran (" .. tostring(e) .. ")")
end
WH:SetShown(true)

-- Position saving
p._scripts.OnDragStop(p)
check(WH.db.point and WH.db.point[1] == "BOTTOMLEFT", "drag saves a BOTTOMLEFT position")
WH:ResetPosition()
check(WH.db.point == nil, "reset clears the saved position")

-- Ticker runs
local okt, e = pcall(MOCK.ticker)
check(okt, "ticker runs (" .. tostring(e) .. ")")

-- Every guide renders every step without error
for _, id in ipairs(WH.guideOrder) do
    WH.char.guideId = id
    local gg = WH.guides[id]
    for idx = 1, #gg.steps do
        WH.char.progress[id] = idx
        local okr, er = pcall(WH.UpdateUI, WH)
        if not okr then check(false, id .. " step " .. idx .. ": " .. tostring(er)) break end
    end
end
passed = passed + 1

print(("%d passed, %d failed"):format(passed, failed))
return failed
