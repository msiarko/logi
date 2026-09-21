const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const linux_impl = @import("linux.zig");
const windows_impl = @import("windows.zig");

pub const PathBuf = struct {
    const max_path_len = switch (builtin.os.tag) {
        .windows => std.os.windows.MAX_PATH,
        // too much for the linux device path,
        // but let's leave this for now
        .linux => std.os.linux.PATH_MAX,
        else => @compileError("Unsupported OS"),
    };

    buf: [max_path_len]u8 = undefined,
    len: usize = 0,

    pub fn init(p: []const u8) @This() {
        var self: @This() = undefined;
        self.len = @min(max_path_len, p.len);
        @memcpy(self.buf[0..self.len], p[0..self.len]);
        return self;
    }

    pub fn asSlice(self: *const @This()) []const u8 {
        return self.buf[0..self.len];
    }
};

pub const HidDeviceInfo = struct {
    path: PathBuf,
    vendor: u16,
    product: u16,

    pub fn init(
        path: []const u8,
        vendor: u16,
        product: u16,
    ) !@This() {
        return .{
            .path = .init(path),
            .vendor = vendor,
            .product = product,
        };
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

test "HidDeviceInfo.init and getPath" {
    const path = "test/path/to/device";
    const info = try HidDeviceInfo.init(path, 0x1234, 0x5678);

    try std.testing.expectEqual(0x1234, info.vendor);
    try std.testing.expectEqual(0x5678, info.product);
    try std.testing.expectEqualSlices(u8, path, info.path.asSlice());
}

test "HidDeviceInfo.init truncates long path" {
    var long_path: [300]u8 = undefined;
    @memset(&long_path, 'A');

    const info = try HidDeviceInfo.init(&long_path, 0, 0);
    try std.testing.expectEqual(PathBuf.max_path_len, info.path.len);
    try std.testing.expectEqualSlices(u8, long_path[0..PathBuf.max_path_len], info.path.asSlice());
}

test {
    if (builtin.os.tag == .windows) {
        _ = std.testing.refAllDecls(windows_impl);
    } else if (builtin.os.tag == .linux) {
        _ = std.testing.refAllDecls(linux_impl);
    }
}
