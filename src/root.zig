const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const hidapi = @import("hidapi/root.zig");
pub const hidpp = @import("hidpp/root.zig");
pub const HidDeviceInfo = hidapi.HidDeviceInfo;
pub const scanDevices = hidapi.scanDevices;

test {
    _ = std.testing.refAllDecls(hidapi);
    _ = std.testing.refAllDecls(hidpp);
}
