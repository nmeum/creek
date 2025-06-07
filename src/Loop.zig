const std = @import("std");
const log = std.log;
const mem = std.mem;
const posix = std.posix;
const linux = std.os.linux;
const io = std.io;

const render = @import("render.zig");
const Loop = @This();
const Bar = @import("Bar.zig");

const state = &@import("root").state;

sfd: posix.fd_t,

pub fn init() !Loop {
    var mask = posix.empty_sigset;
    linux.sigaddset(&mask, linux.SIG.INT);
    linux.sigaddset(&mask, linux.SIG.TERM);
    linux.sigaddset(&mask, linux.SIG.QUIT);

    _ = linux.sigprocmask(linux.SIG.BLOCK, &mask, null);
    const sfd = linux.signalfd(-1, &mask, linux.SFD.NONBLOCK);

    return Loop{ .sfd = @intCast(sfd) };
}

pub fn run(self: *Loop) !void {
    const wayland = &state.wayland;

    var fds = [_]posix.pollfd{
        .{
            .fd = self.sfd,
            .events = posix.POLL.IN,
            .revents = undefined,
        },
        .{
            .fd = wayland.fd,
            .events = posix.POLL.IN,
            .revents = undefined,
        },
        .{
            .fd = posix.STDIN_FILENO,
            .events = posix.POLL.IN,
            .revents = undefined,
        },
    };

    var reader = io.getStdIn().reader();
    while (true) {
        while (true) {
            const ret = wayland.display.dispatchPending();
            _ = wayland.display.flush();
            if (ret == .SUCCESS) break;
        }

        _ = posix.poll(&fds, -1) catch |err| {
            log.err("poll failed: {s}", .{@errorName(err)});
            return;
        };

        for (fds) |fd| {
            if (fd.revents & posix.POLL.HUP != 0 or fd.revents & posix.POLL.ERR != 0) {
                return;
            }
        }

        // signals
        if (fds[0].revents & posix.POLL.IN != 0) {
            return;
        }

        // wayland
        if (fds[1].revents & posix.POLL.IN != 0) {
            const errno = wayland.display.dispatch();
            if (errno != .SUCCESS) return;
        }
        if (fds[1].revents & posix.POLL.OUT != 0) {
            const errno = wayland.display.flush();
            if (errno != .SUCCESS) return;
        }

        // status input
        if (fds[2].revents & posix.POLL.IN != 0) {
            if (state.wayland.river_seat) |seat| {
                seat.status_text.reset();
                try reader.streamUntilDelimiter(seat.status_text.writer(), '\n', null,);
                var focused_bar = seat.*.focusedBar() orelse continue;

                render.renderText(focused_bar, seat.status_text.getWritten()) catch |err| {
                    log.err("renderText failed for monitor {}: {s}",
                        .{focused_bar.monitor.globalName, @errorName(err)});
                    continue;
                };

                focused_bar.text.surface.commit();
                focused_bar.background.surface.commit();

                if (state.config.showStatusAllOutputs) {
                    // We get all bars instead of just the focused one here
                    var bars_buffer: [8]?*Bar = [_]?*Bar{ null } ** 8;
                    const bars = allBars(bars_buffer[0..]) catch |err| {
                        log.err("renderText failed for all monitors: {s}", .{@errorName(err)});
                        continue;
                    } orelse continue;

                    for (bars) |bar| {
                        if (bar) |b| {
                            // Don't write to the same bar twice
                            if (b.monitor.globalName == focused_bar.monitor.globalName) continue;

                            render.renderText(b, seat.status_text.getWritten()) catch |err| {
                                log.err("renderText failed for monitor {}: {s}",
                                    .{b.monitor.globalName, @errorName(err)});
                                continue;
                            };
                         
                            b.text.surface.commit();
                            b.background.surface.commit();
                        }
                    }
                }
            }
        }
    }
}

fn allBars(bars: []?*Bar) !?[]?*Bar {
    const monitors = state.wayland.monitors.items;

    var i: usize = 0;
    var j: usize = 0;
    while (i < monitors.len) : (i += 1) {
        bars[j] = monitors[i].confBar();
        if (bars[j] != null) {
            j += 1;
        }
    }
    return bars[0..j + 1];
}
