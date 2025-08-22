const std = @import("std");

const Scanner = @import("wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const pie = b.option(bool, "pie", "Build a position-independent executable") orelse false;

    const scanner = Scanner.create(b, .{});

    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("stable/viewporter/viewporter.xml");
    scanner.addSystemProtocol("staging/single-pixel-buffer/single-pixel-buffer-v1.xml");
    scanner.addCustomProtocol(b.path("protocol/wlr-layer-shell-unstable-v1.xml"));
    scanner.addCustomProtocol(b.path("protocol/river-status-unstable-v1.xml"));
    scanner.addCustomProtocol(b.path("protocol/river-control-unstable-v1.xml"));

    scanner.generate("wl_compositor", 4);
    scanner.generate("wl_subcompositor", 1);
    scanner.generate("wl_shm", 1);
    scanner.generate("wl_output", 3);
    scanner.generate("wl_seat", 5);
    scanner.generate("wp_single_pixel_buffer_manager_v1", 1);
    scanner.generate("wp_viewporter", 1);
    scanner.generate("zwlr_layer_shell_v1", 1);
    scanner.generate("zriver_status_manager_v1", 2);
    scanner.generate("zriver_control_v1", 1);

    const wayland = b.createModule(.{ .root_source_file = scanner.result });
    const pixman = b.dependency("pixman", .{}).module("pixman");
    const fcft = b.dependency("fcft", .{}).module("fcft");

    const exe = b.addExecutable(.{
        .name = "creek",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.pie = pie;

    exe.linkLibC();
    exe.root_module.addImport("wayland", wayland);
    exe.linkSystemLibrary("wayland-client");

    exe.root_module.addImport("pixman", pixman);
    exe.linkSystemLibrary("pixman-1");

    exe.root_module.addImport("fcft", fcft);
    exe.linkSystemLibrary("fcft");

    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run.addArgs(args);
    }

    const run_step = b.step("run", "Run creek");
    run_step.dependOn(&run.step);
}
