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

pub const table_key = u64;

pub const ComponentTypes = struct {
    Location: struct {
        position: vmt.vec3,
    },
    Mesh: struct {
        mesh: gfx.Mesh,
        topology: gfx.Primitive,
        transformation: vmt.mat4,
    },
    ShaderGroup: struct {
        pub const MAX_MESHES_PER_GROUP = 128;
        shader: gfx.Shader,
        meshes: [MAX_MESHES_PER_GROUP]?table_key,
    },
};

comptime {
    const components = @typeInfo(ComponentTypes);
    const MOD_NAME = "ecs";

    const structInfo = switch (components) {
        .@"struct" => |si| si,
        else => @compileError("Expected struct"),
    };

    var tableFields: [structInfo.fields.len]std.builtin.Type.StructField = undefined;

    for (structInfo.fields, 0..) |component_t, i| {
        tableFields[i] = .{
            .name = component_t.name ++ "s",
            .type = []
        }
    }
}
