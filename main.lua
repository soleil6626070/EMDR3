local screens = {
    menu  = require("screens.menu"),
    cycle = require("screens.cycle"),
}

local currentScreen = "menu"

function switchScreen(name)
    currentScreen = name
    if screens[name].load then
        screens[name].load()
    end
end

function love.load()
    screens[currentScreen].load()
end

function love.update(dt)
    screens[currentScreen].update(dt)
end

function love.draw()
    screens[currentScreen].draw()
end

function love.keypressed(k)
    screens[currentScreen].keypressed(k)
end
