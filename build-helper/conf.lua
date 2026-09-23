-- Headless: the build helper only patches files and writes zips.
function love.conf(t)
    t.window = false
    t.modules.graphics = false
    t.modules.audio = false
    t.modules.video = false
    t.modules.joystick = false
    t.modules.physics = false
end
