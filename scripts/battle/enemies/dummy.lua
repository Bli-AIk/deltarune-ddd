local Dummy, super = Class(EnemyBattler)

function Dummy:init()
    super.init(self)

    self:applyLocalization()
    -- Sets the actor, which handles the enemy's sprites (see scripts/data/actors/dummy.lua)
    self:setActor("dummy")

    -- Enemy health
    self.max_health = 450
    self.health = 450
    -- Enemy attack (determines bullet damage)
    self.attack = 4
    -- Enemy defense (usually 0)
    self.defense = 0
    -- Enemy reward
    self.money = 100

    -- Mercy given when sparing this enemy before its spareable (20% for basic enemies)
    self.spare_points = 20

    -- List of possible wave ids, randomly picked each turn
    self.waves = {
        "basic",
        "aiming",
        "movingarena"
    }

    -- Dialogue randomly displayed in the enemy's speech bubble
    self.dialogue = {
        "..."
    }

    -- Register act called "Smile"
    self:registerAct(self.act_smile)
    -- Register party act with Ralsei called "Tell Story"
    -- (second argument is description, usually empty)
    self:registerAct(self.act_tell_story, "", {"ralsei"})
end

function Dummy:applyLocalization(update_acts)
    local old_check = self.act_check
    local old_smile = self.act_smile
    local old_tell_story = self.act_tell_story

    -- Enemy name
    self.name = Game:loc("Dummy", "enemy_dummy_name")
    -- Check text (automatically has "ENEMY NAME - " at the start)
    self.check = Game:loc("AT 4 DF 0\n* Cotton heart and button eye\n* Looks just like a fluffy guy.", "enemy_dummy_check")

    -- Text randomly displayed at the bottom of the screen each turn
    self.text = {
        Game:loc("* The dummy gives you a soft\nsmile.", "enemy_dummy_turn_1"),
        Game:loc("* The power of fluffy boys is\nin the air.", "enemy_dummy_turn_2"),
        Game:loc("* Smells like cardboard.", "enemy_dummy_turn_3"),
    }
    -- Text displayed at the bottom of the screen when the enemy has low health
    self.low_health_text = Game:loc("* The dummy looks like it's\nabout to fall over.", "enemy_dummy_low_health")

    self.act_check = Game:loc("Check", "act_check")
    self.act_smile = Game:loc("Smile", "act_dummy_smile")
    self.act_tell_story = Game:loc("Tell Story", "act_dummy_tell_story")

    if self.acts and self.acts[1] then
        self.acts[1].name = self.act_check
    end

    if update_acts then
        for _, act in ipairs(self.acts or {}) do
            if act.name == old_check then
                act.name = self.act_check
            elseif act.name == old_smile then
                act.name = self.act_smile
            elseif act.name == old_tell_story then
                act.name = self.act_tell_story
            end
        end
    end
end

function Dummy:onAct(battler, name)
    if name == self.act_check then
        return super.onAct(self, battler, "Check")

    elseif name == self.act_smile then
        -- Give the enemy 100% mercy
        self:addMercy(100)
        -- Change this enemy's dialogue for 1 turn
        self.dialogue_override = "... ^^"
        -- Act text (since it's a list, multiple textboxes)
        return {
            Game:loc("* You smile.[wait:5]\n* The dummy smiles back.", "act_dummy_smile_1"),
            Game:loc("* It seems the dummy just wanted\nto see you happy.", "act_dummy_smile_2")
        }

    elseif name == self.act_tell_story then
        -- Loop through all enemies
        for _, enemy in ipairs(Game.battle.enemies) do
            -- Make the enemy tired
            enemy:setTired(true)
        end
        return Game:loc("* You and Ralsei told the dummy\na bedtime story.\n* The enemies became [color:blue]TIRED[color:reset]...", "act_dummy_tell_story_text")

    elseif name == "Standard" then --X-Action
        -- Give the enemy 50% mercy
        self:addMercy(50)
        if battler.chara.id == "ralsei" then
            -- R-Action text
            return Game:loc("* Ralsei bowed politely.\n* The dummy spiritually bowed\nin return.", "act_dummy_ralsei_standard")
        elseif battler.chara.id == "susie" then
            -- S-Action: start a cutscene (see scripts/battle/cutscenes/dummy.lua)
            Game.battle:startActCutscene("dummy", "susie_punch")
            return
        else
            -- Text for any other character (like Noelle)
            return Game:loc("* [var:name] straightened the\ndummy's hat.", "act_dummy_other_standard", {
                name = battler.chara:getName()
            })
        end
    end

    -- If the act is none of the above, run the base onAct function
    -- (this handles the Check act)
    return super.onAct(self, battler, name)
end

return Dummy
