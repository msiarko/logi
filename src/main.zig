const platform = @import("platform/root.zig");

pub const main = platform.main;

test {
    _ = @import("std").testing.refAllDecls(platform);
}
