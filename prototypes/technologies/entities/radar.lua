data:extend{
    {
        type = "technology",
        name = "platform-radar",
        icons = {
            {
                icon = "__base__/graphics/technology/radar.png",
                icon_size = 256,
                tint = util.color(defines.hexcolor.royalblue.. 'd9'),
            }
        },
        -- Re-rooted EARLY: depends on the vanilla radar tech only (was
        -- electrified-ground + concrete + radar, which chained back through the
        -- whole power/mining/factory-platform ladder and made spectate radars a
        -- very-late unlock). Now researchable right after vanilla radar, and
        -- warp-generator-2 depends on THIS (not radar) -- so any team progressing
        -- the warp ladder picks it up early and their floors become viewable.
        prerequisites = {
            "radar"
        },
        unit = {
            count = 50,
            ingredients = {
                {"automation-science-pack", 1},
            },
            time = 15,
        },
    }
}