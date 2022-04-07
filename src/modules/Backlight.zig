const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const os = std.os;

const udev = @import("udev");

const Module = @import("../modules.zig").Module;
const Event = @import("../Loop.zig").Event;
const render = @import("../render.zig");
const State = @import("../main.zig").State;
const utils = @import("../utils.zig");
const Backlight = @This();

state: *State,
context: *udev.Udev,
monitor: *udev.Monitor,
devices: DeviceList,

const Device = struct {
    name: []const u8,
    value: u64,
    max: u64,

    pub fn deinit(self: *Device, gpa: mem.Allocator) void {
        gpa.free(self.name);
    }
};

const DeviceList = std.ArrayList(Device);

pub fn init(state: *State) !Backlight {
    const context = try udev.Udev.new();

    const monitor = try udev.Monitor.newFromNetlink(context, "udev");
    try monitor.filterAddMatchSubsystemDevType("backlight", null);
    try monitor.filterAddMatchSubsystemDevType("power_supply", null);
    try monitor.enableReceiving();

    var devices = DeviceList.init(state.gpa);
    try updateDevices(state.gpa, context, &devices);
    if (devices.items.len == 0) return error.NoDevicesFound;

    return Backlight{
        .state = state,
        .context = context,
        .monitor = monitor,
        .devices = devices,
    };
}

pub fn deinit(self: *Backlight) void {
    _ = self.context.unref();
    for (self.devices.items) |*device| {
        device.deinit(self.state.gpa);
    }
    self.devices.deinit();
}

pub fn module(self: *Backlight) !Module {
    return Module{
        .impl = @ptrCast(*anyopaque, self),
        .eventFn = getEvent,
        .printFn = print,
    };
}

pub fn getEvent(self_opaque: *anyopaque) !Event {
    const self = utils.cast(Backlight)(self_opaque);

    return Event{
        .fd = .{
            .fd = try self.monitor.getFd(),
            .events = os.POLL.IN,
            .revents = undefined,
        },
        .data = self_opaque,
        .callbackIn = callbackIn,
        .callbackOut = Event.noop,
    };
}

fn callbackIn(self_opaque: *anyopaque) error{Terminate}!void {
    const self = utils.cast(Backlight)(self_opaque);

    _ = self.monitor.receiveDevice() catch return;
    for (self.state.wayland.monitors.items) |monitor| {
        if (monitor.surface) |surface| {
            if (surface.configured) {
                render.renderModules(surface) catch continue;
                surface.modulesSurface.commit();
                surface.backgroundSurface.commit();
            }
        }
    }
}

pub fn print(self_opaque: *anyopaque, writer: Module.StringWriter) !void {
    const self = utils.cast(Backlight)(self_opaque);

    try updateDevices(self.state.gpa, self.context, &self.devices);
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
