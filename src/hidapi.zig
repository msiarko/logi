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

// Vendor ID = 0x046d;
pub fn scanDevices(io: Io, allocator: Allocator, vendor_id: u32) ![]const HidDeviceInfo {
    var dev = try Io.Dir.cwd().openDir(io, "/dev", .{ .iterate = true });
    defer dev.close(io);

    var devices: ArrayList(HidDeviceInfo) = .empty;
    var it = dev.iterate();
    while (try it.next(io)) |entry| {
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

            if (vendor_id != vid) continue;

            try devices.append(allocator, try .init(allocator, full_path, vid, pid));
        }
    }

    return devices.toOwnedSlice(allocator);
}

test "HidDeviceInfo.deinit frees the memory" {
    const allocator = std.testing.allocator;
    const device_name = "/dev/hiddevice";
    var device: HidDeviceInfo = try .init(allocator, device_name, 0, 1);
    device.deinit(allocator);
}
