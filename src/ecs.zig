const std = @import("std");
const vmt = @import("vmath.zig");
const gfx = @import("gfx.zig");

const entity = u64;

// pub const BodyComp = struct {
//     position: vmt.vec3,
//     velocity: vmt.vec3,
// };

// pub const MeshComp = struct {
//     shader: gfx.Shader,
//     mesh: gfx.Mesh,
//     topology: gfx.Primitive,
//     uniform_binder: ?*const fn () void,
// };

// pub const MAX_ACTIVE_BODIES = 5000;
// pub const MAX_ACTIVE_MESHES = 10000;

// pub const MAX_ENTITIES = @max(MAX_ACTIVE_BODIES, MAX_ACTIVE_MESHES);

// pub const BodyTable = [_]?BodyComp{null} ** MAX_ACTIVE_BODIES;
// pub const MeshTable = [_]?MeshComp{null} ** MAX_ACTIVE_MESHES;

// pub const EntityRegistry = struct {
//     const Self = @This();

//     Entities: [MAX_ENTITIES]Self.EntityEntry,

//     pub const EntityEntry = struct {
//         id: entity,
//         body: ?u64,
//         mesh: ?u64,
//     };
// };

pub fn DefineRegistry(comptime component_types: []const type, comptime max_count: []const u64) type {
    comptime {
        if (max_count.len != component_types.len) {
            @compileError("you must provide an equal number of maximum counts as there are component types.");
        }
    }

    comptime var fields: [component_types.len]std.builtin.Type.StructField = undefined;

    inline for (component_types, max_count, 0..) |component_t, count, i| {
        fields[i] = std.builtin.Type.StructField{
            .{
                .name = @typeName(component_t),
                .type = [count]component_t,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf(component_t),
            },
        };
    }

    return @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}
