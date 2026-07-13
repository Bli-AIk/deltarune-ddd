return {
    -- The inclusion of the below line tells the language server that the first parameter of the cutscene is `BattleCutscene`.
    -- This allows it to fetch us useful documentation that shows all of the available cutscene functions while writing our cutscenes!

    ---@param cutscene BattleCutscene
    susie_punch = function(cutscene, battler, enemy)
        -- Open textbox and wait for completion
        cutscene:text("* Susie threw a punch at\nthe dummy.", nil, nil, {
            id = "battle_dummy_susie_punch_1"
        })

        -- Hurt the target enemy for 1 damage
        Assets.playSound("damage")
        enemy:hurt(1, battler)
        -- Wait 1 second
        cutscene:wait(1)

        -- Susie text
        cutscene:text("* You,[wait:5] uh,[wait:5] look like a weenie.[wait:5]\n* I don't like beating up\npeople like that.", "nervous_side", "susie", {
            id = "battle_dummy_susie_punch_2"
        })

        if cutscene:getCharacter("ralsei") then
            -- Ralsei text, if he's in the party
            cutscene:text("* Aww,[wait:5] Susie!", "blush_pleased", "ralsei", {
                id = "battle_dummy_susie_punch_3"
            })
        end
    end
}
