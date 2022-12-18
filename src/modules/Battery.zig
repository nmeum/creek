const std = @import("std");
const fmt = std.fmt;
const log = std.log;
const mem = std.mem;
const os = std.os;

const udev = @import("udev");

const Module = @import("../Modules.zig").Module;
const Event = @import("../Loop.zig").Event;
const render = @import("../render.zig");
const utils = @import("../utils.zig");
const Battery = @This();

const state = &@import("root").state;

context: *udev.Udev,
fd: os.fd_t,
devices: DeviceList,

const Device = struct {
    name: []const u8,
    status: []const u8,
    capacity: u8,
};

const DeviceList = std.ArrayList(Device);

pub fn init() !Battery {
    const tfd = tfd: {
        const fd = os.linux.timerfd_create(
            os.CLOCK.MONOTONIC,
            os.linux.TFD.CLOEXEC,
        );
        const interval: os.linux.itimerspec = .{
            .it_interval = .{ .tv_sec = 10, .tv_nsec = 0 },
            .it_value = .{ .tv_sec = 10, .tv_nsec = 0 },
        };
        _ = os.linux.timerfd_settime(@intCast(i32, fd), 0, &interval, null);
        break :tfd @intCast(os.fd_t, fd);
    };

    const context = try udev.Udev.new();

    var devices = DeviceList.init(state.gpa);
    try updateDevices(state.gpa, context, &devices);

    return Battery{
        .context = context,
        .fd = tfd,
        .devices = devices,
    };
}

pub fn deinit(self: *Battery) void {
    _ = self.context.unref();
    for (self.devices.items) |*device| {
        state.gpa.free(device.name);
        state.gpa.free(device.status);
    }
    self.devices.deinit();
}

pub fn print(self: *Battery, writer: anytype) !void {
    try updateDevices(state.gpa, self.context, &self.devices);
    const device = self.devices.items[0];

    var icon: []const u8 = "❓";
    if (mem.eql(u8, device.status, "Discharging")) {
        icon = "🔋";
    } else if (mem.eql(u8, device.status, "Charging")) {
        icon = "🔌";
    } else if (mem.eql(u8, device.status, "Full")) {
        icon = "⚡";
    }

    try fmt.format(writer, "{s}   {d}%", .{ icon, device.capacity });
}

pub fn refresh(self: *Battery) !void {
    var expirations = mem.zeroes([8]u8);
    _ = try os.read(self.fd, &expirations);

    for (state.wayland.monitors.items) |monitor| {
        if (monitor.bar) |bar| {
            if (bar.configured) {
                render.renderClock(bar) catch continue;
                render.renderModules(bar) catch continue;
                bar.clock.surface.commit();
                bar.modules.surface.commit();
                bar.background.surface.commit();
            }
        }
    }
}

fn updateDevices(
    gpa: mem.Allocator,
    context: *udev.Udev,
    devices: *DeviceList,
) !void {
    const enumerate = try udev.Enumerate.new(context);
    defer _ = enumerate.unref();

    try enumerate.addMatchSubsystem("power_supply");
    try enumerate.addMatchSysattr("type", "Battery");
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
    const name = dev.getSysname() catch return;
    const status = dev.getSysattrValue("status") catch return;
    const capacity = getCapacity(dev) catch return;

    const device = blk: {
        for (devices.items) |*device| {
            if (mem.eql(u8, device.name, name)) {
                gpa.free(device.status);
                break :blk device;
            }
        } else {
            const device = try devices.addOne();
            device.name = try gpa.dupe(u8, name);
            break :blk device;
        }
    };

    device.status = try gpa.dupe(u8, status);
    device.capacity = capacity;
}

fn getCapacity(dev: *udev.Device) !u8 {
    const capacity_str = dev.getSysattrValue("capacity") catch {
        return computeCapacityFromCharge(dev) catch {
            return computeCapacityFromEnergy(dev);
        };
    };

    const capacity = try fmt.parseInt(u8, capacity_str, 10);
    return capacity;
}

fn computeCapacityFromEnergy(dev: *udev.Device) !u8 {
    const energy_str = try dev.getSysattrValue("energy_now");
    const energy_full_str = try dev.getSysattrValue("energy_full");

    const energy = try fmt.parseFloat(f64, energy_str);
    const energy_full = try fmt.parseFloat(f64, energy_full_str);

    const capacity = energy * 100.0 / energy_full;
    return @floatToInt(u8, @round(capacity));
}

fn computeCapacityFromCharge(dev: *udev.Device) !u8 {
    const charge_str = try dev.getSysattrValue("charge_now");
    const charge_full_str = try dev.getSysattrValue("charge_full");

    const charge = try fmt.parseFloat(f64, charge_str);
    const charge_full = try fmt.parseFloat(f64, charge_full_str);

    const capacity = charge * 100.0 / charge_full;
    return @floatToInt(u8, @round(capacity));
}
