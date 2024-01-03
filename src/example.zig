const std = @import("std");
const builtin = @import("builtin");
const options = @import("options");
const phantom = @import("phantom");
const vizops = @import("vizops");

pub const phantomOptions = struct {
    pub const displayBackends = struct {
        pub const drm = @import("phantom.display.drm").display.backends.drm;
    };
};

const alloc = if (builtin.link_libc) std.heap.c_allocator else std.heap.page_allocator;

pub fn main() !void {
    var display = phantom.display.Backend(.drm).Display.init(alloc, .compositor);
    defer display.deinit();

    const outputs = try @constCast(&display.display()).outputs();
    defer {
        for (outputs.items) |output| output.deinit();
        outputs.deinit();
    }

    std.debug.print("{any}\n", .{outputs.items});
}
