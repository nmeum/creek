const std = @import("std");
const fmt = std.fmt;
const log = std.log;
const mem = std.mem;
const os = std.os;

const udev = @import("udev");

const render = @import("../render.zig");
const utils = @import("../utils.zig");
const Backlight = @This();

const state = &@import("root").state;

context: *udev.Udev,
monitor: *udev.Monitor,
fd: os.fd_t,
devices: DeviceList,

const Device = struct {
    name: []const u8,
    value: u64,
    max: u64,
};

const DeviceList = std.ArrayList(Device);

pub fn init() !Backlight {
    const context = try udev.Udev.new();

    const monitor = try udev.Monitor.newFromNetlink(context, "udev");
    try monitor.filterAddMatchSubsystemDevType("backlight", null);
    try monitor.filterAddMatchSubsystemDevType("power_supply", null);
    try monitor.enableReceiving();

    var devices = DeviceList.init(state.gpa);
    try updateDevices(state.gpa, context, &devices);

    return Backlight{
        .context = context,
        .monitor = monitor,
        .fd = try monitor.getFd(),
        .devices = devices,
    };
}

pub fn deinit(self: *Backlight) void {
    _ = self.context.unref();
    for (self.devices.items) |*device| {
        state.gpa.free(device.name);
    }
    self.devices.deinit();
}

pub fn refresh(self: *Backlight) !void {
    _ = try self.monitor.receiveDevice();

    for (state.wayland.monitors.items) |monitor| {
        if (monitor.bar) |bar| {
            if (bar.configured) {
                render.renderModules(bar) catch continue;
                bar.modules.surface.commit();
                bar.background.surface.commit();
            }
        }
    }
}

pub fn print(self: *Backlight, writer: anytype) !void {
    try updateDevices(state.gpa, self.context, &self.devices);
    const device = self.devices.items[0];
    var percent = @intToFloat(f64, device.value) * 100.0;
    percent /= @intToFloat(f64, device.max);
    const value = @floatToInt(u8, @round(percent));

    try writer.print("💡   {d}%", .{value});
}

fn updateDevices(
    gpa: mem.Allocator,
    context: *udev.Udev,
    devices: *DeviceList,
) !void {
    const enumerate = try udev.Enumerate.new(context);
    try enumerate.addMatchSubsystem("backlight");
    try enumerate.scanDevices();
    const entries = enumerate.getListEntry();

    var maybe_entry = entries;
    while (maybe_entry) |entry| : (maybe_entry = entry.getNext()) {
        const path = entry.getName();
        const device = try udev.Device.newFromSyspath(context, path);
        try updateOrAppend(gpa, devices, device);
    }
}

fn updateOrAppend(
    gpa: mem.Allocator,
    devices: *DeviceList,
    dev: *udev.Device,
) !void {
    const value = try dev.getSysattrValue("actual_brightness");
    const max = try dev.getSysattrValue("max_brightness");
    const name = try dev.getSysname();

    const device = blk: {
        for (devices.items) |*device| {
            if (mem.eql(u8, device.name, name)) {
                break :blk device;
            }
        } else {
            const device = try devices.addOne();
            device.name = try gpa.dupe(u8, name);
            break :blk device;
        }
    };
    device.value = try fmt.parseInt(u64, value, 10);
    device.max = try fmt.parseInt(u64, max, 10);
}
