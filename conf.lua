function love.conf(t)
    t.title = "EMDR3"
    t.version = "11.5"

    t.window.width = 1280
    t.window.height = 720
    t.window.vsync = 1
    t.window.resizable = false

    t.modules.graphics = true
    t.modules.keyboard = true
    t.modules.audio = true
    t.modules.mouse = true
    t.modules.timer = true

    t.modules.thread = true

    t.modules.joystick = false
    t.modules.physics = false
    t.modules.touch = false
    t.modules.video = false
end
