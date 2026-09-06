const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const linux_impl = @import("linux.zig");
const windows_impl = @import("windows.zig");

pub const HidDeviceInfo = struct {
    path: []const u8,
    vendor: u16,
    product: u16,

    pub fn init(
        allocator: Allocator,
        path: []const u8,
        vendor: u16,
        product: u16,
    ) !@This() {
        return .{
            .path = try allocator.dupe(u8, path),
            .vendor = vendor,
            .product = product,
        };
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        allocator.free(self.path);
        self.* = undefined;
    }
};

pub const HidDeviceInfoIterator = switch (builtin.os.tag) {
    .windows => windows_impl.WinScanDeviceIterator,
    .linux => linux_impl.LinuxScanDeviceIterator,
    else => @compileError("Unsupported platform"),
};

pub fn scanDevices(io: Io) !HidDeviceInfoIterator {
    return .init(io);
}

test {
    if (builtin.os.tag == .windows) {
        _ = std.testing.refAllDecls(windows_impl);
    } else if (builtin.os.tag == .linux) {
        _ = std.testing.refAllDecls(linux_impl);
    }
}
