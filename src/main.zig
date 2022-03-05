const std = @import("std");
const readline = @import("readline");

pub fn main() !void {
    var buffer: [256]u8 = undefined;
    while (try readline.readline(std.heap.page_allocator, "> ", &buffer)) |amount_read| {
        std.log.info("input: {s}", .{buffer[0..amount_read]});
        std.log.info("KEKW", .{});
    }
}
