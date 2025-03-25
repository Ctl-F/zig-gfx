const std = @import("std");
const vmt = @import("vmath.zig");
const gfx = @import("gfx.zig");

const entity = u64;

pub const Collider = union(enum) {
    const Self = @This();

    point: Self.Point,
    box: Self.Box,
    sphere: Self.Sphere,

    pub const Point = struct {
        center: vmt.vec3,
    };

    pub const Box = struct {
        center: vmt.vec3,
        size: vmt.vec3,
    };

    pub const Sphere = struct {
        center: vmt.vec3,
        radius: f32,
    };

    pub fn get_minimum(self: Collider) vmt.vec3 {
        switch (self) {
            .Point => |p| {
                return p;
            },
            .Box => |b| {
                return b.center - b.size;
            },
            .Sphere => |s| {
                return s.center - @as(vmt.vec3, @splat(s.radius));
            },
        }
    }
    pub fn get_maximum(self: Collider) vmt.vec3 {
        switch (self) {
            .Point => |p| {
                return p;
            },
            .Box => |b| {
                return b.center + b.size;
            },
            .Sphere => |s| {
                return s.center + @as(vmt.vec3, @splat(s.radius));
            },
        }
    }
    pub fn get_center(self: Collider) vmt.vec3 {
        switch (self) {
            .Point => |p| {
                return p;
            },
            .Box => |b| {
                return b.center;
            },
            .Sphere => |s| {
                return s.center;
            },
        }
    }
};

pub const PhysicalBody = struct {
    location: vmt.vec3,
    velocity: vmt.vec3,
    gravity: vmt.vec3,
    collider: Collider,
};

pub const VisualMesh = struct {};

pub const SceneLimits = struct {
    max_physical_bodies: usize = 10000,
    max_visual_meshes: usize = 100000,
};

pub const Scene = struct {
    bodies: []PhysicalBody,
    meshes: []VisualMesh,
};
