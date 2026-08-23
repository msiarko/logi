const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const hidapi = @import("hidapi.zig");

pub fn start(io: Io, allocator: Allocator) !void {
    const devices = try hidapi.scanDevices(io, allocator, 0x046d);
    defer allocator.free(devices);
    for (devices) |*device| {
        std.debug.print("Path: {s}, VID: 0x{X:0>4}, PID: 0x{X:0>4}\n", .{ device.path, device.vendor, device.product });
        @constCast(device).deinit(allocator);
    }
}

test {
    _ = std.testing.refAllDecls(hidapi);
}
