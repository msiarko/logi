const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const HidRawDevInfo = extern struct {
    bustype: u32,
    vendor: i16,
    product: i16,
};

pub const HidDeviceInfo = struct {
    path: []const u8,
    vendor: u16,
    product: u16,

    fn init(
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

const HIDIOCGRAWINFO = std.os.linux.IOCTL.IOR('H', 0x03, HidRawDevInfo);

const ScanDeviceIterator = struct {
    dir: Io.Dir,
    dir_it: Io.Dir.Iterator,

    pub fn init(io: Io, path: []const u8) !@This() {
        var dir = try Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
        return .{ .dir = dir, .dir_it = dir.iterate() };
    }

    pub fn deinit(self: *@This(), io: Io) void {
        self.dir.close(io);
        self.* = undefined;
    }

    pub fn next(self: *@This(), io: Io, allocator: Allocator) !?HidDeviceInfo {
        return while (try self.dir_it.next(io)) |entry| {
            if (entry.kind == .character_device and std.mem.startsWith(u8, entry.name, "hidraw")) {
                const full_path = try std.fmt.allocPrint(allocator, "/dev/{s}", .{entry.name});
                defer allocator.free(full_path);

                const file = Io.Dir.cwd().openFile(io, full_path, .{ .mode = .read_only }) catch continue;
                defer file.close(io);

                var info: HidRawDevInfo = undefined;
                const rc = std.posix.system.ioctl(file.handle, HIDIOCGRAWINFO, @intFromPtr(&info));
                if (rc < 0) continue;

                const vid: u16 = @bitCast(info.vendor);
                const pid: u16 = @bitCast(info.product);

                return try .init(allocator, full_path, vid, pid);
            }
        } else null;
    }
};

pub fn scanDevices(io: Io) !ScanDeviceIterator {
    return .init(io, "/dev");
}

test "HidDeviceInfo.deinit frees the memory" {
    const allocator = std.testing.allocator;
    const device_name = "/dev/hiddevice";
    var device: HidDeviceInfo = try .init(allocator, device_name, 0, 1);
    device.deinit(allocator);
}
