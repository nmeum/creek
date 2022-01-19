const pixman = @import("pixman");

const Buffer = @import("shm.zig").Buffer;
const Surface = @import("wayland.zig").Surface;

pub fn renderBackground(surface: *Surface) !void {
    const wlSurface = surface.backgroundSurface;

    const buffer = try Buffer.nextBuffer(
        &surface.backgroundBuffers,
        surface.output.state.wayland.shm,
        surface.width,
        surface.height,
    );
    buffer.busy = true;

    const area = [_]pixman.Rectangle16{
        .{ .x = 0, .y = 0, .width = surface.width, .height = surface.height },
    };
    const color = pixman.Color{
        .red = 0,
        .green = 0,
        .blue = 0,
        .alpha = 0xffff,
    };
    _ = pixman.Image.fillRectangles(.src, buffer.pix.?, &color, 1, &area);

    wlSurface.setBufferScale(surface.output.scale);
    wlSurface.damageBuffer(0, 0, surface.width, surface.height);
    wlSurface.attach(buffer.buffer, 0, 0);
}
