-- Long pipelines everywhere, to avoid issues with the stairs, mobile gates and
-- harvesters, whose pipelines cross surfaces and run far from the base.
--
-- A segment's extent is the smallest max_pipeline_extent of any fluid box in it,
-- so every fluid box gets the long one, not just pipes and tanks: since Factorio
-- 2.1.15 machines on an overextended segment stop working (2.0 let them run), and
-- a single steam engine at the default 320 then shut down the whole line. Runs in
-- data-final-fixes so other mods' machines are covered too.
local EXTENT = 25000

local function lengthen(box)
    if type(box) == "table" then box.max_pipeline_extent = EXTENT end
end

for _, prototypes in pairs(data.raw) do
    for _, prototype in pairs(prototypes) do
        if type(prototype) == "table" then
            lengthen(prototype.fluid_box)
            lengthen(prototype.input_fluid_box)
            lengthen(prototype.output_fluid_box)
            lengthen(prototype.fuel_fluid_box)
            lengthen(prototype.oxidizer_fluid_box)
            if type(prototype.fluid_boxes) == "table" then
                for _, box in pairs(prototype.fluid_boxes) do lengthen(box) end
            end
            if type(prototype.energy_source) == "table" then
                lengthen(prototype.energy_source.fluid_box)
                lengthen(prototype.energy_source.output_fluid_box)
            end
        end
    end
end
