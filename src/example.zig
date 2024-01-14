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

    const output = blk: {
        for (outputs.items) |value| {
            if ((value.info() catch continue).enable) break :blk value;
        }
        @panic("Could not find an output");
    };

    const surface = output.createSurface(.output, .{
        .size = .{ .value = .{ 1024, 768 } },
        .colorFormat = comptime vizops.color.fourcc.Value.decode(vizops.color.fourcc.formats.xbgr2101010) catch |e| @compileError(@errorName(e)),
    }) catch |e| @panic(@errorName(e));
    defer {
        surface.destroy() catch {};
        surface.deinit();
    }
}
