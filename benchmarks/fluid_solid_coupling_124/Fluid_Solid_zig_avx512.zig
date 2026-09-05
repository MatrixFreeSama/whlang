const std = @import("std");

const CHUNK: u64 = 65536;
const VU = @Vector(8, u64);
const VF = @Vector(8, f64);
const LANES: VU = .{ 0, 1, 2, 3, 4, 5, 6, 7 };

var N: u64 = 0;
var E: usize = 0;
var partials: []align(64) f64 = undefined;

inline fn vu(x: u64) VU {
    return @splat(x);
}

inline fn vf(x: f64) VF {
    return @splat(x);
}

inline fn fluid(i: u64) f64 {
    return -0.375 + @as(f64, @floatFromInt((i * 31 + 11) & 2047)) * (1.0 / 2048.0);
}

inline fn solid(i: u64) f64 {
    return 0.25 + @as(f64, @floatFromInt((i * 23 + 5) & 1023)) * (1.0 / 1536.0);
}

inline fn rho(i: u64) f64 {
    return 1.0 + @as(f64, @floatFromInt((i * 13 + 9) & 255)) * (1.0 / 2048.0);
}

inline fn mu(i: u64) f64 {
    return 0.75 + @as(f64, @floatFromInt((i * 7 + 3) & 127)) * (1.0 / 1024.0);
}

inline fn elastic(i: u64) f64 {
    return 1.25 + @as(f64, @floatFromInt((i * 19 + 1) & 255)) * (1.0 / 1024.0);
}

inline fn gammaC(i: u64) f64 {
    return 0.125 + @as(f64, @floatFromInt((i * 5 + 7) & 63)) * (1.0 / 4096.0);
}

inline fn fluidV(i: VU) VF {
    const bits = (i * vu(31) + vu(11)) & vu(2047);
    return vf(-0.375) + @as(VF, @floatFromInt(bits)) * vf(1.0 / 2048.0);
}

inline fn solidV(i: VU) VF {
    const bits = (i * vu(23) + vu(5)) & vu(1023);
    return vf(0.25) + @as(VF, @floatFromInt(bits)) * vf(1.0 / 1536.0);
}

inline fn rhoV(i: VU) VF {
    const bits = (i * vu(13) + vu(9)) & vu(255);
    return vf(1.0) + @as(VF, @floatFromInt(bits)) * vf(1.0 / 2048.0);
}

inline fn muV(i: VU) VF {
    const bits = (i * vu(7) + vu(3)) & vu(127);
    return vf(0.75) + @as(VF, @floatFromInt(bits)) * vf(1.0 / 1024.0);
}

inline fn elasticV(i: VU) VF {
    const bits = (i * vu(19) + vu(1)) & vu(255);
    return vf(1.25) + @as(VF, @floatFromInt(bits)) * vf(1.0 / 1024.0);
}

inline fn gammaCV(i: VU) VF {
    const bits = (i * vu(5) + vu(7)) & vu(63);
    return vf(0.125) + @as(VF, @floatFromInt(bits)) * vf(1.0 / 4096.0);
}

inline fn slotScalar(i: u64) f64 {
    @setFloatMode(.optimized);
    const im1 = if (i != 0) i - 1 else N - 1;
    const ip1 = if (i + 1 != N) i + 1 else 0;

    const fi = fluid(i);
    const fm = fluid(im1);
    const fp = fluid(ip1);
    const ui = solid(i);
    const um = solid(im1);
    const up = solid(ip1);

    var f = rho(i) * (2.0 * fi - fm - fp) + mu(i) * (fp - fm);
    var s = elastic(i) * (2.0 * ui - um - up) + 0.0625 * (up - um);
    const g = gammaC(i);
    const d = fi - ui;
    f += g * d;
    s -= g * d;
    return f * f + s * s;
}

inline fn slotVector(i: VU) VF {
    @setFloatMode(.optimized);
    const im1 = i - vu(1);
    const ip1 = i + vu(1);

    const fi = fluidV(i);
    const fm = fluidV(im1);
    const fp = fluidV(ip1);
    const ui = solidV(i);
    const um = solidV(im1);
    const up = solidV(ip1);

    var f = rhoV(i) * (vf(2.0) * fi - fm - fp) + muV(i) * (fp - fm);
    var s = elasticV(i) * (vf(2.0) * ui - um - up) + vf(0.0625) * (up - um);
    const g = gammaCV(i);
    const d = fi - ui;
    f += g * d;
    s -= g * d;
    return f * f + s * s;
}

inline fn horizontal(v: VF) f64 {
    const a: [8]f64 = v;
    return ((a[0] + a[1]) + (a[2] + a[3])) + ((a[4] + a[5]) + (a[6] + a[7]));
}

fn chunkSum(k: u64) f64 {
    @setFloatMode(.optimized);
    const start = k * CHUNK;
    const end = @min(start + CHUNK, N);
    var scalar: f64 = 0.0;
    var i = start;

    if (i == 0) {
        scalar += slotScalar(0);
        i = 1;
    }

    // The vector kernel is used only where i-1 and i+1 are ordinary interior
    // neighbours. The global periodic endpoints stay scalar so the SIMD lane
    // topology never needs a hidden wrap/branch.
    const interior_end = if (end == N) N - 1 else end;

    var a0: VF = @splat(0.0);
    var a1: VF = @splat(0.0);
    var a2: VF = @splat(0.0);
    var a3: VF = @splat(0.0);

    while (i + 32 <= interior_end) : (i += 32) {
        a0 += slotVector(vu(i) + LANES);
        a1 += slotVector(vu(i + 8) + LANES);
        a2 += slotVector(vu(i + 16) + LANES);
        a3 += slotVector(vu(i + 24) + LANES);
    }
    while (i + 8 <= interior_end) : (i += 8) {
        a0 += slotVector(vu(i) + LANES);
    }

    scalar += horizontal((a0 + a1) + (a2 + a3));
    while (i < end) : (i += 1) scalar += slotScalar(i);
    return scalar;
}

fn worker(e: usize) void {
    const chunks = (N + CHUNK - 1) / CHUNK;
    var k: u64 = @intCast(e);
    while (k < chunks) : (k += @intCast(E)) {
        partials[@intCast(k)] = chunkSum(k);
    }
}

fn treeReduce(m0: u64) f64 {
    @setFloatMode(.optimized);
    var m = m0;
    while (m > 1) {
        var w: u64 = 0;
        var i: u64 = 0;
        while (i + 1 < m) : (i += 2) {
            partials[@intCast(w)] = partials[@intCast(i)] + partials[@intCast(i + 1)];
            w += 1;
        }
        if ((m & 1) != 0) {
            partials[@intCast(w)] = partials[@intCast(m - 1)];
            w += 1;
        }
        m = w;
    }
    return partials[0];
}

pub fn main(init: std.process.Init) !u8 {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) return 2;

    N = std.fmt.parseInt(u64, args[1], 10) catch return 2;
    E = std.fmt.parseInt(usize, args[2], 10) catch return 2;
    if (N < 4 or N > 100_000_000 or (E != 1 and E != 2 and E != 4)) return 2;

    const chunks = (N + CHUNK - 1) / CHUNK;
    partials = try init.gpa.alignedAlloc(f64, .@"64", @intCast(chunks));
    defer init.gpa.free(partials);

    if (E == 1) {
        worker(0);
    } else {
        var threads: [4]std.Thread = undefined;
        for (0..E) |e| threads[e] = try std.Thread.spawn(.{}, worker, .{e});
        for (threads[0..E]) |thread| thread.join();
    }

    const out = treeReduce(chunks);
    const bits: u64 = @bitCast(out);
    std.debug.print("checksum_bits=0x{x:0>16}\n", .{bits});
    return 0;
}
