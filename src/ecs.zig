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

pub const MAX_ACTIVE_ENTITIES = 1000000;

pub const Entity = struct {
    const Self = @This();

    components: std.AutoHashMap(ComponentID, Component),
    component_signature: ComponentID,
    allocator: *std.mem.Allocator,
    pub fn init(allocator: *std.mem.Allocator) Self {
        return Self{
            .components = std.AutoHashMap(ComponentID, Component).init(allocator),
            .component_signature = CompNone,
            .allocator = allocator,
        };
    }

    pub fn destroy(self: *Self) void {
        self.components.deinit();
    }

    pub fn has_components(self: Self, flags: ComponentID) bool {
        return self.component_signature & flags;
    }

    ///gets a component if it is attached
    pub fn get_component(self: *Self, id: ComponentID) !*Component {
        if (!self.has_components(id)) {
            return error.ComponentNotAttached;
        }
        return self.components.getPtr(id) orelse unreachable;
    }

    /// gets a component if its attached or adds it if it is not attached
    pub fn component(self: *Self, id: ComponentID) !*Component {
        return self.get_component(id) catch |err| {
            switch (err) {
                .ComponentNotAttached => {
                    try self.components.put(id, std.mem.zeroes(Component));
                    self.component_signature &= id;
                    return self.get_component(id);
                },
                else => return err,
            }
        };
    }

    pub fn remove_component(self: *Self, id: ComponentID) void {
        if (!self.has_components(id)) {
            return;
        }
        self.components.remove(id);
        self.component_signature &= ~id;
    }
};

pub const EntityID = usize;

pub const Registry = struct {
    const Self = @This();
    pub const Action = fn (*Entity) anyerror!void;

    allocator: *std.mem.Allocator,
    entities: [MAX_ACTIVE_ENTITIES]?Entity = [_]?Entity{null} ** MAX_ACTIVE_ENTITIES,

    pub fn init(allocator: *std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.entities) |entity| {
            if (entity) |*e| {
                e.destroy();
            }
        }
    }

    //TODO: Improve this search
    pub fn create_entity(self: *Self) !EntityID {
        for (self.entities, 0..) |entity, idx| {
            if (entity == null) {
                entity = Entity.init(self.allocator);
                return idx;
            }
        }
        return error.OutOfSpace;
    }

    pub fn process(self: *Self, ids: EntityID, action: *const Action) anyerror!void {
        for (self.entities) |entity| {
            if (entity) |entt| {
                if (entt.has_components(ids)) {
                    try action(&entt);
                }
            }
        }
    }

    pub fn get_entity(self: *Self, id: EntityID) !*Entity {
        std.debug.assert(id < self.entities.len);
        if (self.entities[id]) |*entity| {
            return entity;
        }
        return error.EntityNotInitialized;
    }

    pub fn destroy_entity(self: *Self, id: EntityID) void {
        std.debug.assert(id < self.entities.len);

        if (self.entities[id]) |*entity| {
            entity.destroy();
        }
    }
};

pub const Component = union(enum) {
    body: Body,
    transformation: Transformation,
    camera: Camera,

    pub const Body = struct {
        pub const ID: ComponentID = CompBody;

        position: vmt.vec3,
        velocity: vmt.vec3,
    };

    pub const Transformation = struct {
        pub const ID: ComponentID = CompTransformation;

        translation: vmt.vec3,
        rotation: vmt.quat,
        scale: vmt.vec3,
    };

    pub const Camera = struct {
        pub const ID: ComponentID = CompCamera;

        eye_position: vmt.vec3,
        orientation: vmt.quat,
        fov: f32 = std.math.pi / 2.0,
        zNear: f32 = 0.01,
        zFar: f32 = 1000.0,

        pub fn get_perspective(self: Camera, aspect: f32) vmt.mat4 {
            return vmt.mat4.createPerspective(self.fov, aspect, self.zNear, self.zFar);
        }
        pub fn get_view(self: Camera, position: vmt.vec3) vmt.mat4 {
            // How to get look direction
            const forward = self.get_forward();
            const eye = position + self.eye_offset;
            const center = eye + forward;
            return vmt.mat4.createLookAt(eye, center, vmt.vec3{ 0, 1, 0 });
        }

        pub fn get_forward(self: Camera) vmt.vec3 {
            return vmt.quat.rotate_vec3(self.orientation, vmt.vec3{ 0, 0, -1 });
        }

        pub fn get_right(self: Camera) vmt.vec3 {
            return vmt.quat.rotate_vec3(self.orientation, vmt.vec3{ 1, 0, 0 });
        }
    };
};

const ComponentID = u128;
pub const CompNone: ComponentID = 0x00000000000000000000000000000000;
pub const CompBody: ComponentID = 0x00000000000000000000000000000001;
pub const CompTransformation: ComponentID = 0x00000000000000000000000000000002;
pub const CompCamera: ComponentID = 0x00000000000000000000000000000004;
