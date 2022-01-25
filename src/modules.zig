const std = @import("std");
const fmt = std.fmt;
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const os = std.os;

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
    path: []const u8,
    watch: i32,

    pub const Data = struct {
        value: u8,
        icon: []const u8,
    };

    pub fn init(state: *State) !Battery {
        const path = try fs.path.join(
            state.allocator,
            &.{ "/sys/class/power_supply", state.config.batteryDev },
        );

        const uevent_path = try fs.path.joinZ(
            state.allocator,
            &.{ path, "uevent" },
        );
        defer state.allocator.free(uevent_path);

        const watch = os.linux.inotify_add_watch(
            state.loop.fds[2].fd,
            uevent_path,
            os.linux.IN.ACCESS,
        );

        return Battery{
            .state = state,
            .path = path,
            .watch = @intCast(i32, watch),
        };
    }

    pub fn module(self: *Battery) Module {
        return .{ .impl = @ptrCast(*anyopaque, self), .printFn = print };
    }

    pub fn print(self_opaque: *anyopaque, writer: StringWriter) !void {
        const self = Module.cast(Battery)(self_opaque);

        const data = try self.readData();
        try fmt.format(writer, "{s}   {d}%", .{ data.icon, data.value });
    }

    fn readData(self: *const Battery) !Data {
        const voltage = try self.readInt("voltage_now");
        const charge = try self.readInt("charge_now");
        const charge_full = try self.readInt("charge_full");

        const energy = @as(u64, charge) * @as(u64, voltage) / 1000000;
        const energy_full = @as(u64, charge_full) * @as(u64, voltage) / 1000000;

        var capacity = @intToFloat(f64, energy) * 100.0;
        capacity /= @intToFloat(f64, energy_full);

        const status = try self.readValue("status");

        var icon: []const u8 = "❓";
        if (mem.eql(u8, status, "Discharging")) {
            icon = "🔋";
        } else if (mem.eql(u8, status, "Charging")) {
            icon = "🔌";
        } else if (mem.eql(u8, status, "Full")) {
            icon = "⚡";
        }

        return Data{
            .value = @floatToInt(u8, @round(capacity)),
            .icon = icon,
        };
    }

    fn readInt(self: *const Battery, filename: []const u8) !u32 {
        const value = try self.readValue(filename);
        defer self.state.allocator.free(value);

        return fmt.parseInt(u32, value, 10);
    }

    fn readValue(self: *const Battery, filename: []const u8) ![]u8 {
        const state = self.state;

        const path = try fs.path.join(
            state.allocator,
            &.{ self.path, filename },
        );
        defer state.allocator.free(path);

        const file = try fs.openFileAbsolute(path, .{});
        defer file.close();

        var str = try file.readToEndAlloc(state.allocator, 128);
        return state.allocator.resize(str, str.len - 1).?;
    }
};

pub const Backlight = struct {
    state: *State,
    path: []const u8,
    watch: i32,

    pub const Data = struct {
        value: u8,
    };

    pub fn init(state: *State) !Backlight {
        const path = try fs.path.join(
            state.allocator,
            &.{ "/sys/class/backlight", state.config.backlightDev },
        );

        const uevent_path = try fs.path.joinZ(
            state.allocator,
            &.{ path, "brightness" },
        );
        defer state.allocator.free(uevent_path);

        const watch = os.linux.inotify_add_watch(
            state.loop.fds[2].fd,
            uevent_path,
            os.linux.IN.ACCESS,
        );

        return Backlight{
            .state = state,
            .path = path,
            .watch = @intCast(i32, watch),
        };
    }

    pub fn module(self: *Backlight) Module {
        return .{ .impl = @ptrCast(*anyopaque, self), .printFn = print };
    }

    pub fn print(self_opaque: *anyopaque, writer: StringWriter) !void {
        const self = Module.cast(Backlight)(self_opaque);

        const data = try self.readData();
        try fmt.format(writer, "💡   {d}%", .{ data.value });
    }

    fn readData(self: *const Backlight) !Data {
        const value = try self.readInt("actual_brightness");
        const max = try self.readInt("max_brightness");

        const percent = @intToFloat(f64, value) * 100.0 / @intToFloat(f64, max);

        return Data{ .value = @floatToInt(u8, @round(percent)) };
    }

    fn readInt(self: *const Backlight, filename: []const u8) !u32 {
        const value = try self.readValue(filename);
        defer self.state.allocator.free(value);

        return fmt.parseInt(u32, value, 10);
    }

    fn readValue(self: *const Backlight, filename: []const u8) ![]u8 {
        const state = self.state;

        const path = try fs.path.join(
            state.allocator,
            &.{ self.path, filename },
        );
        defer state.allocator.free(path);

        const file = try fs.openFileAbsolute(path, .{});
        defer file.close();

        var str = try file.readToEndAlloc(state.allocator, 128);
        return state.allocator.resize(str, str.len - 1).?;
    }
};
