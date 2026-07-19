-- screens/ident_prelude.lua
-- Entry of the identification flow: plays the cached settling intro, then the
-- image prelude ("with your eyes closed, or a soft gaze, cast your mind
-- back..."), then hands over to the live agent screen. No marker exists yet —
-- Escape here abandons cleanly (the agent call is not resumable anyway).

local identification = require("modules.identification")

local ident_prelude = {}

local SETTLING_DIR = "resources/audio/ident/settling"
local PRELUDE_DIR  = "resources/audio/ident/image_prelude"

local phase    -- "settling" | "image_prelude"
local source
local fontBody, fontHint
local bgShader, shaderTime, spinTime

local colour1 = {0.15, 0.35, 0.55, 1.0}
local colour2 = {0.05, 0.20, 0.40, 1.0}
local colour3 = {0.25, 0.50, 0.65, 1.0}

local PHASE_TEXT = {
    settling      = "Take a moment to settle.",
    image_prelude = "With your eyes closed, or a soft gaze,\ncast your mind back to the memory.",
}

local function playFromDir(dir)
    local files = {}
    for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
        if name:match("%.mp3$") then files[#files + 1] = dir .. "/" .. name end
    end
    if #files == 0 then return nil end
    local s = love.audio.newSource(files[love.math.random(#files)], "static")
    s:play()
    return s
end

local function startImagePrelude()
    phase = "image_prelude"
    source = playFromDir(PRELUDE_DIR)
    -- Missing audio: hold the text briefly is pointless — go to the agent
    if not source then switchScreen("ident_agent") end
end

function ident_prelude.load()
    phase = "settling"
    fontBody = love.graphics.newFont(26)
    fontHint = love.graphics.newFont(14)
    bgShader = love.graphics.newShader("resources/shaders/background.fs")
    shaderTime = 0
    spinTime = 0

    source = playFromDir(SETTLING_DIR)
    if not source then startImagePrelude() end
end

function ident_prelude.update(dt)
    shaderTime = shaderTime + dt
    spinTime   = spinTime + dt * 0.1

    if source and not source:isPlaying() then
        if phase == "settling" then
            startImagePrelude()
        else
            source = nil
            switchScreen("ident_agent")
        end
    end
end

function ident_prelude.draw()
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()

    bgShader:send("time", shaderTime)
    bgShader:send("spin_time", spinTime)
    bgShader:send("colour_1", colour1)
    bgShader:send("colour_2", colour2)
    bgShader:send("colour_3", colour3)
    bgShader:send("contrast", 1.0)
    bgShader:send("spin_amount", 0.0)
    love.graphics.setShader(bgShader)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, W, H)
    love.graphics.setShader()

    love.graphics.setFont(fontBody)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(PHASE_TEXT[phase] or "", W * 0.15, H * 0.4, W * 0.7, "center")

    love.graphics.setFont(fontHint)
    love.graphics.setColor(0.75, 0.82, 0.95, 0.8)
    local hint = "Space/Enter — skip   Escape — back to menu"
    love.graphics.print(hint, (W - fontHint:getWidth(hint)) / 2, H - 36)
end

function ident_prelude.keypressed(k)
    if k == "escape" then
        if source then source:stop() end
        identification.reset()
        switchScreen("menu")
    elseif k == "space" or k == "return" or k == "kpenter" then
        if source then source:stop() end
        if phase == "settling" then
            startImagePrelude()
        else
            switchScreen("ident_agent")
        end
    end
end

return ident_prelude
