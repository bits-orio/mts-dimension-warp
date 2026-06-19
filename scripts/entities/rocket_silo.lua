--- prevent the rocket silo from being built everywhere.
--- PORTED to per-team ctx (P4/S7): upstream allowed silos only on the literal
--- 'produstia' surface; under per-team unique names we resolve the surface's
--- owning team + role and allow only on that team's FACTORY dimension.
------------------------------------------------------------
---
local function prevent_building_except_in_factory(event)
    local entity = event.entity

    if not entity.valid then return end

    if entity.name == "rocket-silo" or entity.name == "cargo-landing-pad" then
        local owner = dw.surface_owner(entity.surface.index)
        local ctx = owner and dw.warp_ctx(owner) or nil
        utils.entity_built_surface_check(event, ctx, "factory", "dw-messages.cannot-build-silo-cargo")
    end
end

dw.register_event(defines.events.on_built_entity, prevent_building_except_in_factory)
dw.register_event(defines.events.on_robot_built_entity, prevent_building_except_in_factory)
dw.register_event(defines.events.script_raised_revive, prevent_building_except_in_factory)
