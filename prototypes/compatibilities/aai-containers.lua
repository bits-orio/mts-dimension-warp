local logistic_chests = {
    data.raw['logistic-container']['dw-logistic-input'],
    data.raw['logistic-container']['dw-logistic-output'],
}
local yumako_chest = {
    data.raw['logistic-container']['dw-crane-yumako-seed-input'],
    data.raw['logistic-container']['dw-crane-yumako-output'],
}
local jelly_chest = {
    data.raw['logistic-container']['dw-crane-jellynut-seed-input'],
    data.raw['logistic-container']['dw-crane-jellynut-output'],
}

-- The robot door animation: Factorio 2.1 moved LogisticContainerPrototype's
-- animation into robot_door; 2.0 kept it on the container.
local function robot_animation(chest)
    return (chest.robot_door and chest.robot_door.animation) or chest.animation
end

-- Darken every tinted layer; alpha is given in both colour scales a tint can use.
local function tint_layers(chest, alpha_255, alpha_1)
    local animation = robot_animation(chest)
    if not (animation and animation.layers) then return nil end
    for _, layer in pairs(animation.layers) do
        if layer.tint then
            local color = util.multiply_color(layer.tint, 0.55)
            layer.tint = {r=color[1], g=color[2], b=color[3], a=(color[1] > 1 and alpha_255 or alpha_1)}
        end
    end
    return animation
end

for _, chest in pairs(logistic_chests) do
    tint_layers(chest, 220, 0.85)
end

for _, chest in pairs(jelly_chest) do
    local animation = tint_layers(chest, 255*0.5, 0.5)
    if animation then
        animation.layers[1].tint = util.color(defines.hexcolor.olive.. 'd9')
        animation.layers[2].tint = util.color(defines.hexcolor.olive.. 'd9')
    end
end

for _, chest in pairs(yumako_chest) do
    local animation = tint_layers(chest, 255*0.5, 0.5)
    if animation then
        animation.layers[1].tint = util.color(defines.hexcolor.coral.. 'd9')
        animation.layers[2].tint = util.color(defines.hexcolor.coral.. 'd9')
    end
end
