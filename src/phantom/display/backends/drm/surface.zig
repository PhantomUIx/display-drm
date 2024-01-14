const std = @import("std");
const phantom = @import("phantom");
const libdrm = @import("libdrm");
const gbm = @import("gbm");
const Output = @import("output.zig");
const Self = @This();

base: phantom.display.Surface,
output: *Output,
fbId: u32,
fb: ?*phantom.painting.fb.Base,
scene: ?*phantom.scene.Base,
gbmDevice: *gbm.Device,

pub fn new(output: *Output, info: phantom.display.Surface.Info) !*Self {
    const self = try output.display.allocator.create(Self);
    errdefer output.display.allocator.destroy(self);

    self.* = .{
        .base = .{
            .ptr = self,
            .vtable = &.{
                .deinit = impl_deinit,
                .destroy = impl_destroy,
                .info = impl_info,
                .updateInfo = impl_update_info,
                .createScene = impl_create_scene,
            },
            .displayKind = output.base.displayKind,
            .kind = .output,
            .type = @typeName(Self),
        },
        .output = output,
        .fbId = 0,
        .fb = null,
        .scene = null,
        .gbmDevice = try gbm.Device.create(output.node),
    };
    errdefer self.gbmDevice.destroy();

    const connector = try self.output.node.getConnector(self.output.connectorId);
    defer connector.deinit(self.output.display.allocator);

    _ = info;

    if (self.output.node.getEncoder(connector.encoderId) catch null) |encoder| {
        if (self.output.node.getCrtc(encoder.crtcId) catch null) |crtc| {
            std.debug.print("{}\n", .{crtc});
        } else {
            std.debug.print("{}\n", .{encoder});
        }
    } else {
        std.debug.print("{}\n", .{connector});
    }

    return self;
}

fn impl_deinit(ctx: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(ctx));

    if (self.scene) |scene| scene.deinit();
    self.gbmDevice.destroy();
    self.output.display.allocator.destroy(self);
}

fn impl_destroy(ctx: *anyopaque) anyerror!void {
    const self: *Self = @ptrCast(@alignCast(ctx));

    if (self.fbId > 0) {
        try libdrm.types.ModeFbCmd.remove(self.output.node.fd, self.fbId);
        self.fbId = 0;
    }
}

fn impl_info(ctx: *anyopaque) anyerror!phantom.display.Surface.Info {
    const self: *Self = @ptrCast(@alignCast(ctx));
    const outputInfo = try self.output.base.info();
    return .{
        .colorFormat = outputInfo.colorFormat,
        .size = outputInfo.size.res,
        .maxSize = outputInfo.size.res,
        .minSize = outputInfo.size.res,
    };
}

fn impl_update_info(ctx: *anyopaque, info: phantom.display.Surface.Info, fields: []std.meta.FieldEnum(phantom.display.Surface.Info)) anyerror!void {
    const self: *Self = @ptrCast(@alignCast(ctx));
    var outputFields = std.ArrayList(std.meta.FieldEnum(phantom.display.Output.Info)).init(self.output.display.allocator);
    defer outputFields.deinit();

    const outputInfo = try self.output.base.info();

    for (fields) |field| {
        switch (field) {
            .size => try outputFields.append(.size),
            .colorFormat => try outputFields.append(.colorFormat),
            else => return error.UnsupportedField,
        }
    }

    return self.output.base.updateInfo(.{
        .scale = outputInfo.scale,
        .colorFormat = info.colorFormat orelse outputInfo.colorFormat,
        .size = .{
            .phys = outputInfo.size.phys,
            .res = info.size,
        },
    }, outputFields.items);
}

fn impl_create_scene(ctx: *anyopaque, backendType: phantom.scene.BackendType) anyerror!*phantom.scene.Base {
    const self: *Self = @ptrCast(@alignCast(ctx));

    if (self.scene) |scene| return scene;

    const outputInfo = try self.output.base.info();

    if (self.fb == null) {
        return error.NotImplemented;
        //self.fb = try phantom.painting.fb.FileDescriptorFrameBuffer.create(self.output.display.allocator, .{
        //    .res = outputInfo.size.res,
        //    .colorspace = .sRGB,
        //    .colorFormat = outputInfo.colorFormat,
        //}, undefined);
    }

    self.scene = try phantom.scene.createBackend(backendType, .{
        .allocator = self.output.display.allocator,
        .frame_info = phantom.scene.Node.FrameInfo.init(.{
            .res = outputInfo.size.res,
            .scale = outputInfo.scale,
            .physicalSize = outputInfo.size.phys,
            .colorFormat = outputInfo.colorFormat,
        }),
        .target = .{ .fb = self.fb.? },
    });
    return self.scene.?;
}
