local menu = {}

local options = { "Start Session", "Quit" }
local selected = 1

function menu.load()
    selected = 1
end

function menu.update(dt)
end

function menu.draw()
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()

    love.graphics.setBackgroundColor(0.08, 0.08, 0.1)
    love.graphics.clear()

    -- Title
    love.graphics.setColor(1, 1, 1)
    local titleFont = love.graphics.newFont(64)
    love.graphics.setFont(titleFont)
    local titleText = "EMDR3"
    local titleW = titleFont:getWidth(titleText)
    love.graphics.print(titleText, (W - titleW) / 2, H * 0.25)

    -- Subtitle
    local subFont = love.graphics.newFont(18)
    love.graphics.setFont(subFont)
    love.graphics.setColor(0.6, 0.6, 0.7)
    local subText = "Eye Movement Desensitisation & Reprocessing"
    local subW = subFont:getWidth(subText)
    love.graphics.print(subText, (W - subW) / 2, H * 0.25 + 74)

    -- Menu options
    local menuFont = love.graphics.newFont(28)
    love.graphics.setFont(menuFont)
    local startY = H * 0.55

    for i, option in ipairs(options) do
        local optW = menuFont:getWidth(option)
        local x = (W - optW) / 2
        local y = startY + (i - 1) * 56

        if i == selected then
            love.graphics.setColor(1, 1, 1)
            -- Selection indicator
            love.graphics.print("> " .. option .. " <", x - menuFont:getWidth("> "), y)
        else
            love.graphics.setColor(0.5, 0.5, 0.6)
            love.graphics.print(option, x, y)
        end
    end

    -- Controls hint
    local hintFont = love.graphics.newFont(14)
    love.graphics.setFont(hintFont)
    love.graphics.setColor(0.35, 0.35, 0.45)
    local hintText = "↑↓ Navigate   Enter Select"
    local hintW = hintFont:getWidth(hintText)
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
            switchScreen("oscillating")
        elseif selected == 2 then
            love.event.quit()
        end
    elseif k == "escape" or k == "q" then
        love.event.quit()
    end
end

return menu
