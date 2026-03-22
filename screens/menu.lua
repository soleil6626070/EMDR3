local menu = {}

local options = { "Start Session", "Quit" }
local selected = 1

local bgShader
local time = 0
local spinTime = 0
local fontTitle, fontSub, fontMenu, fontHint

-- Calm blue/teal palette for the background
local colour1 = {0.15, 0.35, 0.55, 1.0}
local colour2 = {0.05, 0.20, 0.40, 1.0}
local colour3 = {0.25, 0.50, 0.65, 1.0}

function menu.load()
    selected = 1
    time = 0
    spinTime = 0
    bgShader = love.graphics.newShader("resources/shaders/background.fs")
    fontTitle = love.graphics.newFont(64)
    fontSub   = love.graphics.newFont(18)
    fontMenu  = love.graphics.newFont(28)
    fontHint  = love.graphics.newFont(14)
end

-- Dictates menu background movement speed
function menu.update(dt)
    time = time + dt 
    spinTime = spinTime + dt * 0.1
end

function menu.draw()
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()

    -- Draw animated background shader
    bgShader:send("time", time)
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

    -- Title
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(fontTitle)
    local titleText = "EMDR3"
    local titleW = fontTitle:getWidth(titleText)
    love.graphics.print(titleText, (W - titleW) / 2, H * 0.25)

    -- Subtitle
    love.graphics.setFont(fontSub)
    love.graphics.setColor(0.85, 0.90, 1.0)
    local subText = "Eye Movement Desensitisation & Reprocessing"
    local subW = fontSub:getWidth(subText)
    love.graphics.print(subText, (W - subW) / 2, H * 0.25 + 74)

    -- Menu options
    love.graphics.setFont(fontMenu)
    local startY = H * 0.55

    for i, option in ipairs(options) do
        local optW = fontMenu:getWidth(option)
        local x = (W - optW) / 2
        local y = startY + (i - 1) * 56

        if i == selected then
            love.graphics.setColor(1, 1, 1)
            love.graphics.print("> " .. option .. " <", x - fontMenu:getWidth("> "), y)
        else
            love.graphics.setColor(0.65, 0.75, 0.90)
            love.graphics.print(option, x, y)
        end
    end

    -- Controls hint
    love.graphics.setFont(fontHint)
    love.graphics.setColor(0.55, 0.65, 0.80)
    local hintText = "↑↓ Navigate   Enter Select"
    local hintW = fontHint:getWidth(hintText)
    love.graphics.print(hintText, (W - hintW) / 2, H - 40)
end

function menu.keypressed(k)
    if k == "up" then
        selected = selected - 1
        if selected < 1 then selected = #options end
    elseif k == "down" then
        selected = selected + 1
        if selected > #options then selected = 1 end
    elseif k == "return" or k == "kpenter" then
        if selected == 1 then
            require("modules.session").start(require("config").cycles)
            switchScreen("oscillating")
        elseif selected == 2 then
            love.event.quit()
        end
    elseif k == "escape" or k == "q" then
        love.event.quit()
    end
end

return menu
