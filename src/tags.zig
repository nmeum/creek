const zriver = @import("wayland").client.zriver;

const Output = @import("wayland.zig").Output;
const render = @import("render.zig");
const State = @import("main.zig").State;

pub const Tag = struct {
    label: u8,
    focused: bool = false,
    occupied: bool = false,
};

pub const Tags = struct {
    output: *Output,
    outputStatus: *zriver.OutputStatusV1,
    tags: [9]Tag,

    pub fn create(state: *State, output: *Output) !*Tags {
        const self = try state.allocator.create(Tags);

        self.output = output;
        self.outputStatus = try state.wayland.statusManager.getRiverOutputStatus(
            output.wlOutput,
        );
        for (self.tags) |*tag, i| {
            tag.label = '1' + @intCast(u8, i);
        }

        self.outputStatus.setListener(*Tags, outputStatusListener, self);
        return self;
    }

    pub fn destroy(self: *Tags) void {
        self.outputStatus.destroy();
    }

    fn outputStatusListener(
        _: *zriver.OutputStatusV1,
        event: zriver.OutputStatusV1.Event,
        tags: *Tags,
    ) void {
        switch (event) {
            .focused_tags => |data| {
                for (tags.tags) |*tag, i| {
                    const mask = @as(u32, 1) << @intCast(u5, i);
                    tag.focused = data.tags & mask != 0;
                }
            },
            .view_tags => |data| {
                for (tags.tags) |*tag| {
                    tag.occupied = false;
                }
                for (data.tags.slice(u32)) |view| {
                    for (tags.tags) |*tag, i| {
                        const mask = @as(u32, 1) << @intCast(u5, i);
                        if (view & mask != 0) tag.occupied = true;
                    }
                }
            },
        }
        if (tags.output.surface) |surface| {
            if (surface.configured) {
                render.renderTags(surface) catch return;
                surface.tagsSurface.commit();
                surface.backgroundSurface.commit();
            }
        }
    }
};
