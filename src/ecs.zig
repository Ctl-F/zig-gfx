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

pub fn DefineRegistry(comptime component_types: []const type, comptime max_count: []const u64, comptime moduleName: []const u8) type {
    comptime {
        if (max_count.len != component_types.len) {
            @compileError("you must provide an equal number of maximum counts as there are component types.");
        }
    }

    comptime var fields: [component_types.len]std.builtin.Type.StructField = undefined;
    comptime var managers: [component_types.len]type = undefined;

    inline for (component_types, max_count, 0..) |component_t, count, i| {
        const component_name = @typeName(component_t)[moduleName.len + 1 ..];

        fields[i] = std.builtin.Type.StructField{
            .name = component_name,
            .type = [count]component_t,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(component_t),
        };

        managers[i] = struct {
            current_index: u64 = 0,
            next_index: u64 = 1,

            pub fn get_next(self: *@This()) u64 {
                defer self.current_index = self.next_index;

                return self.current_index;
            }
        };
    }

    const table_type = @Type(std.builtin.Type{
        .@"struct" = std.builtin.Type.Struct{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });

    return struct {
        data: table_type,
    };
}
