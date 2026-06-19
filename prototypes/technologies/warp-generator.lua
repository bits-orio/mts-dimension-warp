local function generate_icon(overlay_icon, tint)
    return {
        {icon = "__mts-dimension-warp__/graphics/icons/technologies/dimension-warp-512.png", tint = util.color('#aaaaaa77'), icon_size = 512},
        {
            icon = "__core__/graphics/icons/technology/constants/" .. overlay_icon,
            icon_size = 128,
            scale = 0.75,
            shift = {50, 45},
            floating = true,
            tint = tint
        }
    }
end

-- Half-step display name: reuse the "Warp Generator" base name + a ".5" label, so
-- the internal name (warp-generator-N-5, no dot allowed) shows as "Warp Generator N.5".
local function half_name(label)
    return {"", {"technology-name.warp-generator"}, " " .. label}
end

local DGOLD = util.color(defines.hexcolor.darkgoldenrod .. 'ff')
local YGREEN = util.color(defines.hexcolor.yellowgreen .. 'ff')
local LGREEN = util.color(defines.hexcolor.lawngreen .. 'ff')

-- Each generator tech LENGTHENS the auto-warp interval by 5 minutes, forming one
-- MANDATORY ladder: gen-1 -> 1.5 -> 2 -> 2.5 -> ... -> 6 -> 6.5 (15..70 min). Every
-- step is a required prerequisite of the next, so the .5 levels can't be skipped
-- (an optional .5 would be strictly dominated by the next full level and nobody
-- would take it). Timer values live in scripts/warp.lua. Because gen-5/gen-6 sit
-- on this ladder, reaching them -- and everything they gate (platforms, warp gate,
-- stabilize-dimensions) -- now passes through the .5 steps too; that extra science
-- is the price of the finer granularity.

local tech_warp_generator_1 = { -- 15min (THE GATE: arms the warp timer)
    type = "technology", name = "warp-generator-1",
    icons = generate_icon("constant-battery.png", nil),
    effects = {{ type = "nothing", effect_description = {"technology-description.warp-generator"} }},
    prerequisites = {"neo-nauvis", "automation-science-pack"},
    research_trigger = {
        type = "craft-item",
        item = "automation-science-pack",
        count = 100,
    }
}
local tech_warp_generator_1_5 = { -- 20min
    type = "technology", name = "warp-generator-1-5",
    localised_name = half_name("1.5"),
    icons = generate_icon("constant-speed.png", DGOLD),
    effects = {{ type = "nothing", effect_description = {"technology-description.warp-generator-efficiency"} }},
    prerequisites = {"warp-generator-1"},
    unit = {
        count = 100,
        ingredients = {
            {"automation-science-pack", 1},
        },
        time = 15,
    },
}
local tech_warp_generator_2 = { -- 25min
    type = "technology", name = "warp-generator-2",
    icons = generate_icon("constant-speed.png", DGOLD),
    effects = {{ type = "nothing", effect_description = {"technology-description.warp-generator-efficiency"} }},
    -- Depends on platform-radar (not vanilla radar): weaves the cheap early
    -- spectate-radar tech into the warp ladder, so a team extending its planet
    -- time past tier 1.5 makes its floors viewable as a side effect.
    prerequisites = {"warp-generator-1-5", "platform-radar"},
    unit = {
        count = 100,
        ingredients = {
            {"automation-science-pack", 1},
        },
        time = 15,
    },
}
local tech_warp_generator_2_5 = { -- 30min
    type = "technology", name = "warp-generator-2-5",
    localised_name = half_name("2.5"),
    icons = generate_icon("constant-speed.png", DGOLD),
    effects = {{ type = "nothing", effect_description = {"technology-description.warp-generator-efficiency"} }},
    prerequisites = {"warp-generator-2"},
    unit = {
        count = 175,
        ingredients = {
            {"automation-science-pack", 1},
        },
        time = 15,
    },
}

local tech_warp_generator_3 = { -- 35min
    type = "technology", name = "warp-generator-3",
    icons = generate_icon("constant-speed.png", DGOLD),
    effects = {{ type = "nothing", effect_description = {"technology-description.warp-generator-efficiency"} }},
    prerequisites = {"warp-generator-2-5", "military-2"},
    unit = {
        count = 250,
        ingredients = {
            {"automation-science-pack", 1},
            {"logistic-science-pack", 1},
        },
        time = 15,
    },
}
local tech_warp_generator_3_5 = { -- 40min
    type = "technology", name = "warp-generator-3-5",
    localised_name = half_name("3.5"),
    icons = generate_icon("constant-speed.png", YGREEN),
    effects = {{ type = "nothing", effect_description = {"technology-description.warp-generator-efficiency"} }},
    prerequisites = {"warp-generator-3"},
    unit = {
        count = 375,
        ingredients = {
            {"automation-science-pack", 1},
            {"logistic-science-pack", 1},
        },
        time = 15,
    },
}

local tech_warp_generator_4 = { -- 45min
    type = "technology", name = "warp-generator-4",
    icons = generate_icon("constant-speed.png", YGREEN),
    effects = {{ type = "nothing", effect_description = {"technology-description.warp-generator-efficiency"} }},
    prerequisites = {"warp-generator-3-5", "military-3", "advanced-oil-processing"},
    unit = {
        count = 500,
        ingredients = {
            {"automation-science-pack", 1},
            {"logistic-science-pack", 1},
            {"military-science-pack", 2},
            {"chemical-science-pack", 2},
        },
        time = 15,
    },
}
local tech_warp_generator_4_5 = { -- 50min
    type = "technology", name = "warp-generator-4-5",
    localised_name = half_name("4.5"),
    icons = generate_icon("constant-speed.png", YGREEN),
    effects = {{ type = "nothing", effect_description = {"technology-description.warp-generator-efficiency"} }},
    prerequisites = {"warp-generator-4"},
    unit = {
        count = 750,
        ingredients = {
            {"automation-science-pack", 1},
            {"logistic-science-pack", 1},
            {"military-science-pack", 2},
            {"chemical-science-pack", 2},
        },
        time = 15,
    },
}

local tech_warp_generator_5 = { -- 55min
    type = "technology", name = "warp-generator-5",
    icons = generate_icon("constant-speed.png", YGREEN),
    effects = {{ type = "nothing", effect_description = {"technology-description.warp-generator-efficiency"} }},
    prerequisites = {"warp-generator-4-5", "production-science-pack"},
    unit = {
        count = 1000,
        ingredients = {
            {"automation-science-pack", 1},
            {"logistic-science-pack", 1},
            {"military-science-pack", 2},
            {"chemical-science-pack", 1},
            {"production-science-pack", 2},
        },
        time = 15,
    },
}
local tech_warp_generator_5_5 = { -- 60min
    type = "technology", name = "warp-generator-5-5",
    localised_name = half_name("5.5"),
    icons = generate_icon("constant-speed.png", LGREEN),
    effects = {{ type = "nothing", effect_description = {"technology-description.warp-generator-efficiency"} }},
    prerequisites = {"warp-generator-5"},
    unit = {
        count = 1750,
        ingredients = {
            {"automation-science-pack", 1},
            {"logistic-science-pack", 1},
            {"military-science-pack", 2},
            {"chemical-science-pack", 1},
            {"production-science-pack", 2},
        },
        time = 15,
    },
}

local tech_warp_generator_6 = { -- 65min
    type = "technology", name = "warp-generator-6",
    icons = generate_icon("constant-speed.png", LGREEN),
    effects = {{ type = "nothing", effect_description = {"technology-description.warp-generator-efficiency"} }},
    prerequisites = {"warp-generator-5-5", "effect-transmission", "military-4"},
    unit = {
        count = 2500,
        ingredients = {
            {"automation-science-pack", 1},
            {"logistic-science-pack", 1},
            {"military-science-pack", 2},
            {"chemical-science-pack", 1},
            {"utility-science-pack", 2},
            {"production-science-pack", 2},
        },
        time = 15,
    },
}
local tech_warp_generator_6_5 = { -- 70min (final generator step; optional, before stabilize-dimensions)
    type = "technology", name = "warp-generator-6-5",
    localised_name = half_name("6.5"),
    icons = generate_icon("constant-speed.png", LGREEN),
    effects = {{ type = "nothing", effect_description = {"technology-description.warp-generator-efficiency"} }},
    prerequisites = {"warp-generator-6"},
    unit = {
        count = 4000,
        ingredients = {
            {"automation-science-pack", 1},
            {"logistic-science-pack", 1},
            {"military-science-pack", 2},
            {"chemical-science-pack", 1},
            {"utility-science-pack", 2},
            {"production-science-pack", 2},
        },
        time = 15,
    },
}

--- next levels will unlock other features


data:extend({
    tech_warp_generator_1,
    tech_warp_generator_1_5,
    tech_warp_generator_2,
    tech_warp_generator_2_5,
    tech_warp_generator_3,
    tech_warp_generator_3_5,
    tech_warp_generator_4,
    tech_warp_generator_4_5,
    tech_warp_generator_5,
    tech_warp_generator_5_5,
    tech_warp_generator_6,
    tech_warp_generator_6_5,
})
