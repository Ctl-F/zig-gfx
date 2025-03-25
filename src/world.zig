const std = @import("std");
const vmt = @import("vmath.zig");
const gfx = @import("gfx.zig");

pub const VoxelID = enum(u16) {
    Air = 0,
    SoftStone = 1,
};

pub const Dimension = @Vector(3, u32);
pub const Coord = @Vector(3, i32);

pub const VoxelBody = struct {
    const Self = @This();

    voxels: []VoxelID,
    allocator: *std.mem.Allocator,
    size: Dimension,

    pub fn create_empty(allocator: *std.mem.Allocator, size: Dimension) !Self {
        const voxels = try allocator.alloc(VoxelID, @reduce(.Mul, size));
        @memset(voxels, VoxelID.Air);
        return Self{
            .voxels = voxels,
            .allocator = allocator,
            .size = size,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.voxels);
    }

    pub fn select(self: *Self, where: Coord) *VoxelID {
        const index: usize = @intCast(where[0] + (where[1] * @as(i32, @intCast(self.size[0]))) + (where[2] * @as(i32, @intCast(self.size[0])) * @as(i32, @intCast(self.size[1]))));

        std.debug.assert(index < self.voxels.len);

        return &self.voxels[index];
    }
};

pub const World = struct {};

test "VoxelBody allocation and selection" {
    std.debug.print("Running test `VoxelBody allocation and selection`\n", .{});

    var gpa = std.testing.allocator;
    const size = Dimension{ 4, 4, 4 };

    std.debug.print("Creating empty voxel instance...\n", .{});
    var body = try VoxelBody.create_empty(&gpa, size);
    defer body.deinit();
    std.debug.print("...Done.\n", .{});

    std.debug.print("Validating each individual cell for 'empty'...\n", .{});
    for (body.voxels) |v| {
        try std.testing.expectEqual(v, VoxelID.Air);
    }
    std.debug.print("...Done.\n", .{});

    const coord = Coord{ 2, 1, 3 };
    std.debug.print("Selecting: {}\n", .{coord});
    const voxel = body.select(Coord{ 2, 1, 3 });
    voxel.* = VoxelID.SoftStone;
    try std.testing.expectEqual(body.select(Coord{ 2, 1, 3 }).*, VoxelID.SoftStone);

    std.debug.print("Validating empty slot\n", .{});
    try std.testing.expectEqual(body.select(Coord{ 0, 0, 0 }).*, VoxelID.Air);

    std.debug.print("End of test reached.\n", .{});
}
