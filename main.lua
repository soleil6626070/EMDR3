-- Add lib/ to module search paths (for https.so, ssl.so, websocket.lua, etc.)
local _src = love.filesystem.getSource()
package.cpath = _src .. "/lib/?.so;" .. _src .. "/lib/?.dll;" .. package.cpath
package.path  = _src .. "/lib/?.lua;" .. _src .. "/lib/?/init.lua;" .. package.path

local config        = require("config")
local tts           = require("modules.tts")
local transcription = require("modules.transcription")
local agent         = require("modules.agent")
local cue_in        = require("modules.cue_in")
local llm           = require("modules.llm")

local makeRatingScreen = require("screens.rating")
local identification   = require("modules.identification")

local screens = {
    menu                    = require("screens.menu"),
    target_identification   = require("screens.target_identification"),
    target_select           = require("screens.target_select"),
    cue_in_review           = require("screens.cue_in_review"),
    pre_rating              = makeRatingScreen("pre"),
    oscillating             = require("screens.oscillating"),
    noticed                 = require("screens.noticed"),
    notice_that             = require("screens.notice_that"),
    post_rating             = makeRatingScreen("post"),
    ident_prelude           = require("screens.ident_prelude"),
    ident_agent             = require("screens.ident_agent"),
    ident_stage             = require("screens.ident_stage"),
    ident_voc               = makeRatingScreen(identification.ratingOpts("voc")),
    ident_sud               = makeRatingScreen(identification.ratingOpts("sud")),
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
    cue_in.init(config)
    llm.init(config)
    screens[currentScreen].load()
end

function love.update(dt)
    tts.update()
    transcription.update()
    agent.update()
    cue_in.update()
    llm.update()
    screens[currentScreen].update(dt)
end

function love.draw()
    screens[currentScreen].draw()
end

function love.keypressed(k)
    screens[currentScreen].keypressed(k)
end

function love.textinput(t)
    if screens[currentScreen].textinput then
        screens[currentScreen].textinput(t)
    end
end

function love.quit()
    tts.shutdown()
    transcription.shutdown()
    agent.shutdown()
    cue_in.shutdown()
    llm.shutdown()
end
