const std = @import("std");
const mem = std.mem;
const os = std.os;
const ArrayList = std.ArrayList;

const wl = @import("wayland").client.wl;

const c = @import("c.zig");
const render = @import("render.zig");
const State = @import("main.zig").State;

pub const Loop = struct {
    state: *State,
    fds: [5]os.pollfd,
    monitor: *c.udev.udev_monitor,

    pub fn init(state: *State) !Loop {
        // signals
        var mask = mem.zeroes(os.linux.sigset_t);
        os.linux.sigaddset(&mask, os.linux.SIG.INT);
        os.linux.sigaddset(&mask, os.linux.SIG.TERM);
        os.linux.sigaddset(&mask, os.linux.SIG.QUIT);
        _ = os.linux.sigprocmask(os.linux.SIG.BLOCK, &mask, null);
        const sfd = os.linux.signalfd(-1, &mask, os.linux.SFD.NONBLOCK);

        // timer
        const tfd = os.linux.timerfd_create(
            os.CLOCK.MONOTONIC,
            os.linux.TFD.CLOEXEC,
        );
        const interval: os.linux.itimerspec = .{
            .it_interval = .{ .tv_sec = 1, .tv_nsec = 0 },
            .it_value = .{ .tv_sec = 1, .tv_nsec = 0 },
        };
        _ = os.linux.timerfd_settime(@intCast(i32, tfd), 0, &interval, null);

        // inotify
        const ifd = os.linux.inotify_init1(os.linux.IN.CLOEXEC);

        // udev
        const udev = c.udev.udev_new();
        if (udev == null) return error.UdevError;
        const monitor = c.udev.udev_monitor_new_from_netlink(udev, "udev");
        if (monitor == null) return error.UdevError;
        _ = c.udev.udev_monitor_filter_add_match_subsystem_devtype(
            monitor,
            "backlight",
            null,
        );
        _ = c.udev.udev_monitor_enable_receiving(monitor);
        const ufd = c.udev.udev_monitor_get_fd(monitor);

        return Loop{
            .state = state,
            .fds = .{
                .{
                    .fd = @intCast(os.fd_t, sfd),
                    .events = os.POLL.IN,
                    .revents = 0,
                },
                .{
                    .fd = state.wayland.display.getFd(),
                    .events = os.POLL.IN,
                    .revents = 0,
                },
                .{
                    .fd = @intCast(os.fd_t, tfd),
                    .events = os.POLL.IN,
                    .revents = 0,
                },
                .{
                    .fd = @intCast(os.fd_t, ifd),
                    .events = os.POLL.IN,
                    .revents = 0,
                },
                .{
                    .fd = @intCast(os.fd_t, ufd),
                    .events = os.POLL.IN,
                    .revents = 0,
                },
            },
            .monitor= monitor.?,
        };
    }

    pub fn run(self: *Loop) !void {
        const display = self.state.wayland.display;
        const tfd = self.fds[2].fd;

        while (true) {
            while (true) {
                const ret = try display.dispatchPending();
                _ = try display.flush();
                if (ret <= 0) break;
            }
            _ = try os.poll(&self.fds, -1);

            for (self.fds) |fd| {
                if (fd.revents & os.POLL.HUP != 0) {
                    return;
                }
                if (fd.revents & os.POLL.ERR != 0) {
                    return;
                }
            }

            // signals
            if (self.fds[0].revents & os.POLL.IN != 0) {
                return;
            }

            // wayland
            if (self.fds[1].revents & os.POLL.IN != 0) {
                _ = try display.dispatch();
            }
            if (self.fds[1].revents & os.POLL.OUT != 0) {
                _ = try display.flush();
            }

            // timer
            if (self.fds[2].revents & os.POLL.IN != 0) {
                var expirations = mem.zeroes([8]u8);
                _ = try os.read(tfd, &expirations);
                self.renderAllSurfaces(render.renderClock);
            }

            // inotify
            if (self.fds[3].revents & os.POLL.IN != 0) {
                const ifd = self.fds[3].fd;
                var event = mem.zeroes(os.linux.inotify_event);
                _ = try os.read(ifd, mem.asBytes(&event));
                self.renderAllSurfaces(render.renderModules);
            }

            // udev
            if (self.fds[4].revents & os.POLL.IN != 0) {
                _ = c.udev.udev_monitor_receive_device(self.monitor);
                self.renderAllSurfaces(render.renderModules);
            }
        }
    }

    fn renderAllSurfaces(self: *Loop, renderFn: render.RenderFn) void {
        for (self.state.wayland.outputs.items) |output| {
            if (output.surface) |surface| {
                if (surface.configured) {
                    renderFn(surface) catch continue;
                    surface.modulesSurface.commit();
                    surface.backgroundSurface.commit();
                }
            }
        }
    }
};
