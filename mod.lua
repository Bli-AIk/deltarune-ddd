function Mod:init()
    Game:registerEvent("squeak", function(data)
        return Squeak(data.x, data.y, {data.width, data.height, data.polygon})
    end)
    print(Game:loc("Loaded [var:name]!", "mod.loaded", {name = self.info.name}))
end
