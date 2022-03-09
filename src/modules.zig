const std = @import("std");
const fmt = std.fmt;
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const os = std.os;

const udev = @import("udev");

const State = @import("main.zig").State;

const StringWriter = std.ArrayList(u8).Writer;

pub const Module = struct {
    impl: *anyopaque,

    printFn: fn (*anyopaque, StringWriter) anyerror!void,

    pub fn print(self: *Module, writer: StringWriter) !void {
        try self.printFn(self.impl, writer);
    }

    pub fn cast(comptime to: type) fn (*anyopaque) *to {
        return (struct {
            pub fn cast(module: *anyopaque) *to {
                return @ptrCast(*to, @alignCast(@alignOf(to), module));
            }
        }).cast;
    }
};

pub const Battery = struct {
    state: *State,
    context: *udev.Udev,
    devices: DeviceList,

    const Device = struct {
        name: []const u8,
        status: []const u8,
        capacity: u8,
    };
    const DeviceList = std.ArrayList(Device);

    pub fn init(state: *State) !Battery {
        const context = try udev.Udev.new();

        var devices = DeviceList.init(state.allocator);
        try updateDevices(state.allocator, context, &devices);
        if (devices.items.len == 0) return error.NoDevicesFound;

        return Battery{
            .state = state,
            .context = context,
            .devices = devices,
        };
    }

    pub fn module(self: *Battery) Module {
        return .{ .impl = @ptrCast(*anyopaque, self), .printFn = print };
    }

    pub fn print(self_opaque: *anyopaque, writer: StringWriter) !void {
        const self = Module.cast(Battery)(self_opaque);

        try updateDevices(self.state.allocator, self.context, &self.devices);
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

    fn updateDevices(
        allocator: mem.Allocator,
        context: *udev.Udev,
        devices: *DeviceList,
    ) !void {
        const enumerate = try udev.Enumerate.new(context);
        try enumerate.addMatchSubsystem("power_supply");
        try enumerate.addMatchSysattr("type", "Battery");
        try enumerate.scanDevices();
        const entries = enumerate.getListEntry();

        var maybe_entry = entries;
        while (maybe_entry) |entry| : (maybe_entry = entry.getNext()) {
            const path = entry.getName();
            const device = try udev.Device.newFromSyspath(context, path);
            try updateOrAppend(allocator, devices, device);
        }
    }

    fn updateOrAppend(
        allocator: mem.Allocator,
        devices: *DeviceList,
        dev: *udev.Device,
    ) !void {
        const name = dev.getSysname() catch return;
        const status = dev.getSysattrValue("status") catch return;
        const capacity = getCapacity(dev) catch return;

        const device = blk: {
            for (devices.items) |*device| {
                if (mem.eql(u8, device.name, name)) {
                    break :blk device;
                }
            } else {
                const device = try devices.addOne();
                device.name = try allocator.dupe(u8, name);
                break :blk device;
            }
        };

        device.status = try allocator.dupe(u8, status);
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
};

pub const Backlight = struct {
    state: *State,
    context: *udev.Udev,
    devices: DeviceList,

    const Device = struct {
        name: []const u8,
        value: u64,
        max: u64,
    };
    const DeviceList = std.ArrayList(Device);

    pub fn init(state: *State) !Backlight {
        const context = try udev.Udev.new();

        var devices = DeviceList.init(state.allocator);
        try updateDevices(state.allocator, context, &devices);
        if (devices.items.len == 0) return error.NoDevicesFound;

        return Backlight{
            .state = state,
            .context = context,
            .devices = devices,
        };
    }

    pub fn module(self: *Backlight) Module {
        return .{ .impl = @ptrCast(*anyopaque, self), .printFn = print };
    }

    pub fn print(self_opaque: *anyopaque, writer: StringWriter) !void {
        const self = Module.cast(Backlight)(self_opaque);

        try updateDevices(self.state.allocator, self.context, &self.devices);
        const device = self.devices.items[0];
        var percent = @intToFloat(f64, device.value) * 100.0;
        percent /= @intToFloat(f64, device.max);
        const value = @floatToInt(u8, @round(percent));

        try writer.print("💡   {d}%", .{value});
    }

    fn updateDevices(
        allocator: mem.Allocator,
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
            try updateOrAppend(allocator, devices, device);
        }
    }

    fn updateOrAppend(
        allocator: mem.Allocator,
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
                device.name = try allocator.dupe(u8, name);
                break :blk device;
            }
        };
        device.value = try fmt.parseInt(u64, value, 10);
        device.max = try fmt.parseInt(u64, max, 10);
    }
};
