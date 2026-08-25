const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const hidapi = @import("hidapi.zig");
const hidpp = @import("hidpp.zig");

pub fn start(io: Io, allocator: Allocator) !void {
    var devices = try hidapi.scanDevices(io);
    defer devices.deinit(io);

    var found_device: ?hidapi.HidDeviceInfo = blk: while (try devices.next(io, allocator)) |device| {
        if (device.vendor == 0x046d and device.product == 0xb034)
            break :blk device;

        var mut = device;
        mut.deinit(allocator);
    } else null;

    if (found_device) |*device| {
        std.debug.print("Path: {s}, VID: 0x{X:0>4}, PID: 0x{X:0>4}\n", .{ device.path, device.vendor, device.product });
        device.deinit(allocator);
    }
}

test {
    _ = std.testing.refAllDecls(hidapi);
    _ = std.testing.refAllDecls(hidpp);
}
