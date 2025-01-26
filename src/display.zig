const sdl = @import("sdl");
const std = @import("std");

pub const Display = struct {
    pub const WIDTH = 64;
    pub const HEIGHT = 32;
    pub const SCALE = 12;
    
    pub const SIZE = WIDTH * HEIGHT;
    pub const PIXELS_COUNT = SIZE * 4;
    pub const MARGIN = 10;

    pub const tick_interval = 10;

    window: sdl.Window,
    renderer: sdl.Renderer,

    // http://devernay.free.fr/hacks/chip8/C8TECH10.HTM#dispcoords
    // The original implementation of the Chip-8 language used a 64x32-pixel monochrome display
    screen_surface: sdl.Surface,

    pub fn new() !Display {
        try sdl.init(.{
            .video = true,
            .events = true,
            .audio = true,
        });

        const window = try sdl.createWindow(
            "zig-8",
            .{ .default = {} },
            .{ .default = {} },
            (WIDTH * SCALE) + (MARGIN * 2),
            (HEIGHT * SCALE) + (MARGIN * 2),
            .{ .vis = .shown },
        );

        const renderer = try sdl.createRenderer(window, null, .{ .accelerated = true });
        return Display{
            .window = window,
            .renderer = renderer,
            .screen_surface = try sdl.createRgbSurfaceWithFormat(64, 32, .rgb888),
        };
    }

    pub fn close(self: *Display) void {
        self.window.destroy();
        self.renderer.destroy();
    }

    pub fn get_pixels(self: *Display) *[PIXELS_COUNT]u8 {
        const surface = self.screen_surface;
        const surf = surface.ptr;
        const pixels: *[PIXELS_COUNT]u8 = @as([*]u8, @ptrCast(surf.pixels))[0 .. PIXELS_COUNT];
        return pixels;
    }

    pub fn get_pixel(self: *Display, x: u8, y: u8) u32 {
        const surface = self.screen_surface;
        const surf = surface.ptr;
        const fmt = surf.format.*;
        const pixels: *[PIXELS_COUNT]u8 = @as([*]u8, @ptrCast(surf.pixels))[0 .. PIXELS_COUNT];

        const pitch: u32 = @intCast(surf.pitch);
        const bpp: u32 = @intCast(fmt.BytesPerPixel);
        const target = ((y * pitch) + (x * bpp));

        return std.mem.readInt(u32, &[_]u8{
            pixels[target],
            pixels[target + 1],
            pixels[target + 2],
            pixels[target + 3],
        }, .big);
    }

    pub fn set_pixel(self: *Display, x: u8, y: u8, pixel_value: u32) void {
        const surface = self.screen_surface;
        const surf = surface.ptr;
        const fmt = surf.format.*;
        const pixels: *[PIXELS_COUNT]u8 = @as([*]u8, @ptrCast(surf.pixels))[0 .. PIXELS_COUNT];

        const pitch: u32 = @intCast(surf.pitch);
        const bpp: u32 = @intCast(fmt.BytesPerPixel);
        const target = ((y * pitch) + (x * bpp));

        const b: u8 = @intCast(pixel_value & 0xFF);
        const g: u8 = @intCast((pixel_value >> 8) & 0xFF);
        const r: u8 = @intCast((pixel_value >> 16) & 0xFF);

        pixels[target + 1] = r;
        pixels[target + 2] = g;
        pixels[target + 3] = b;
    }

    pub const Sprite = struct {
        data: []u8,

        x: u8,
        y: u8,
    };

    pub fn draw_sprite(self: *Display, s: Sprite) bool {
        var row = s.y;
        var col = s.x;
        var set_one = false;
        std.debug.print("Drawing sprite {any}\n", .{ s });

        // For every piece of sprite data
        for (s.data) |elem| {
            // Wrap sprites around screen edge
            if (row >= HEIGHT) {
                row = 0;
            }
            
            // Draw each column
            for (0..8) |idx| {
                // Wrap sprites around screen edge
                if (col >= WIDTH) {
                    col = 0;
                }
                
                // 0x80 = 0b1000_0000
                // By pulling out each bit and seeing if we should render it
                const last_bit_mask: u8 = 0x80;
                if (elem & (last_bit_mask >> @as(u3, @intCast(idx))) != 0) {
                    var color: u32 = 0x00000000;
                    if (self.get_pixel(col, row) == 0) {
                        // It's black, turn it on
                        color = 0x00FFFFFF;
                        set_one = true;
                    }

                    self.set_pixel(col, row, color);
                }

                col += 1;
            }

            col = s.x;
            row += 1;
        }

        return set_one;
    }

    pub fn tick(self: *Display) !void {
        const screen_texture = try sdl.createTextureFromSurface(self.renderer, self.screen_surface);
        const screen_rect = sdl.Rectangle{
            .x = MARGIN,
            .y = MARGIN,
            .width = WIDTH * SCALE,
            .height = HEIGHT * SCALE,
        };
        try self.renderer.clear();

        try self.renderer.setColorRGB(0x1e, 0x1e, 0x2e);
        try self.renderer.copy(screen_texture, screen_rect, null);

        self.renderer.present();
    }
};
