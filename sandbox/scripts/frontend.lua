-- The game's own menus: a Sandbox Mode button on the main menu under Prophecy Mode, and the cat choice it
-- leads to. The button is one more of the main menu's own buttons (WBP_GuiButtonMenu_C), in its column
-- and its keyboard and controller navigation. The game doesn't tell a screen about a button it didn't
-- make, so the press is read here: Enter or the controller's A while the button has the focus, or a click.
-- Pressing it opens the same cat choice Prophecy Mode does, with `state.mode` set to "sandbox": an empty
-- slot there makes a sandbox cat. A cat stays what it was made as, whichever button led to it, and the cat
-- choice says which cats are sandbox cats.
return function(state, Reg)
    local LABEL = "Sandbox Mode"
    local MENU, SELECT = "WBP_GuiScreenMainMenu_C", "WBP_GuiScreenSelectYourCat_C"

    local button, menuScreen     -- our button, and the main menu it's in
    local wasDown, opening = false, false

    local function shows(w)
        if not Game.valid(w) then return false end
        local ok, yes = pcall(function() return w:IsVisible() and w:IsInViewport() end)
        return ok and yes == true
    end

    -- A screen of the game's that's up now. A closed one lingers, so the one found must be showing.
    local function screen(class)
        local s = Game.find(class)
        if shows(s) then return s end
        return nil
    end

    local function setText(w, text)
        pcall(function() w.Text = FText(text) end)
        for _, n in ipairs({ "mcGuiTextNormal", "mcGuiTextSelected", "mcGuiTextDisabled", "mcGuiTextPressed", "mcGuiTextOver" }) do
            local t = Game.get(w, n)
            if Game.valid(t) then pcall(function() t:SetText(FText(text)) end) end
        end
    end

    local function padding(slot)
        local p = slot.Padding
        return { Left = p.Left, Top = p.Top, Right = p.Right, Bottom = p.Bottom }
    end

    -- The button goes in the column under Prophecy Mode: the column (a vertical box) can only add at the
    -- end, so the buttons after Prophecy come out and go back in after ours, each with its own spacing.
    local function addButton(s)
        local prophecy = Game.get(s, "mcGuiButtonProphecy")
        if not Game.valid(prophecy) then return nil end
        local box = prophecy:GetParent()
        local lib = Game.object("/Script/UMG.Default__WidgetBlueprintLibrary")
        local pc = Game.controller()
        if not (Game.valid(box) and lib and pc) then return nil end
        local ok, w = pcall(function() return lib:Create(pc, prophecy:GetClass(), pc) end)
        if not ok or not Game.valid(w) then
            MOD.log("couldn't make the main menu's button: %s", tostring(w))
            return nil
        end
        Game.set(w, "ParentScreen", s)
        setText(w, LABEL)

        local after, seen = {}, false
        for i = 0, box:GetChildrenCount() - 1 do
            local c = box:GetChildAt(i)
            if seen then
                local sl = c.Slot
                after[#after + 1] = { w = c, pad = padding(sl), h = sl.HorizontalAlignment, v = sl.VerticalAlignment }
            elseif Game.name(c) == "mcGuiButtonProphecy" then
                seen = true
            end
        end
        local function put(c, pad, h, v)
            local sl = box:AddChildToVerticalBox(c)
            sl:SetPadding(pad)
            sl:SetHorizontalAlignment(h)
            sl:SetVerticalAlignment(v)
        end
        for _, a in ipairs(after) do box:RemoveChild(a.w) end
        local ps = prophecy.Slot
        put(w, padding(ps), ps.HorizontalAlignment, ps.VerticalAlignment)
        for _, a in ipairs(after) do put(a.w, a.pad, a.h, a.v) end

        -- The keyboard and controller go down the screen's navigation list, so ours goes in after Prophecy.
        local list = Game.get(s, "NavControls.ControlsNavigation")
        if list then
            local order = {}
            for _, c in ipairs(Game.list(list)) do
                order[#order + 1] = c
                if Game.name(c) == "mcGuiButtonProphecy" then order[#order + 1] = w end
            end
            for i, c in ipairs(order) do list[i] = c end
        end
        return w
    end

    local function open(s)
        local prophecy = Game.get(s, "mcGuiButtonProphecy")
        if not Game.valid(prophecy) then return end
        state.mode = "sandbox"
        MOD.log("Sandbox Mode: choosing a cat")
        -- What Prophecy Mode does: the cat choice. The press is the game's own, so it's heard (below) and
        -- would say "prophecy"; `opening` keeps the mode.
        opening = true
        Game.call(s, "OnUIPress", prophecy)
        Game.call(s, "OnUIRelease", prophecy)
        opening = false
    end

    -- The game's own presses. Prophecy Mode is the way out of sandbox mode.
    Game.hook("/Script/SwtEngine.SwtScreen:OnUIPress", function(s, b)
        if opening or not Game.valid(b) then return end
        if Game.name(b) == "mcGuiButtonProphecy" and Game.className(s) == MENU then
            if state.mode == "sandbox" then MOD.log("Prophecy Mode: the story again") end
            state.mode = "prophecy"
        end
    end)

    -- Which slot was chosen: the game tells the quest manager when a cat is picked (and as the game starts,
    -- the slot picked last time). Whether it was empty then says whether a new cat is being made.
    Game.hook("/Script/SwtQuest.QuestManager:OnCharacterSlot", function(_, slot)
        if type(slot) ~= "number" then return end
        state.slot = slot
        state.slotEmpty = Reg.saved(slot) == nil
    end)

    -- The main menu: put the button in when a new menu comes up, and watch for its press.
    Game.onFrame(function()
        local s = screen(MENU)
        if not s then
            menuScreen = nil
            return
        end
        if menuScreen == nil or not Game.valid(button) or Game.fullName(menuScreen) ~= Game.fullName(s) then
            -- A new main menu: back from the game, or the first. Nothing is chosen yet.
            menuScreen = s
            button = addButton(s)
            wasDown = false
            if state.mode ~= nil and not screen(SELECT) then state.mode = nil end
            if not button then return end
        end
        if screen(SELECT) then return end
        local current = Game.get(s, "NavControls.CurrentControl")
        local focused = Game.valid(current) and Game.name(current) == Game.name(button)
        local pressed = focused and (Game.pressed("Enter") or Game.pressed("Gamepad_FaceButton_Bottom"))
        -- A click: the button underneath the picture was held down and let go with the mouse on it.
        local col = Game.get(button, "mcGuiButtonCollision")
        if Game.valid(col) then
            local ok, down = pcall(function() return col:IsPressed() end)
            down = ok and down == true
            if wasDown and not down then
                local okH, over = pcall(function() return col:IsHovered() end)
                if okH and over then pressed = true end
            end
            wasDown = down
        end
        if pressed then open(s) end
    end)

    -- The cat choice: in sandbox mode its title says so; in either mode, a sandbox cat's line under its
    -- name says "Sandbox" where a story cat's says how far its Clan's prophecy has got.
    local TITLE = "Sandbox: Select Your Cat"
    local SANDBOX_LINE = "Sandbox"
    local shownTitle, pruned = nil, false
    Game.every(0.1, function()
        local s = screen(SELECT)
        if not s then
            shownTitle, pruned = nil, false
            return
        end
        if not pruned then
            pruned = true
            pcall(Reg.prune)
        end
        local title = Game.get(s, "mcGuiTitle")
        if state.mode == "sandbox" and Game.valid(title) and shownTitle ~= TITLE then
            title:SetText(FText(TITLE))
            shownTitle = TITLE
        end
        -- The cat the choice is on: mcGuiButtonCat1 to 9 are slots 0 to 8.
        local current = Game.get(s, "CurrentNav.CurrentControl")
        local n = Game.valid(current) and tonumber(Game.name(current):match("^mcGuiButtonCat(%d)$"))
        if n and Reg.find(n - 1) then
            local line = Game.get(s, "mcGuiInfo2")
            if Game.valid(line) and Game.str(line:GetText()) ~= SANDBOX_LINE then line:SetText(FText(SANDBOX_LINE)) end
        end
    end)
end
