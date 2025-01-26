const std = @import("std");
const sdl = @import("sdl");
const emu = @import("emu");
const graphics = @import("graphics");

pub const App = struct {
    cpu: emu.CPU,
    display: graphics.Display,
    next_time: u32,
    random: std.Random,

    fn new(allocator: std.mem.Allocator) !App {
        const display = try graphics.Display.new();
        
        return App{
            .display = display,
            .random = std.crypto.random,
            .next_time = sdl.getTicks() + graphics.Display.tick_interval,
            .cpu = emu.CPU.new(allocator),
        };
    }

    fn time_left_this_frame(self: *App) u32 {
        const now = sdl.getTicks();
        const next_time = self.next_time;
        if (next_time <= now) {
            return 0;
        } else {
            return next_time - now;
        }
    }

    fn close(self: *App) void {
        sdl.quit();
        self.display.close();
    }

    pub fn load_rom(self: *App, path: []const u8) !void {
        const rom = try std.fs.cwd().openFile(path, .{});
        const slice: []u8 = self.cpu.ram.data[emu.CPU.ROM_BASE..];
        _ = try rom.readAll(slice);
    }
};

const CPUError = error {
    UnknownInstruction
};

const InstructionSet = struct {
    // 00E0 - Clear the screen
    pub fn clear_screen(_: u16, app: *App) void {
        @memset(app.display.get_pixels(), 0);    
    }

    // 00EE - Return from a subroutine
    pub fn return_from_sub(_: u16, app: *App) void {
        app.cpu.ip = app.cpu.return_stack.pop();
    }

    // 1NNN - Jump to address NNN
    pub fn jump_to_addr(inst: u16, app: *App) void {
        const addr: u16 = @intCast(inst & 0x0FFF);
        
        app.cpu.ip = addr;
    }

    // 2NNN - Execute subroutine starting at address NNN
    pub fn jump_to_sub(inst: u16, app: *App) !void {
        const addr: u16 = @intCast(inst & 0x0FFF);
        try app.cpu.return_stack.append(app.cpu.ip);
        app.cpu.ip = addr;
        std.debug.print("JSR to {X} {X}\n", .{addr, inst});
    }

    // 6XNN - Store number NN in register VX
    pub fn store_reg(inst: u16, app: *App) void {
        const reg: u8 = @intCast((inst >> 8) & 0x0F);
        const val: u8 = @intCast(inst & 0xFF);
        
        app.cpu.regs.set(reg, val);
        std.debug.print("Reg {X} for {X} set to {X}\n", .{ reg, inst, val });
    }
    
    // ANNN - Store memory address NNN in register I
    pub fn store_addr(inst: u16, app: *App) void {
        const addr: u16 = @intCast(inst & 0x0FFF);
        app.cpu.regs.addr_reg = addr;
        std.debug.print("Storing addr {X} into I\n", .{addr});
    }

    // CXNN - Set VX to a random number with a mask of NN
    pub fn rand(inst: u16, app: *App) void {
        const mask = @as(u8, @intCast(inst & 0x0FF));
        const reg = @as(u8, @intCast((inst >> 8) & 0xF));
        const num = app.random.int(u8);
        std.debug.print("Rand {d} mask={d} reg={d} inst={d}", .{num, mask, reg, inst});
        app.cpu.regs.set(reg, num & mask);
    }

    // DXYN - Draw a sprite at position VX, VY with N bytes of sprite data
    //        starting at the address stored in I
    //        Set VF to 01 if any set pixels are changed to unset, 00 otherwise
    pub fn draw_sprite(inst: u16, app: *App) void {
        const vx = @as(u8, @intCast((inst >> 8) & 0xF));
        const vy = @as(u8, @intCast((inst >> 4) & 0xF));
        const size = inst & 0xF;

        const sprite_data = app.cpu.ram.data[
            app.cpu.regs.addr_reg..(app.cpu.regs.addr_reg + size)
        ];

        const sprite = graphics.Display.Sprite{
            .x = app.cpu.regs.get(vx),
            .y = app.cpu.regs.get(vy),
            .data = sprite_data
        };

        std.debug.print("vx={X} vy={X} size={X} for {X}\n", .{ vx, vy, size, inst });    
        const did_change_any_pixels = app.display.draw_sprite(sprite);
        if (did_change_any_pixels) {
            app.cpu.regs.set(0xF, 1);
        } else {
            app.cpu.regs.set(0xF, 0);
        }        
    }

    // 7XNN - Add the value NN to register VX
    pub fn add_reg(inst: u16, app: *App) void {
        const reg = @as(u8, @intCast((inst >> 8) & 0xF));
        const to_add = @as(u8, @intCast(inst & 0xFF));
        
        const val = app.cpu.regs.get(reg);
        // +% = wrapping_add
        app.cpu.regs.set(reg, val +% to_add);
    }

    // 3XNN - Skip the following instruction if the value of register VX equals NN
    pub fn skip_if_eq(inst: u16, app: *App) void {
        const reg = @as(u8, @intCast((inst >> 8) & 0xF));
        const compare = @as(u8, @intCast(inst & 0xFF));

        const val = app.cpu.regs.get(reg);
        if (val == compare) {
            app.cpu.ip += 2;
        }
    }
    
    // 4XNN - Skip the following instruction if the value of register VX is not equal to NN
    pub fn skip_if_neq(inst: u16, app: *App) void {
        const reg = @as(u8, @intCast((inst >> 8) & 0xF));
        const compare = @as(u8, @intCast(inst & 0xFF));

        const val = app.cpu.regs.get(reg);
        if (val != compare) {
            app.cpu.ip += 2;
        }
    }

    // 5XY0 - Skip the following instruction if the value of
    //        register VX is equal to the value of register VY
    pub fn skip_if_regs_eq(inst: u16, app: *App) void {
        const r1 = @as(u8, @intCast((inst >> 8) & 0xF));
        const r2 = @as(u8, @intCast((inst >> 4) & 0xF));

        const v1 = app.cpu.regs.get(r1);
        const v2 = app.cpu.regs.get(r2);
        if (v1 == v2) {
            app.cpu.ip += 2;
        }
    }

    // 8XY0 - Store the value of register VY in register VX
    pub fn reg_copy(inst: u16, app: *App) void {
        const r1 = @as(u8, @intCast((inst >> 8) & 0xF));
        const r2 = @as(u8, @intCast((inst >> 4) & 0xF));

        const val = app.cpu.regs.get(r2);
        app.cpu.regs.set(r1, val);
    }

    // 8XY1 - Set VX to VX OR VY
    pub fn reg_bw_or(inst: u16, app: *App) void {
        const r1 = @as(u8, @intCast((inst >> 8) & 0xF));
        const r2 = @as(u8, @intCast((inst >> 4) & 0xF));

        const v1 = app.cpu.regs.get(r1);
        const v2 = app.cpu.regs.get(r2);
        app.cpu.regs.set(r1, v1 | v2);
        app.cpu.regs.set(0xF, 0);
    }

    // 8XY2 - Set VX to VX AND VY
    pub fn reg_bw_and(inst: u16, app: *App) void {
        const r1 = @as(u8, @intCast((inst >> 8) & 0xF));
        const r2 = @as(u8, @intCast((inst >> 4) & 0xF));

        const v1 = app.cpu.regs.get(r1);
        const v2 = app.cpu.regs.get(r2);
        app.cpu.regs.set(r1, v1 & v2);
        app.cpu.regs.set(0xF, 0);
    }

    // 8XY3 - Set VX to VX XOR VY
    pub fn reg_bw_xor(inst: u16, app: *App) void {
        const r1 = @as(u8, @intCast((inst >> 8) & 0xF));
        const r2 = @as(u8, @intCast((inst >> 4) & 0xF));

        const v1 = app.cpu.regs.get(r1);
        const v2 = app.cpu.regs.get(r2);
        app.cpu.regs.set(r1, v1 ^ v2);
        app.cpu.regs.set(0xF, 0);
    }

    // 8XY4 - Add the value of register VY to register VX
    //        Set VF to 01 if a carry occurs
    //        Set VF to 00 if a carry does not occur
    pub fn add_with_carry(inst: u16, app: *App) void {
        const r1 = @as(u8, @intCast((inst >> 8) & 0xF));
        const r2 = @as(u8, @intCast((inst >> 4) & 0xF));

        const v1 = app.cpu.regs.get(r1);
        const v2 = app.cpu.regs.get(r2);

        var overflow: u8 = 0x0;
        const res = @addWithOverflow(v1, v2);
        
        // Overflow
        if (res[1] != 0) {
            overflow = 0x1;
        }
        
        app.cpu.regs.set(r1, res[0]);
        app.cpu.regs.set(0xF, overflow);
    }
    
    // 8XY5 - Subtract the value of register VY from register VX
    //        Set VF to 00 if a borrow occurs
    //        Set VF to 01 if a borrow does not occur
    pub fn sub_with_borrow(inst: u16, app: *App) void {
        const rx = @as(u8, @intCast((inst >> 8) & 0xF));
        const ry = @as(u8, @intCast((inst >> 4) & 0xF));

        const vx = app.cpu.regs.get(rx);
        const vy = app.cpu.regs.get(ry);

        var underflow: u8 = 1;
        const res = @subWithOverflow(vx, vy);
        
        // Underflow
        if (res[1] != 0) {
            std.debug.print("underflowed {d} - {d} ({d}) ({d})\n", .{ vx, vy, res[1], res[0] });
            underflow = 0;
        }
        
        app.cpu.regs.set(rx, res[0]);
        app.cpu.regs.set(0xF, underflow);
    }

    // 8XY6 - Store the value of register VY shifted right one bit in register VX
    //        Set register VF to the least significant bit prior to the shift
    pub fn reg_shr(inst: u16, app: *App) void {
        const r1 = @as(u8, @intCast((inst >> 8) & 0xF));
        const r2 = @as(u8, @intCast((inst >> 4) & 0xF));

        const v2 = app.cpu.regs.get(r2);
        const lsb = v2 & 1;
        
        app.cpu.regs.set(r1, v2 >> 1);
        app.cpu.regs.set(0xF, lsb);
    }
    
    // 8XY7 - Set register VX to the value of VY minus VX
    //        Set VF to 00 if a borrow occurs
    //        Set VF to 01 if a borrow does not occur
    pub fn sub_with_borrow2(inst: u16, app: *App) void {
        const rx = @as(u8, @intCast((inst >> 8) & 0xF));
        const ry = @as(u8, @intCast((inst >> 4) & 0xF));

        const vx = app.cpu.regs.get(rx);
        const vy = app.cpu.regs.get(ry);

        var underflow: u8 = 0x01;
        const res = @subWithOverflow(vy, vx);
        
        // Underflow
        if (res[1] != 0) {
            underflow = 0x00;
        }
        
        app.cpu.regs.set(rx, res[0]);
        app.cpu.regs.set(0xF, underflow);
    }

    // 8XYE - Store the value of register VY shifted left one bit in register VX
    //        Set register VF to the most significant bit prior to the shift
    pub fn reg_shl(inst: u16, app: *App) void {
        const r1 = @as(u8, @intCast((inst >> 8) & 0xF));
        const r2 = @as(u8, @intCast((inst >> 4) & 0xF));

        const v2 = app.cpu.regs.get(r2);
        const msb = (v2 & 0b10000000) >> 7;
        
        app.cpu.regs.set(r1, v2 << 1);
        app.cpu.regs.set(0xF, msb);
    }

    // 9XY0 - Skip the following instruction if the value of
    //        register VX is not equal to the value of register VY
    pub fn skip_if_regs_neq(inst: u16, app: *App) void {
        const r1 = @as(u8, @intCast((inst >> 8) & 0xF));
        const r2 = @as(u8, @intCast((inst >> 4) & 0xF));

        const v1 = app.cpu.regs.get(r1);
        const v2 = app.cpu.regs.get(r2);
        if (v1 != v2) {
            app.cpu.ip += 2;
        }
    }

    // FX15 - Set the delay timer to the value of register VX
    pub fn set_delay(inst: u16, app: *App) void {
        const reg = @as(u8, @intCast((inst >> 8) & 0xF));
        const val = app.cpu.regs.get(reg);
        app.cpu.timers.delay = val;
    }

    // FX07 - Store the current value of the delay timer in register VX
    pub fn get_delay(inst: u16, app: *App) void {
        const reg = @as(u8, @intCast((inst >> 8) & 0xF));
        app.cpu.regs.set(reg, app.cpu.timers.delay);
    }

    // BNNN - Jump to address NNN + V0
    pub fn jump_with_reg(inst: u16, app: *App) void {
        const addr = @as(u16, @intCast(inst & 0x0FFF));
        app.cpu.ip = addr + @as(u16, @intCast(app.cpu.regs.get(0)));
    }

    // EX9E - Skip the following instruction if the key corresponding to
    //        the hex value currently stored in register VX is pressed
    pub fn jump_if_key_pressed(inst: u16, app: *App) void {
        const reg = @as(u8, @intCast((inst >> 8) & 0xF));
        const val = app.cpu.regs.get(reg);
        const pressed = app.cpu.keys.pressed(val);
        if (pressed) {
            app.cpu.ip += 2;
        }
    }

    // EXA1 - Skip the following instruction if the key corresponding to
    //        the hex value currently stored in register VX is not pressed
    pub fn jump_if_key_not_pressed(inst: u16, app: *App) void {
        const reg = @as(u8, @intCast((inst >> 8) & 0xF));
        const val = app.cpu.regs.get(reg);
        const pressed = app.cpu.keys.pressed(val);
        if (!pressed) {
            app.cpu.ip += 2;
        }
    }

    // FX0A - Wait for a keypress and store the result in register VX
    pub fn wait_for_key(inst: u16, app: *App) void {
        const reg = @as(u8, @intCast((inst >> 8) & 0xF));
        app.cpu.state = .wait_for_key;
        app.cpu.regs.wake_reg = reg;
    }

    // FX55 - Store the values of registers V0 to VX inclusive in memory starting at address I
    //        I is set to I + X + 1 after operation
    pub fn reg_store(inst: u16, app: *App) void {
        const reg = @as(u8, @intCast((inst >> 8) & 0xF));
        
        for (0 .. reg + 1) |r| {
            const reg_val = app.cpu.regs.get(@as(u8, @intCast(r)));
            app.cpu.ram.set(app.cpu.regs.addr_reg, reg_val);
            app.cpu.regs.addr_reg += 1;
        }
    }

    fn to_bcd(value: u8) [3]u8 {
        const hundreds = value / 100;
        const tens = (value % 100) / 10;
        const units = value % 10;

        return [3]u8{hundreds, tens, units};
    }


    // FX33 - Store the binary-coded decimal equivalent of the value stored
    //        in register VX at addresses I, I + 1, and I + 2
    pub fn store_bcd(inst: u16, app: *App) void {
        const reg = @as(u8, @intCast((inst >> 8) & 0xF));
        const bcd = to_bcd(app.cpu.regs.get(reg));
        
        app.cpu.ram.set(app.cpu.regs.addr_reg, bcd[0]);
        app.cpu.ram.set(app.cpu.regs.addr_reg + 1, bcd[1]);
        app.cpu.ram.set(app.cpu.regs.addr_reg + 2, bcd[2]);
    }

    // FX65 - Fill registers V0 to VX inclusive with the values stored in memory starting at address I
    //        I is set to I + X + 1 after operation
    pub fn reg_fill(inst: u16, app: *App) void {
        const reg = @as(u8, @intCast((inst >> 8) & 0xF));
        for (0 .. reg + 1) |r| {
            const mem_val = app.cpu.ram.get(app.cpu.regs.addr_reg);
            app.cpu.regs.set(@as(u8, @intCast(r)), mem_val);
            app.cpu.regs.addr_reg += 1;
        }
    }

    // FX1E - Add the value stored in register VX to register I (addr_reg)
    pub fn add_to_addr(inst: u16, app: *App) void {
        const reg = @as(u8, @intCast((inst >> 8) & 0xF));
        const val = app.cpu.regs.get(reg);
        app.cpu.regs.addr_reg += val;
    }

    // FX29 - Set I to the memory address of the sprite data corresponding
    //        to the hexadecimal digit stored in register VX
    pub fn load_i_for_digit(inst: u16, app: *App) void {
        const reg = @as(u8, @intCast((inst >> 8) & 0xF));
        const val = app.cpu.regs.get(reg);
        // Each digit is 5 bytes long and they start at 0x0000
        app.cpu.regs.addr_reg = val * 5;
    }

    pub fn execute(inst: u16, app: *App) !void {
        // First 4 bits
        switch (inst & 0xF000) {
            0x0000 => {
                // Last 12 bits
                switch (inst & 0x0FFF) {
                    0x0E0 => {
                        InstructionSet.clear_screen(inst, app);
                    },
                    0x0EE => {
                        InstructionSet.return_from_sub(inst, app);
                    },
                    else => {
                        std.debug.print("Instruction via 0x0 {X}\n", .{inst});
                    },
                }
            },
            0x1000 => {
                InstructionSet.jump_to_addr(inst, app);
            },
            0x2000 => {
                try InstructionSet.jump_to_sub(inst, app);
            },
            0x3000 => {
                InstructionSet.skip_if_eq(inst, app);
            },
            0x4000 => {
                InstructionSet.skip_if_neq(inst, app);
            },
            0x5000 => {
                InstructionSet.skip_if_regs_eq(inst, app);
            },
            0x6000 => {
                InstructionSet.store_reg(inst, app);
            },
            0x7000 => {
                InstructionSet.add_reg(inst, app);
            },
            0x8000 => {
                // Last 4 bits
                switch (inst & 0xF) {
                    0x0 => {
                        InstructionSet.reg_copy(inst, app);
                    },
                    0x1 => {
                        InstructionSet.reg_bw_or(inst, app);
                    },
                    0x2 => {
                        InstructionSet.reg_bw_and(inst, app);
                    },
                    0x3 => {
                        InstructionSet.reg_bw_xor(inst, app);
                    },
                    0x4 => {
                        InstructionSet.add_with_carry(inst, app);
                    },
                    0x5 => {
                        InstructionSet.sub_with_borrow(inst, app);
                    },
                    0x6 => {
                        InstructionSet.reg_shr(inst, app);
                    },
                    0x7 => {
                        InstructionSet.sub_with_borrow2(inst, app);
                    },
                    0xE => {
                        InstructionSet.reg_shl(inst, app);
                    },
                    else => {
                        std.debug.print("Instruction {X}\n", .{inst});
                        return CPUError.UnknownInstruction;
                    }
                }
            },
            0x9000 => {
                InstructionSet.skip_if_regs_neq(inst, app);
            },
            0xA000 => {
                InstructionSet.store_addr(inst, app);
            },
            0xB000 => {
                InstructionSet.jump_with_reg(inst, app);
            },
            0xC000 => {
                InstructionSet.rand(inst, app);
            },
            0xD000 => {
                InstructionSet.draw_sprite(inst, app);
            },
            0xE000 => {
                // Last 8 bits
                switch (inst & 0xFF) {
                    0x9E => {
                        InstructionSet.jump_if_key_pressed(inst, app);
                    },
                    0xA1 => {
                        InstructionSet.jump_if_key_not_pressed(inst, app);
                    },
                    else => {
                        std.debug.print("Instruction {X}\n", .{inst});
                        return CPUError.UnknownInstruction;    
                    }
                }
            },
            0xF000 => {
                // Last 8 bits
                switch (inst & 0xFF) {
                    0x18 => {
                        std.debug.print("Audio is not implemented!", .{});
                    },
                    0x29 => {
                        InstructionSet.load_i_for_digit(inst, app);
                    },
                    0x0A => {
                        InstructionSet.wait_for_key(inst, app);
                    },
                    0x07 => {
                        InstructionSet.get_delay(inst, app);
                    },
                    0x15 => {
                        InstructionSet.set_delay(inst, app);
                    },
                    0x65 => {
                        InstructionSet.reg_fill(inst, app);
                    },
                    0x55 => {
                        InstructionSet.reg_store(inst, app);
                    },
                    0x33 => {
                        InstructionSet.store_bcd(inst, app);
                    },
                    0x1E => {
                        InstructionSet.add_to_addr(inst, app);
                    },
                    else => {
                        std.debug.print("Instruction {X}\n", .{inst});
                        return CPUError.UnknownInstruction;
                    }
                }
            },
            else => {
                std.debug.print("Instruction {X}\n", .{inst});
                return CPUError.UnknownInstruction;
            },
        }
    }
};

const keys_we_care_about = [16]sdl.Scancode{
    sdl.Scancode.@"0",
    sdl.Scancode.@"1",
    sdl.Scancode.@"2",
    sdl.Scancode.@"3",
    sdl.Scancode.@"4",
    sdl.Scancode.@"5",
    sdl.Scancode.@"6",
    sdl.Scancode.@"7",
    sdl.Scancode.@"8",
    sdl.Scancode.@"9",
    sdl.Scancode.@"a",
    sdl.Scancode.@"b",
    sdl.Scancode.@"c",
    sdl.Scancode.@"d",
    sdl.Scancode.@"e",
    sdl.Scancode.@"f",
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var app = try App.new(gpa.allocator());

    defer {
        // NOTE: Deinit this array before trying to deinit the gpa
        //       otherwise it will complain about leaks
        app.cpu.return_stack.deinit();
        
        _ = gpa.deinit();
        app.close();
    }
    
    try app.load_rom("./tests/inputs/UFO.ch8");
    mainLoop: while (true) {
        if (app.cpu.state == .run) {
            // Guestimating 500hz @ 60fps
            for (0..8) |_| {
                const inst = app.cpu.fetch_instruction();
                try InstructionSet.execute(inst, &app);        
            }
        }

        while (sdl.pollEvent()) |ev| {
            switch (ev) {
                .quit => break :mainLoop,
                .key_up => {
                    const evt = ev.key_up;
                    for (keys_we_care_about, 0..) |k, i| {
                        if (evt.scancode == k) {
                            app.cpu.keys.up(@as(u8, @intCast(i)));
                        }
                        if (app.cpu.state == .wait_for_key) {
                            app.cpu.state = .run;
                            app.cpu.regs.set(app.cpu.regs.wake_reg, @as(u8, @intCast(i)));
                        }
                    }
                },
                .key_down => {
                    const evt = ev.key_down;
                    for (keys_we_care_about, 0..) |k, i| {
                        if (evt.scancode == k) {
                            app.cpu.keys.down(@as(u8, @intCast(i)));
                        }
                    }
                    switch (evt.scancode) {
                        sdl.Scancode.c => {
                            if (evt.modifiers.get(sdl.KeyModifierBit.left_control)) {
                                break :mainLoop;
                            }
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }
        
        sdl.delay(app.time_left_this_frame());
        app.next_time += graphics.Display.tick_interval;
        
        app.cpu.timers.tick();
        try app.display.tick();
    }
}
