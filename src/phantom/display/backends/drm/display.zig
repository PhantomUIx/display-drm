const std = @import("std");
const Allocator = std.mem.Allocator;
const phantom = @import("phantom");
const libdrm = @import("libdrm");
const Output = @import("output.zig");
const Self = @This();

allocator: Allocator,
kind: phantom.display.Base.Kind,

pub fn init(alloc: Allocator, kind: phantom.display.Base.Kind) Self {
    return .{
        .allocator = alloc,
        .kind = kind,
    };
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn display(self: *Self) phantom.display.Base {
    return .{
        .vtable = &.{
            .outputs = impl_outputs,
        },
        .type = @typeName(Self),
        .ptr = self,
        .kind = self.kind,
    };
}

fn impl_outputs(ctx: *anyopaque) anyerror!std.ArrayList(*phantom.display.Output) {
    const self: *Self = @ptrCast(@alignCast(ctx));
    var outputs = std.ArrayList(*phantom.display.Output).init(self.allocator);
    errdefer outputs.deinit();

    var iter = libdrm.Node.Iterator.init(self.allocator, .primary);

    while (iter.next()) |node| {
        defer node.deinit();

        const modeCardRes = node.getModeCardRes() catch continue;
        defer modeCardRes.deinit(self.allocator);

        if (modeCardRes.connectorIds()) |connectorIds| {
            for (connectorIds) |connectorId| {
                const connector = node.getConnector(connectorId) catch continue;
                defer connector.deinit(self.allocator);

                const node2 = libdrm.Node{
                    .allocator = self.allocator,
                    .fd = try std.os.dup(node.fd),
                };
                errdefer node2.deinit();

                const output = try Output.new(self, node2, connectorId);
                errdefer output.base.deinit();
                try outputs.append(&output.base);
            }
        }
    }
    return outputs;
}
