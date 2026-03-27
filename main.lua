-- Add lib/ to module search paths (for https.so, ssl.so, websocket.lua, etc.)
local _src = love.filesystem.getSource()
package.cpath = _src .. "/lib/?.so;" .. _src .. "/lib/?.dll;" .. package.cpath
package.path  = _src .. "/lib/?.lua;" .. _src .. "/lib/?/init.lua;" .. package.path

local config        = require("config")
local tts           = require("modules.tts")
local transcription = require("modules.transcription")
local agent         = require("modules.agent")

local screens = {
    menu                    = require("screens.menu"),
    target_identification   = require("screens.target_identification"),
    oscillating             = require("screens.oscillating"),
    noticed                 = require("screens.noticed"),
    notice_that             = require("screens.notice_that"),
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
    transcription.init(config)
    agent.init(config)
    screens[currentScreen].load()
end

function love.update(dt)
    tts.update()
    transcription.update()
    agent.update()
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
    transcription.shutdown()
    agent.shutdown()
end
