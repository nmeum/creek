const std = @import("std");
const fmt = std.fmt;
const log = std.log;
const mem = std.mem;
const os = std.os;

const udev = @import("udev");

const Module = @import("../Modules.zig").Module;
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
};

const DeviceList = std.ArrayList(Device);

pub fn create(state: *State) !*Backlight {
    const self = try state.gpa.create(Backlight);
    self.state = state;
    self.context = try udev.Udev.new();

    self.monitor = try udev.Monitor.newFromNetlink(self.context, "udev");
    try self.monitor.filterAddMatchSubsystemDevType("backlight", null);
    try self.monitor.filterAddMatchSubsystemDevType("power_supply", null);
    try self.monitor.enableReceiving();

    self.devices = DeviceList.init(state.gpa);
    try updateDevices(state.gpa, self.context, &self.devices);
    if (self.devices.items.len == 0) return error.NoDevicesFound;

    return self;
}

pub fn module(self: *Backlight) !Module {
    return Module{
        .impl = @ptrCast(*anyopaque, self),
        .funcs = .{
            .getEvent = getEvent,
            .print = print,
            .destroy = destroy,
        },
    };
}

fn getEvent(self_opaque: *anyopaque) !Event {
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

fn callbackIn(self_opaque: *anyopaque) Event.Action {
    const self = utils.cast(Backlight)(self_opaque);

    _ = self.monitor.receiveDevice() catch |err| {
        log.err("failed to receive udev device: {s}", .{@errorName(err)});
        return .terminate;
    };

    for (self.state.wayland.monitors.items) |monitor| {
        if (monitor.bar) |bar| {
            if (bar.configured) {
                render.renderModules(bar) catch continue;
                bar.modules.surface.commit();
                bar.background.surface.commit();
            }
        }
    }
    return .ok;
}

fn print(self_opaque: *anyopaque, writer: Module.StringWriter) !void {
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

fn destroy(self_opaque: *anyopaque) void {
    const self = utils.cast(Backlight)(self_opaque);

    _ = self.context.unref();
    for (self.devices.items) |*device| {
        self.state.gpa.free(device.name);
    }
    self.devices.deinit();
    self.state.gpa.destroy(self);
}
