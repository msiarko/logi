const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const linux_impl = @import("linux.zig");
const windows_impl = @import("windows.zig");

pub const HidDeviceInfo = struct {
    const max_path_len = 256;

    path: [max_path_len]u8,
    path_len: usize,
    vendor: u16,
    product: u16,

    pub fn init(
        path: []const u8,
        vendor: u16,
        product: u16,
    ) !@This() {
        var self: @This() = .{
            .path = undefined,
            .path_len = @min(max_path_len, path.len),
            .vendor = vendor,
            .product = product,
        };

        @memcpy(self.path[0..self.path_len], path[0..self.path_len]);
        return self;
    }

    pub fn getPath(self: *const @This()) []const u8 {
        return self.path[0..self.path_len];
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
