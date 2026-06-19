-- change default import for items when importing on space platform.
require 'prototypes.update-final.collision'

if mods['space-age'] then
    for _, planet in pairs(data.raw.planet) do
        if not planet.pollutant_type then planet.pollutant_type = "pollution" end
    end
end

-- force autoplce from nauvis to neo-nauvis
local nauvis_mgs = data.raw.planet['nauvis'].map_gen_settings
data.raw.planet['neo-nauvis'].map_gen_settings = table.deepcopy(nauvis_mgs)

-- Motivation gate (replaces early-game pollution pressure): a team cannot research
-- logistic-science-pack -- and therefore the entire mid-game past red science --
-- until it has warp-generator-1, the tech that arms the warp clock. This pulls
-- teams onto the warp progression early through TECH dependency, with no
-- environmental difficulty spike: you simply cannot advance while parked on the
-- home planet. Idempotent + guarded, so an overhaul mod that renames or removes
-- either tech is a clean no-op.
do
    local green = data.raw.technology['logistic-science-pack']
    if green and data.raw.technology['warp-generator-1'] then
        green.prerequisites = green.prerequisites or {}
        local already = false
        for _, p in pairs(green.prerequisites) do
            if p == 'warp-generator-1' then already = true break end
        end
        if not already then table.insert(green.prerequisites, 'warp-generator-1') end
    end
end

-- fix harvester techs uranium mining requirements sometimes removed(hidden) in mods.
if data.raw.technology['uranium-mining'].hidden then
    for _, tech_name in pairs({'dimension-harvester-right-2', 'dimension-harvester-left-2'}) do
        local prereqs = data.raw.technology[tech_name].prerequisites
        if prereqs then
            for i = #prereqs, 1, -1 do
                if prereqs[i] == 'uranium-mining' then
                    table.remove(prereqs, i)
                end
            end
        end
    end
end