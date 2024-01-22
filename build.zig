const std = @import("std");
const Phantom = @import("phantom");

pub const phantomModule = Phantom.Sdk.PhantomModule{
    .provides = .{
        .displays = &.{"drm"},
    },
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const no_importer = b.option(bool, "no-importer", "disables the import system (not recommended)") orelse false;
    const no_docs = b.option(bool, "no-docs", "skip installing documentation") orelse false;
    const no_tests = b.option(bool, "no-tests", "skip generating tests") orelse false;
    const scene_backend = b.option(Phantom.SceneBackendType, "scene-backend", "The scene backend to use for the example") orelse .headless;
    const use_mesa = b.option(bool, "use-mesa", "whether to use mesa's gbm as a fallback") orelse true;
    const use_libc = b.option(bool, "use-libc", "whether to link libc or not") orelse use_mesa;

    const vizops = b.dependency("vizops", .{
        .target = target,
        .optimize = optimize,
    });

    const libdrm = b.dependency("libdrm", .{
        .target = target,
        .optimize = optimize,
    });

    const dispinf = b.dependency("dispinf", .{
        .target = target,
        .optimize = optimize,
    });

    const gbm = b.dependency("gbm", .{
        .target = target,
        .optimize = optimize,
        .@"use-mesa" = use_mesa,
    });

    const phantom = b.dependency("phantom", .{
        .target = target,
        .optimize = optimize,
        .@"no-importer" = no_importer,
        .@"no-docs" = no_docs,
        .@"import-module" = try Phantom.Sdk.ModuleImport.init(&.{
            .{
                .name = "vizops",
                .module = vizops.module("vizops"),
            },
            .{
                .name = "libdrm",
                .module = libdrm.module("libdrm"),
            },
            .{
                .name = "dispinf",
                .module = dispinf.module("dispinf"),
            },
            .{
                .name = "gbm",
                .module = gbm.module("gbm"),
            },
        }, b.pathFromRoot("src"), b.allocator),
    });

    _ = b.addModule("phantom.display.drm", .{
        .root_source_file = .{ .path = b.pathFromRoot("src/phantom.zig") },
        .imports = &.{
            .{
                .name = "phantom",
                .module = phantom.module("phantom"),
            },
            .{
                .name = "vizops",
                .module = vizops.module("vizops"),
            },
            .{
                .name = "libdrm",
                .module = libdrm.module("libdrm"),
            },
            .{
                .name = "dispinf",
                .module = dispinf.module("dispinf"),
            },
            .{
                .name = "gbm",
                .module = gbm.module("gbm"),
            },
        },
    });

    const exe_options = b.addOptions();
    exe_options.addOption(Phantom.SceneBackendType, "scene_backend", scene_backend);

    const exe_example = b.addExecutable(.{
        .name = "example",
        .root_source_file = .{
            .path = b.pathFromRoot("src/example.zig"),
        },
        .target = target,
        .optimize = optimize,
        .link_libc = use_libc,
    });
    exe_example.root_module.addImport("phantom", phantom.module("phantom"));
    exe_example.root_module.addImport("options", exe_options.createModule());
    exe_example.root_module.addImport("vizops", vizops.module("vizops"));
    b.installArtifact(exe_example);

    if (!no_tests) {
        const step_test = b.step("test", "Run all unit tests");

        const unit_tests = phantom.artifact("test");

        const run_unit_tests = b.addRunArtifact(unit_tests);
        step_test.dependOn(&run_unit_tests.step);

        if (!no_docs) {
            const docs = b.addInstallDirectory(.{
                .source_dir = unit_tests.getEmittedDocs(),
                .install_dir = .prefix,
                .install_subdir = "docs",
            });

            b.getInstallStep().dependOn(&docs.step);
        }
    }
}
