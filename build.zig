const std = @import("std");
const Pkg = std.build.Pkg;

const ScanProtocolsStep = @import("deps/zig-wayland/build.zig").ScanProtocolsStep;

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("levee", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);

    const scanner = ScanProtocolsStep.create(b);
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("stable/viewporter/viewporter.xml");
    scanner.addProtocolPath("protocol/wlr-layer-shell-unstable-v1.xml");
    scanner.addProtocolPath("protocol/river-status-unstable-v1.xml");
    scanner.addProtocolPath("protocol/river-control-unstable-v1.xml");

    scanner.generate("wl_compositor", 4);
    scanner.generate("wl_subcompositor", 1);
    scanner.generate("wl_shm", 1);
    scanner.generate("wl_output", 3);
    scanner.generate("wl_seat", 5);
    scanner.generate("wp_viewporter", 1);
    scanner.generate("zwlr_layer_shell_v1", 1);
    scanner.generate("zriver_status_manager_v1", 1);
    scanner.generate("zriver_control_v1", 1);

    exe.step.dependOn(&scanner.step);
    scanner.addCSource(exe);

    const wayland = Pkg{
        .name = "wayland",
        .path = .{ .generated = &scanner.result },
    };
    const pixman = Pkg{
        .name = "pixman",
        .path = .{ .path = "deps/zig-pixman/pixman.zig" },
    };
    const fcft = Pkg{
        .name = "fcft",
        .path = .{ .path = "deps/zig-fcft/fcft.zig" },
        .dependencies = &[_]Pkg{pixman},
    };
    const udev = Pkg{
        .name = "udev",
        .path = .{ .path = "deps/zig-udev/udev.zig" },
    };

    exe.addPackage(fcft);
    exe.addPackage(pixman);
    exe.addPackage(udev);
    exe.addPackage(wayland);

    exe.linkLibC();
    exe.linkSystemLibrary("fcft");
    exe.linkSystemLibrary("libudev");
    exe.linkSystemLibrary("pixman-1");
    exe.linkSystemLibrary("libpulse");
    exe.linkSystemLibrary("wayland-client");

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run levee");
    run_step.dependOn(&run_cmd.step);
}
