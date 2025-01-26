const sdl = @import("sdl");
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.host;
    const optimize = b.standardOptimizeOption(.{});
    
    const sdk = sdl.init(b, null);
    
    // NOTE: Only call this once so zig doesn't get confused about importing
    //       it multiple times
    const sdl_mod = sdk.getWrapperModule();
    
    const exe = b.addExecutable(.{
        .name = "zig-8",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const emu = b.addModule("emu", .{
        .root_source_file = b.path("src/cpu.zig"),
        .target = target,
        .optimize = optimize,
    });
    emu.addImport("sdl", sdl_mod);

    const graphics = b.addModule("graphics", .{
        .root_source_file = b.path("src/display.zig"),
        .target = target,
        .optimize = optimize,
    });
    graphics.addImport("sdl", sdl_mod);

    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("c");
    
    exe.root_module.addImport("sdl", sdl_mod);
    exe.root_module.addImport("emu", emu);
    exe.root_module.addImport("graphics", graphics);
    
    b.installArtifact(exe);
    
    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    
    run_step.dependOn(&run_exe.step);
}
