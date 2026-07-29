function Mod:init()
    print(Game:locText("Loaded [var:name]!", {name = self.info.name}))

    if os.getenv("KRISTAL_MOD_SMOKE") == "1" then
        print("KRISTAL_MOD_SMOKE=PASS")
        love.event.quit()
    end
end
