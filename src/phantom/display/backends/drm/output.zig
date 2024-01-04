const std = @import("std");
const vizops = @import("vizops");
const phantom = @import("phantom");
const Display = @import("display.zig");
const libdrm = @import("libdrm");
const dispinf = @import("dispinf");
const Self = @This();

base: phantom.display.Output,
display: *Display,
node: libdrm.Node,
connectorId: u32,
scale: vizops.vector.Float32Vector2,
edid: ?dispinf.Edid,
name: []const u8,
manufacturer: ?[]const u8,

pub fn new(display: *Display, node: libdrm.Node, connectorId: u32) !*Self {
    const self = try display.allocator.create(Self);
    errdefer display.allocator.destroy(self);

    const connector = try node.getConnector(connectorId);
    defer connector.deinit(display.allocator);

    self.* = .{
        .base = .{
            .ptr = self,
            .vtable = &.{
                .surfaces = impl_surfaces,
                .createSurface = impl_create_surface,
                .info = impl_info,
                .updateInfo = impl_update_info,
                .deinit = impl_deinit,
            },
            .displayKind = display.kind,
            .type = @typeName(Self),
        },
        .display = display,
        .node = node,
        .connectorId = connectorId,
        .scale = vizops.vector.Float32Vector2.init(1.0),
        .edid = null,
        .name = try std.fmt.allocPrint(display.allocator, "{s}-{}", .{
            @tagName(connector.connectorType),
            connector.connectorTypeId,
        }),
        .manufacturer = null,
    };
    errdefer display.allocator.free(self.name);
    errdefer {
        if (self.manufacturer) |m| display.allocator.free(m);
    }

    if (connector.props()) |props| {
        const propValues = connector.propValues().?;

        for (props, 0..) |propId, i| {
            const propValueId = propValues[i];

            var prop: libdrm.types.ModeGetProperty = .{
                .propId = propId,
            };
            try prop.getAllocated(node.fd, display.allocator);
            defer prop.deinit(display.allocator);

            var nameEnd: usize = 0;
            while (prop.name[nameEnd] != 0 and nameEnd < prop.name.len) nameEnd += 1;

            if (std.mem.eql(u8, prop.name[0..nameEnd], "EDID")) {
                var blob: libdrm.types.ModeGetBlob = .{
                    .blobId = @intCast(propValueId),
                };
                blob.getAllocated(node.fd, display.allocator) catch continue;
                defer blob.deinit(display.allocator);

                self.edid = dispinf.Edid.initBuffer(blob.data().?) catch null;
            }
        }
    }

    if (self.edid) |edid| {
        self.manufacturer = try display.allocator.dupe(u8, edid.hdr.manufacturerString());
    }
    return self;
}

fn impl_surfaces(ctx: *anyopaque) anyerror!std.ArrayList(*phantom.display.Surface) {
    const self: *Self = @ptrCast(@alignCast(ctx));
    var surfaces = std.ArrayList(*phantom.display.Surface).init(self.display.allocator);
    errdefer surfaces.deinit();
    return surfaces;
}

fn impl_create_surface(ctx: *anyopaque, kind: phantom.display.Surface.Kind, _: phantom.display.Surface.Info) anyerror!*phantom.display.Surface {
    const self: *Self = @ptrCast(@alignCast(ctx));

    if (kind != .output) return error.InvalidKind;
    _ = self;
    return error.NotImplemented;
}

fn impl_info(ctx: *anyopaque) anyerror!phantom.display.Output.Info {
    const self: *Self = @ptrCast(@alignCast(ctx));

    const connector = try self.node.getConnector(self.connectorId);
    defer connector.deinit(self.display.allocator);

    var res = vizops.vector.UsizeVector2.zero();

    if (self.node.getEncoder(connector.encoderId) catch null) |encoder| {
        if (self.node.getCrtc(encoder.crtcId) catch null) |crtc| {
            res.value[0] = crtc.mode.hdisplay;
            res.value[1] = crtc.mode.vdisplay;
        }
    }

    return .{
        .enable = connector.connection == 1,
        .size = .{
            .phys = .{ .value = .{ @floatFromInt(connector.mmWidth), @floatFromInt(connector.mmHeight) } },
            .res = res,
        },
        .scale = self.scale,
        .name = self.name,
        .manufacturer = self.manufacturer orelse "Unknown",
        .colorFormat = .{ .rg = @splat(0) },
    };
}

fn impl_update_info(ctx: *anyopaque, info: phantom.display.Output.Info, fields: []std.meta.FieldEnum(phantom.display.Output.Info)) anyerror!void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    _ = self;
    _ = info;
    _ = fields;
    return error.NotImplemented;
}

fn impl_deinit(ctx: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    self.node.deinit();
    if (self.manufacturer) |m| self.display.allocator.free(m);
    self.display.allocator.free(self.name);
    self.display.allocator.destroy(self);
}
