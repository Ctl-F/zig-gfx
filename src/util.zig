const std = @import("std");

pub fn debug_print_struct_fields(comptime T: type) void {
    std.debug.print("{s}:\n", .{@typeName(T)});
    impl_debug_print_struct_fields(T, 2);
}

fn impl_debug_print_struct_fields(comptime T: type, indent: comptime_int) void {
    const info = @typeInfo(T);

    switch (info) {
        .@"struct" => |structInfo| {
            const fields = structInfo.fields;
            inline for (fields) |field| {
                inline for (0..indent) |_| {
                    std.debug.print("{s}", .{" "});
                }
                std.debug.print("{s}: {}\n", .{ field.name, field.type });
                impl_debug_print_struct_fields(field.type, indent + 2);
            }
        },
        else => {},
    }
}
