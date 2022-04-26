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
    scanner.addProtocolPath("protocol/wlr-layer-shell-unstable-v1.xml");
    scanner.addProtocolPath("protocol/river-status-unstable-v1.xml");
    scanner.addProtocolPath("protocol/river-control-unstable-v1.xml");

    exe.step.dependOn(&scanner.step);
    scanner.addCSource(exe);

    const clap = Pkg{
        .name = "clap",
        .path = .{ .path = "deps/zig-clap/clap.zig" },
    };
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

    exe.addPackage(clap);
    exe.addPackage(fcft);
    exe.addPackage(pixman);
    exe.addPackage(udev);
    exe.addPackage(wayland);

    exe.linkLibC();
    exe.linkSystemLibrary("alsa");
    exe.linkSystemLibrary("fcft");
    exe.linkSystemLibrary("libudev");
    exe.linkSystemLibrary("pixman-1");
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
