const std = @import("std");
const Io = std.Io;
const win = std.os.windows;
const Allocator = std.mem.Allocator;
const root = @import("root.zig");
const HidDeviceInfo = root.HidDeviceInfo;

const HDEVINFO = win.HANDLE;
const SP_DEVINFO_DATA = extern struct {
    cbSize: win.DWORD,
    ClassGuid: win.GUID,
    DevInst: win.DWORD,
    Reserved: win.ULONG_PTR,
};

const SP_DEVICE_INTERFACE_DATA = extern struct {
    cbSize: win.DWORD,
    InterfaceClassGuid: win.GUID,
    Flags: win.DWORD,
    Reserved: win.ULONG_PTR,
};

const SP_DEVICE_INTERFACE_DETAIL_DATA_W = extern struct {
    cbSize: win.DWORD,
    DevicePath: [1]win.WCHAR,
};

const HIDD_ATTRIBUTES = extern struct {
    Size: win.ULONG,
    VendorID: win.USHORT,
    ProductID: win.USHORT,
    VersionNumber: win.USHORT,
};

extern "hid" fn HidD_GetHidGuid(guid: *win.GUID) callconv(.winapi) void;
extern "hid" fn HidD_GetAttributes(file: win.HANDLE, attributes: *HIDD_ATTRIBUTES) callconv(.winapi) c_int;
extern "setupapi" fn SetupDiGetClassDevsW(
    classGuid: ?*const win.GUID,
    enumerator: ?win.PCWSTR,
    hwndParent: ?win.HWND,
    flags: win.DWORD,
) callconv(.winapi) HDEVINFO;
extern "setupapi" fn SetupDiEnumDeviceInterfaces(
    deviceInfoSet: HDEVINFO,
    deviceInfoData: ?*SP_DEVINFO_DATA,
    interfaceClassGuid: *const win.GUID,
    memberIndex: win.DWORD,
    deviceInterfaceData: *SP_DEVICE_INTERFACE_DATA,
) callconv(.winapi) c_int;
extern "setupapi" fn SetupDiGetDeviceInterfaceDetailW(
    deviceInfoSet: HDEVINFO,
    deviceInterfaceData: *SP_DEVICE_INTERFACE_DATA,
    deviceInterfaceDetailData: ?*SP_DEVICE_INTERFACE_DETAIL_DATA_W,
    deviceInterfaceDetailDataSize: win.DWORD,
    requiredSize: ?*win.DWORD,
    deviceInfoData: ?*SP_DEVINFO_DATA,
) callconv(.winapi) c_int;
extern "setupapi" fn SetupDiDestroyDeviceInfoList(deviceInfoSet: HDEVINFO) callconv(.winapi) c_int;
extern "kernel32" fn CreateFileW(
    lpFileName: [*:0]const win.WCHAR,
    dwDesiredAccess: win.DWORD,
    dwShareMode: win.DWORD,
    lpSecurityAttributes: ?*anyopaque,
    dwCreationDisposition: win.DWORD,
    dwFlagsAndAttributes: win.DWORD,
    hTemplateFile: ?win.HANDLE,
) callconv(.winapi) win.HANDLE;
extern "kernel32" fn CloseHandle(hObject: win.HANDLE) callconv(.winapi) c_int;

const DIGCF_PRESENT = 0x00000002;
const DIGCF_DEVICEINTERFACE = 0x00000010;
const FILE_SHARE_READ = 1;
const FILE_SHARE_WRITE = 2;
const OPEN_EXISTING = 3;

pub const WinScanDeviceIterator = struct {
    device_info_set: win.HANDLE,
    guid: win.GUID,
    index: win.DWORD,

    pub fn init(_: Io) !@This() {
        var guid: win.GUID = undefined;
        HidD_GetHidGuid(&guid);

        const hdev = SetupDiGetClassDevsW(&guid, null, null, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
        if (hdev == win.INVALID_HANDLE_VALUE) return error.SetupDiGetClassDevsWFailed;

        return .{
            .device_info_set = hdev,
            .guid = guid,
            .index = 0,
        };
    }

    pub fn deinit(self: *@This(), _: Io) void {
        _ = SetupDiDestroyDeviceInfoList(self.device_info_set);
        self.* = undefined;
    }

    pub fn next(self: *@This(), _: Io, allocator: Allocator) !?HidDeviceInfo {
        while (true) {
            var iface_data = std.mem.zeroInit(
                SP_DEVICE_INTERFACE_DATA,
                .{ .cbSize = @sizeOf(SP_DEVICE_INTERFACE_DATA) },
            );

            const setup_result = SetupDiEnumDeviceInterfaces(
                self.device_info_set,
                null,
                &self.guid,
                self.index,
                &iface_data,
            );

            if (setup_result == 0) return null;
            self.index += 1;
            var required_size: win.DWORD = 0;
            _ = SetupDiGetDeviceInterfaceDetailW(
                self.device_info_set,
                &iface_data,
                null,
                0,
                &required_size,
                null,
            );

            if (required_size == 0) continue;
            const buf = try allocator.alloc(u8, required_size);
            defer allocator.free(buf);

            const detail_data: *SP_DEVICE_INTERFACE_DETAIL_DATA_W = @ptrCast(@alignCast(buf.ptr));
            detail_data.cbSize = if (@sizeOf(usize) == 8) 8 else 6;
            const setup_detail_result = SetupDiGetDeviceInterfaceDetailW(
                self.device_info_set,
                &iface_data,
                detail_data,
                required_size,
                null,
                null,
            );

            if (setup_detail_result == 0) continue;
            const path_ptr = @as([*:0]const win.WCHAR, @ptrCast(&detail_data.DevicePath));
            const handle = CreateFileW(
                path_ptr,
                0,
                FILE_SHARE_READ | FILE_SHARE_WRITE,
                null,
                OPEN_EXISTING,
                0,
                null,
            );

            if (handle == win.INVALID_HANDLE_VALUE) continue;
            defer _ = CloseHandle(handle);

            var attrs: HIDD_ATTRIBUTES = undefined;
            attrs.Size = @sizeOf(HIDD_ATTRIBUTES);
            if (HidD_GetAttributes(handle, &attrs) == 0) continue;

            const path_len = std.mem.indexOfScalar(
                win.WCHAR,
                @as([*]win.WCHAR, @ptrCast(&detail_data.DevicePath))[0..required_size],
                0,
            ) orelse @divCeil(required_size, 2);

            const utf8_path = std.unicode.utf16LeToUtf8Alloc(
                allocator,
                @as([*]win.WCHAR, @ptrCast(&detail_data.DevicePath))[0..path_len],
            ) catch continue;
            defer allocator.free(utf8_path);

            return HidDeviceInfo.init(
                allocator,
                utf8_path,
                attrs.VendorID,
                attrs.ProductID,
            ) catch continue;
        }
    }
};
