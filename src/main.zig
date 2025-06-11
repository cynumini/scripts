const std = @import("std");

/// The caller owns the returned memory
pub fn tomorrow(allocator: std.mem.Allocator) ![]const u8 {
    const child = try std.process.Child.run(.{ .allocator = allocator, .argv = &.{
        "pactl", "list", "sink-inputs",
    } });
    return child.stdout;
}

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}){};
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    const stdout = std.io.getStdOut().writer();

    const result = try tomorrow(allocator);
    defer allocator.free(result);

    try stdout.print("{s}\n", .{result});
}
