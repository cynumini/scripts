const std = @import("std");
const skn = @import("sakana");

const SinkInput = struct {
    allocator: std.mem.Allocator,
    index: u32 = 0,
    corked: bool = false,
    mute: bool = false,
    name: []const u8 = "",

    pub fn init(allocator: std.mem.Allocator, index: i64, corked: bool, mute: bool, name: []const u8) !SinkInput {
        return .{
            .allocator = allocator,
            .index = index,
            .corked = corked,
            .mute = mute,
            .name = try allocator.dupe(u8, name),
        };
    }

    pub fn deinit(self: SinkInput) void {
        self.allocator.free(self.name);
    }

    /// The caller owns the returned memory
    pub fn getString(self: SinkInput) ![]const u8 {
        const icon = blk: {
            if (self.mute) {
                break :blk "🔇";
            } else if (self.corked) {
                break :blk "🔈";
            } else {
                break :blk "🔊";
            }
        };
        return std.fmt.allocPrint(self.allocator, "{s} {s}", .{ icon, self.name });
    }

    pub fn toggleMute(self: SinkInput) !void {
        const index = try std.fmt.allocPrint(self.allocator, "{}", .{self.index});
        defer self.allocator.free(index);
        const child = try skn.process.run(.{
            .allocator = self.allocator,
            .argv = &.{ "pactl", "set-sink-input-mute", index, "toggle" },
        });
        defer child.deinit();
    }
};

/// You must deinit the ArrayList and each of its members
pub fn getSinkInputs(allocator: std.mem.Allocator) !std.ArrayList(SinkInput) {
    const child = try skn.process.run(.{
        .allocator = allocator,
        .argv = &.{ "pactl", "list", "sink-inputs" },
    });
    defer child.deinit();

    var result = std.ArrayList(SinkInput).init(allocator);

    if (child.stdout.len == 0) return error.Empty;

    var it = std.mem.splitAny(u8, child.stdout, "\n");

    var sink_input = SinkInput{ .allocator = allocator };
    while (it.next()) |line| {
        if (line.len > 11 and std.mem.eql(u8, line[0..12], "Sink Input #")) {
            sink_input.index = try std.fmt.parseInt(u32, line[12..], 10);
        } else if (line.len > 10 and std.mem.eql(u8, line[1..8], "Corked:")) {
            sink_input.corked = if (std.mem.eql(u8, line[9..11], "no")) false else true;
        } else if (line.len > 8 and std.mem.eql(u8, line[1..6], "Mute:")) {
            sink_input.mute = if (std.mem.eql(u8, line[7..9], "no")) false else true;
        } else if (line.len > 15 and std.mem.eql(u8, line[2..15], "media.name = ")) {
            sink_input.name = try allocator.dupe(u8, line[16 .. line.len - 1]);
            try result.append(sink_input);
        }
    }

    return result;
}

pub fn menu(allocator: std.mem.Allocator, items: []const []const u8) !usize {
    var stdin = std.ArrayList(u8).init(allocator);
    defer stdin.deinit();

    for (items) |item| {
        try stdin.appendSlice(item);
        try stdin.append('\n');
    }

    const child = try skn.process.run(.{
        .allocator = allocator,
        .argv = &.{ "wofi", "-dmenu" },
        .stdin = stdin.items,
    });
    defer child.deinit();

    if (child.stdout.len == 0) return error.Cancelled;

    const result = child.stdout[0 .. child.stdout.len - 1];

    for (0.., items) |i, item| {
        if (std.mem.eql(u8, item, result)) {
            return i;
        }
    }
    return 0;
}

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}){};
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    const sinks_inputs = getSinkInputs(allocator) catch |err| switch (err) {
        error.Empty => return,
        else => return err,
    };
    defer {
        for (sinks_inputs.items) |item| {
            item.deinit();
        }
        sinks_inputs.deinit();
    }

    var items = std.ArrayList([]const u8).init(allocator);
    defer {
        for (items.items) |item| {
            defer allocator.free(item);
        }
        items.deinit();
    }

    for (sinks_inputs.items) |item| {
        const string = try item.getString();
        try items.append(string);
    }

    const index = menu(allocator, items.items) catch |err| switch (err) {
        error.Cancelled => return,
        else => return err,
    };

    try sinks_inputs.items[index].toggleMute();
}
