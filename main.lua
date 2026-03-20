-- Add lib/ to native module search path (for https.so)
package.cpath = love.filesystem.getSource() .. "/lib/?.so;"
            .. love.filesystem.getSource() .. "/lib/?.dll;"
            .. package.cpath

local config = require("config")
local tts    = require("modules.tts")

local screens = {
    menu        = require("screens.menu"),
    oscillating = require("screens.oscillating"),
    noticed     = require("screens.noticed"),
}

local currentScreen = "menu"

function switchScreen(name)
    currentScreen = name
    if screens[name].load then
        screens[name].load()
    end
end

function love.load()
    tts.init(config)
    screens[currentScreen].load()
end

function love.update(dt)
    tts.update()
    screens[currentScreen].update(dt)
end

function love.draw()
    screens[currentScreen].draw()
end

function love.keypressed(k)
    screens[currentScreen].keypressed(k)
end

function love.quit()
    tts.shutdown()
end
