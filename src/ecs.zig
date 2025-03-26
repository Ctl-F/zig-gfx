/// Components
/// Tables
/// Entities
/// Systems
///
/// Components -> A struct/enum for storing some information related to an area
/// Tables -> Generated from components, used to bulk store componenets, accessed by key(index)
/// Entities -> Collection of keys(index) into the tables
/// Systems -> Methods designed to perform work on all the components in a table in a uniform way
///
const std = @import("std");
const vmt = @import("vmath.zig");
const gfx = @import("gfx.zig");

const table_key = u64;

pub const ComponentInfo = struct {
    component_t: type,
    table_length: comptime_int,
};

pub fn GenerateRegistry(comptime components: []ComponentInfo, comptime mod_name: []const u8) type {
    comptime var _Tables: [components.len]std.builtin.Type.StructField = undefined;

    inline for (components, 0..) |component, i| {
        //const componentInfo = @typeInfo(component.component_t);
        const table_name = @typeName(component)[mod_name.len + 1 ..];
        _Tables[i] = .{
            .name = table_name ++ "_Table",
            .type = [component.table_length]component,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(component),
        };
    }

    const TablesCollection = @Type(std.builtin.Type{
        .@"struct" = .{
            .layout = std.builtin.Type.ContainerLayout.auto,
            .fields = &_Tables,
            .decls = &.{},
            .is_tuple = false,
        },
    });

    return struct {
        tables: TablesCollection,
    };
}

fn is_same_base_type(comptime fieldType: type, comptime baseType: type) bool {
    return fieldType == baseType or
        (@typeInfo(fieldType) == .array and @typeInfo(fieldType).array.child == baseType);
}

pub fn CreateEntityType(comptime registry: type, comptime components: []type, comptime mod_name: []const u8) type {
    comptime {
        const registryInfo = @typeInfo(registry);

        for (components) |component| {
            var found: bool = false;

            switch (registryInfo) {
                .@"struct" => |ri| {
                    for (ri.fields) |field| {
                        if (is_same_base_type(field, component)) {
                            found = true;
                            break;
                        }
                    }
                },
                else => @compileError("Registry needs to be a generated registry type."),
            }

            if (!found) {
                @compileError("Component type specified was not found in the registry");
            }
        }

        const fields: [components.len]std.builtin.Type.StructField = undefined;
        for (components, 0..) |comp_t, i| {
            const field_name = @typeName(comp_t)[mod_name.len + 1 ..];
            fields[i] = .{
                .name = field_name,
                .type = table_key,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf(table_key),
            };
        }

        const entity_type = @Type(std.builtin.Type{
            .@"struct" = .{
                .layout = std.builtin.Type.ContainerLayout.auto,
                .fields = &fields,
                .decls = &.{},
                .is_tuple = false,
            },
        });

        return struct {
            components: entity_type,
        };
    }
}

// pub const Collider = union(enum) {
//     const Self = @This();

//     point: Self.Point,
//     box: Self.Box,
//     sphere: Self.Sphere,

//     pub const Point = struct {
//         center: vmt.vec3,
//     };

//     pub const Box = struct {
//         center: vmt.vec3,
//         size: vmt.vec3,
//     };

//     pub const Sphere = struct {
//         center: vmt.vec3,
//         radius: f32,
//     };

//     pub fn get_minimum(self: Collider) vmt.vec3 {
//         switch (self) {
//             .Point => |p| {
//                 return p;
//             },
//             .Box => |b| {
//                 return b.center - b.size;
//             },
//             .Sphere => |s| {
//                 return s.center - @as(vmt.vec3, @splat(s.radius));
//             },
//         }
//     }
//     pub fn get_maximum(self: Collider) vmt.vec3 {
//         switch (self) {
//             .Point => |p| {
//                 return p;
//             },
//             .Box => |b| {
//                 return b.center + b.size;
//             },
//             .Sphere => |s| {
//                 return s.center + @as(vmt.vec3, @splat(s.radius));
//             },
//         }
//     }
//     pub fn get_center(self: Collider) vmt.vec3 {
//         switch (self) {
//             .Point => |p| {
//                 return p;
//             },
//             .Box => |b| {
//                 return b.center;
//             },
//             .Sphere => |s| {
//                 return s.center;
//             },
//         }
//     }
// };

// pub const PhysicalBody = struct {
//     location: vmt.vec3,
//     velocity: vmt.vec3,
//     gravity: vmt.vec3,
//     collider: Collider,
// };

// pub const VisualMesh = struct {};

// pub const SceneLimits = struct {
//     max_physical_bodies: usize = 10000,
//     max_visual_meshes: usize = 100000,
// };

// pub const Scene = struct {
//     bodies: []PhysicalBody,
//     meshes: []VisualMesh,
// };
