const builtin = @import("builtin");
const std = @import("std");
const linux = std.os.linux;
const os = std.posix;
const assert = std.debug.assert;

const c = @cImport({
    @cInclude("errno.h");
    @cInclude("string.h");
    @cInclude("stdlib.h");
    @cInclude("stdio.h");
    @cInclude("time.h");
    @cInclude("signal.h");
    @cInclude("termios.h");
    @cInclude("sys/time.h");
    @cInclude("sys/stat.h");
    @cInclude("sys/select.h");
});

const cstd = struct {
    extern fn __zreserveFile() callconv(.C) ?*c.FILE;
};

const trace = @import("trace.zig");

const GetoptContext = extern struct {
    optarg: ?[*:0]const u8 = null,
    opterr: c_int = 1,
    optind: c_int = 1,
    optopt: c_int = undefined,
    // When an element of `argv` contains multiple option characters, it is unspecified how `getopt`
    // determines which options have already been processed.
    //
    // so we use an additional cursor variable
    optcur: c_int = 0,
};

fn z_getopt_r(context: *GetoptContext, argc: c_int, argv: [*]const ?[*:0]const u8, optstring: [*:0]const u8) callconv(.C) c_int {
    var mut_optstring = optstring;

    const first_char_was_colon = mut_optstring[0] == ':';

    // If the application has not set the variable opterr to 0 and the first character of optstring
    // is not a <colon>, getopt() shall also print a diagnostic message to stderr in the format
    // specified for the getopts utility, unless the stderr stream has wide orientation, in which
    // case the behavior is undefined.
    const report_errors = first_char_was_colon or context.opterr != 0;

    if (first_char_was_colon) mut_optstring += 1;

    if (context.optind == 0) {
        // If the application sets `optind` to zero before calling `getopt`, the behavior is
        // unspecified.
        unreachable; // setting `optind` to zero is not portable
    }

    // `getopt` shall return `-1` when all command line options are parsed.
    if (context.optind > argc) {
        return -1;
    }

    // If, when `getopt` is called:
    // - `argv[optind]` is a null pointer
    var arg = argv[@as(usize, @intCast(context.optind))] orelse return -1;

    // - `*argv[optind]` is not the character `-`
    // - `argv[optind]` points to the string `"-"`
    // `getopt` shall return `-1` without changing `optind`.
    if (arg[0] != '-' or arg[1] == 0) {
        return -1;
    }

    // If `argv[optind]` points to the string `"--"` `getopt` shall return `-1` after incrementing
    // optind.
    if (arg[1] == '-' and arg[2] == 0) {
        return -1;
    }

    arg += 1;
    arg += @as(usize, @intCast(context.optcur));

    const opt_char = arg[0];
    assert(opt_char != 0);

    const is_last_char = arg[1] == 0;

    const opt_ptr = c.strchr(mut_optstring, opt_char) orelse {
        context.optopt = opt_char;
        if (report_errors) {
            // in the format specified for the getopts utility
            _ = c.fprintf(c.stderr, "%s: illegal option -- %c\n", argv[0], @as(c_int, opt_char));
        }
        // If `getopt` encounters an option character that is not contained in optstring, it shall
        // return the `<question-mark>` ( `'?'` ) character.
        return '?';
    };

    const takes_arg = opt_ptr[1] == ':';

    if (is_last_char) {
        context.optind += 1;
        context.optcur = 0;
    } else {
        context.optcur += 1;
    }

    if (takes_arg) {
        // If the option takes an argument, `getopt` shall set the variable `optarg` to point to the
        // option-argument as follows:
        if (is_last_char) {
            // If the option was the last character in the string pointed to by an element of argv,
            // then optarg shall contain the next element of argv, and optind shall be incremented
            // by 2.
            context.optarg = argv[@as(usize, @intCast(context.optind))];
            context.optind += 1;

            // If the resulting value of optind is greater than argc, this indicates a missing
            // option-argument, and `getopt` shall return an error indication.
            if (context.optind > argc) {
                if (report_errors) {
                    // in the format specified for the getopts utility
                    _ = c.fprintf(c.stderr, "%s: option requires an argument -- %c\n", argv[0], @as(c_int, opt_char));
                }
                // If it detects a missing option-argument, it shall return the <colon> character ( ':'
                // ) if the first character of optstring was a <colon>, or a <question-mark> character (
                // '?' ) otherwise.
                return if (first_char_was_colon) ':' else '?';
            }
        } else {
            // `optarg` shall point to the string following the option character in that element of
            // argv, and optind shall be incremented by 1.
            context.optarg = arg + 1;
            context.optind += 1;
            context.optcur = 0;
        }
    }
    return opt_char;
}

test z_getopt_r {
    const optstr = "s:vyzaG:";
    const argv: []const ?[*:0]const u8 = &[_]?[*:0]const u8{ "progname", "-v", "-Gsus", "-s", "foo", "-zy", "--", "-a" };
    var s: GetoptContext = .{};
    try std.testing.expect(z_getopt_r(&s, argv.len, argv.ptr, optstr) == 'v' and s.optind == 2);
    try std.testing.expect(z_getopt_r(&s, argv.len, argv.ptr, optstr) == 'G' and std.mem.eql(u8, std.mem.span(s.optarg.?), "sus") and s.optind == 3);
    try std.testing.expect(z_getopt_r(&s, argv.len, argv.ptr, optstr) == 's' and std.mem.eql(u8, std.mem.span(s.optarg.?), "foo") and s.optind == 5);
    try std.testing.expect(z_getopt_r(&s, argv.len, argv.ptr, optstr) == 'z' and s.optind == 6);
    try std.testing.expect(z_getopt_r(&s, argv.len, argv.ptr, optstr) == 'y' and s.optind == 6);
    try std.testing.expect(z_getopt_r(&s, argv.len, argv.ptr, optstr) == -1 and s.optind == 7);
}

test "z_getopt_r handles unknown options correctly without leading colon" {
    const optstr = "s:vyzaG:";
    const argv: []const ?[*:0]const u8 = &[_]?[*:0]const u8{ "progname", "-k" };
    var s: GetoptContext = .{ .opterr = 0 };
    try std.testing.expect(z_getopt_r(&s, argv.len, argv.ptr, optstr) == '?' and s.optind == 1 and s.optopt == 'k');
}

test "z_getopt_r handles unknown options correctly with leading colon" {
    const optstr = ":s:vyzaG:";
    const argv: []const ?[*:0]const u8 = &[_]?[*:0]const u8{ "progname", "-k" };
    var s: GetoptContext = .{ .opterr = 0 };
    try std.testing.expect(z_getopt_r(&s, argv.len, argv.ptr, optstr) == ':' and s.optind == 1 and s.optopt == 'k');
}

test "z_getopt_r handles single dash correctly " {
    const optstr = "s:vyzaG:";
    const argv: []const ?[*:0]const u8 = &[_]?[*:0]const u8{ "progname", "-v", "-", "-l" };
    var s: GetoptContext = .{ .opterr = 0 };
    try std.testing.expect(z_getopt_r(&s, argv.len, argv.ptr, optstr) == 'v' and s.optind == 1);
    try std.testing.expect(z_getopt_r(&s, argv.len, argv.ptr, optstr) == -1 and s.optind == 2);
}

test "z_getopt_r handles missing argument correctly without leading colon" {
    const optstr = "s:vyzaG:";
    const argv: []const ?[*:0]const u8 = &[_]?[*:0]const u8{ "progname", "-s" };
    var s: GetoptContext = .{ .opterr = 0 };
    try std.testing.expect(z_getopt_r(&s, argv.len, argv.ptr, optstr) == '?' and s.optind == 1 and s.optopt == 's');
}

test "z_getopt_r handles missing argument correctly with leading colon" {
    const optstr = ":s:vyzaG:";
    const argv: []const ?[*:0]const u8 = &[_]?[*:0]const u8{ "progname", "-s" };
    var s: GetoptContext = .{ .opterr = 0 };
    try std.testing.expect(z_getopt_r(&s, argv.len, argv.ptr, optstr) == ':' and s.optind == 1 and s.optopt == 's');
}

/// Returns some information through these globals
///    extern char *optarg;
///    extern int opterr, optind, optopt;
export fn getopt(argc: c_int, argv: [*]const ?[*:0]const u8, optstring: [*:0]const u8) callconv(.C) c_int {
    const global = struct {
        // The `getopt` function need not be thread-safe.
        export var optarg: ?[*:0]const u8 = @as(GetoptContext, .{}).optarg;
        export var opterr: c_int = @as(GetoptContext, .{}).opterr;
        export var optind: c_int = @as(GetoptContext, .{}).optind;
        export var optopt: c_int = @as(GetoptContext, .{}).optopt;
        var optcur: c_int = @as(GetoptContext, .{}).optcur;
    };

    trace.log("getopt argc={} argv={*} opstring={} (err={}, ind={}, opt={})", .{
        argc,
        argv,
        trace.fmtStr(optstring),
        global.opterr,
        global.optind,
        global.optopt,
    });

    var s: GetoptContext = .{
        .optarg = global.optarg,
        .opterr = global.opterr,
        .optind = global.optind,
        .optopt = global.optopt,
        .optcur = global.optcur,
    };

    defer {
        global.optarg = s.optarg;
        global.opterr = s.opterr;
        global.optind = s.optind;
        global.optopt = s.optopt;
        global.optcur = s.optcur;
    }

    return z_getopt_r(&s, argc, argv, optstring);
}

export fn write(fd: c_int, buf: [*]const u8, nbyte: usize) callconv(.C) isize {
    if (builtin.os.tag == .windows) {
        @panic("write not implemented on windows");
    }
    const rc = os.system.write(fd, buf, nbyte);
    switch (os.errno(rc)) {
        .SUCCESS => return @as(isize, @intCast(rc)),
        else => |e| {
            c.errno = @intFromEnum(e);
            return -1;
        },
    }
}

export fn read(fd: c_int, buf: [*]u8, len: usize) callconv(.C) isize {
    trace.log("read fd={} buf={*} len={}", .{ fd, buf, len });
    const rc = os.system.read(fd, buf, len);
    switch (os.errno(rc)) {
        .SUCCESS => return @as(isize, @intCast(rc)),
        else => |e| {
            c.errno = @intFromEnum(e);
            return -1;
        },
    }
}

// --------------------------------------------------------------------------------
// string
// --------------------------------------------------------------------------------
export fn strdup(s: [*:0]const u8) callconv(.C) ?[*:0]u8 {
    trace.log("strdup '{}'", .{trace.fmtStr(s)});
    const len = c.strlen(s);
    const optional_new_s = @as(?[*]u8, @ptrCast(c.malloc(len + 1)));
    if (optional_new_s) |new_s| {
        _ = c.strcpy(new_s, s);
    }
    return @as([*:0]u8, @ptrCast(optional_new_s)); // TODO: use std.meta.assumeSentinel if it's brought back
}

// --------------------------------------------------------------------------------
// stdlib
// --------------------------------------------------------------------------------
export fn mkstemp(template: [*:0]u8) callconv(.C) c_int {
    return mkostemp(template, 0, 0);
}

export fn mkostemp(template: [*:0]u8, suffixlen: c_int, flags: c_int) callconv(.C) c_int {
    trace.log("mkstemp '{}'", .{trace.fmtStr(template)});

    if (builtin.os.tag == .windows) {
        @panic("mkostemp not implemented in Windows");
    }

    if (flags != 0) {
        @panic("nonzero flags not handled");
    }

    const rand_part: *[6]u8 = blk: {
        const len = c.strlen(template);
        if (6 + suffixlen > len) {
            c.errno = c.EINVAL;
            return -1;
        }
        const rand_part_off = len - @as(usize, @intCast(suffixlen)) - 6;
        break :blk @as(*[6]u8, @ptrCast(template + rand_part_off));
    };

    if (!std.mem.eql(u8, rand_part, "XXXXXX")) {
        c.errno = c.EINVAL;
        return -1;
    }

    const max_attempts = 200;
    var attempt: u32 = 0;
    while (true) : (attempt += 1) {
        randomizeTempFilename(rand_part);
        const fd = os.system.open(
            template,
            linux.O{ .ACCMODE = .RDWR, .CREAT = true, .EXCL = true },
            0o600,
        );
        switch (os.errno(fd)) {
            .SUCCESS => return @as(c_int, @intCast(fd)),
            else => |e| {
                if (attempt >= max_attempts) {
                    // TODO: should we restore rand_part back to XXXXXX?
                    c.errno = @intFromEnum(e);
                    return -1;
                }
            },
        }
    }
}

const filename_char_set =
    "+,-.0123456789=@ABCDEFGHIJKLMNOPQRSTUVWXYZ" ++
    "_abcdefghijklmnopqrstuvwxyz";
fn randToFilenameChar(r: u8) u8 {
    return filename_char_set[r % filename_char_set.len];
}

fn randomizeTempFilename(slice: *[6]u8) void {
    var randoms: [6]u8 = undefined;
    {
        // previously used time-seeded PRNG (predictable)
        std.crypto.random.bytes(&randoms);
    }
    var i: usize = 0;
    while (i < slice.len) : (i += 1) {
        slice[i] = randToFilenameChar(randoms[i]);
    }
}

// --------------------------------------------------------------------------------
// stdio
// --------------------------------------------------------------------------------
export fn fileno(stream: *c.FILE) callconv(.C) c_int {
    if (builtin.os.tag == .windows) {
        // this probably isn't right, but might be fine for an initial implementation
        return @as(c_int, @intCast(@intFromPtr(stream.fd)));
    }
    @panic("fileno not implemented");
}

export fn popen(command: [*:0]const u8, mode: [*:0]const u8) callconv(.C) *c.FILE {
    trace.log("popen '{}' mode='{s}'", .{ trace.fmtStr(command), mode });
    @panic("popen not implemented");
}
export fn pclose(stream: *c.FILE) callconv(.C) c_int {
    _ = stream;
    @panic("pclose not implemented");
}

export fn fdopen(fd: c_int, mode: [*:0]const u8) callconv(.C) ?*c.FILE {
    trace.log("fdopen {d} mode={s}", .{ fd, mode });
    if (builtin.os.tag == .windows) @panic("not impl");

    const file = cstd.__zreserveFile() orelse {
        c.errno = c.ENOMEM;
        return null;
    };
    file.fd = fd;
    file.eof = 0;
    return file;
}

// --------------------------------------------------------------------------------
// unistd
// --------------------------------------------------------------------------------
comptime {
    if (builtin.os.tag != .windows) @export(&close, .{ .name = "close" });
}
fn close(fd: c_int) callconv(.C) c_int {
    trace.log("close {}", .{fd});
    os.close(fd);
    return 0;
}

export fn access(path: [*:0]const u8, amode: c_int) callconv(.C) c_int {
    trace.log("access '{}' mode=0x{x}", .{ trace.fmtStr(path), amode });
    @panic("acces not implemented");
}

export fn unlink(path: [*:0]const u8) callconv(.C) c_int {
    if (builtin.os.tag == .windows)
        @panic("windows unlink not implemented");

    switch (os.errno(os.system.unlink(path))) {
        .SUCCESS => return 0,
        else => |e| {
            c.errno = @intFromEnum(e);
            return -1;
        },
    }
}

export fn _exit(status: c_int) callconv(.C) noreturn {
    if (builtin.os.tag == .windows) {
        os.windows.kernel32.ExitProcess(@as(c_uint, @bitCast(status)));
    }
    if (builtin.os.tag == .wasi) {
        os.wasi.proc_exit(status);
    }
    if (builtin.os.tag == .linux and !builtin.single_threaded) {
        // TODO: is this right?
        linux.exit_group(status);
    }
    os.system.exit(status);
}

export fn isatty(fd: c_int) callconv(.C) c_int {
    if (builtin.os.tag == .windows)
        @panic("isatty not supported on windows (yet?)");

    var size: c.winsize = undefined;
    switch (os.errno(os.system.ioctl(fd, c.TIOCGWINSZ, @intFromPtr(&size)))) {
        .SUCCESS => return 1,
        .BADF => {
            c.errno = c.ENOTTY;
            return 0;
        },
        else => return 0,
    }
}

// --------------------------------------------------------------------------------
// sys/time
// --------------------------------------------------------------------------------
comptime {
    std.debug.assert(@sizeOf(c.timespec) == @sizeOf(os.timespec));
    if (builtin.os.tag != .windows) {
        std.debug.assert(c.CLOCK_REALTIME == @intFromEnum(os.CLOCK.REALTIME));
    }
}

export fn clock_gettime(clk_id: c.clockid_t, tp: *os.timespec) callconv(.C) c_int {
    if (builtin.os.tag == .windows) {
        if (clk_id == c.CLOCK_REALTIME) {
            var ft: os.windows.FILETIME = undefined;
            os.windows.kernel32.GetSystemTimeAsFileTime(&ft);
            // FileTime has a granularity of 100 nanoseconds and uses the NTFS/Windows epoch.
            const ft64 = (@as(u64, ft.dwHighDateTime) << 32) | ft.dwLowDateTime;
            const ft_per_s = std.time.ns_per_s / 100;
            tp.* = .{
                .tv_sec = @as(i64, @intCast(ft64 / ft_per_s)) + std.time.epoch.windows,
                .tv_nsec = @as(c_long, @intCast(ft64 % ft_per_s)) * 100,
            };
            return 0;
        }
        // TODO POSIX implementation of CLOCK.MONOTONIC on Windows.
        std.debug.panic("clk_id {} not implemented on Windows", .{clk_id});
    }

    switch (os.errno(os.system.clock_gettime(@enumFromInt(clk_id), tp))) {
        .SUCCESS => return 0,
        else => |e| {
            c.errno = @intFromEnum(e);
            return -1;
        },
    }
}

export fn gettimeofday(tv: *c.timeval, tz: *anyopaque) callconv(.C) c_int {
    trace.log("gettimeofday tv={*} tz={*}", .{ tv, tz });
    @panic("gettimeofday not implemented");
}

export fn setitimer(which: c_int, value: *const c.itimerval, avalue: *c.itimerval) callconv(.C) c_int {
    trace.log("setitimer which={}", .{which});
    _ = value;
    _ = avalue;
    @panic("setitimer not implemented");
}

// --------------------------------------------------------------------------------
// signal
// --------------------------------------------------------------------------------
export fn sigaction(sig: c_int, act: *const c.struct_sigaction, oact: *c.struct_sigaction) callconv(.C) c_int {
    trace.log("sigaction sig={}", .{sig});
    _ = act;
    _ = oact;
    @panic("sigaction not implemented");
}

// --------------------------------------------------------------------------------
// sys/stat.h
// --------------------------------------------------------------------------------
export fn chmod(path: [*:0]const u8, mode: c.mode_t) callconv(.C) c_int {
    trace.log("chmod '{s}' mode=0x{x}", .{ path, mode });
    @panic("chmod not implemented");
}

export fn fstat(fd: c_int, buf: *c.struct_stat) c_int {
    _ = fd;
    _ = buf;
    @panic("fstat not implemented");
}

export fn umask(mode: c.mode_t) callconv(.C) c.mode_t {
    trace.log("umask 0x{x}", .{mode});
    const old_mode = linux.syscall1(.umask, @as(usize, @intCast(mode)));
    switch (os.errno(old_mode)) {
        .SUCCESS => {},
        else => |e| std.debug.panic("umask syscall should never fail but got '{s}'", .{@tagName(e)}),
    }
    return @as(c.mode_t, @intCast(old_mode));
}

// --------------------------------------------------------------------------------
// libgen
// --------------------------------------------------------------------------------
export fn basename(path: ?[*:0]u8) callconv(.C) [*:0]u8 {
    trace.log("basename {}", .{trace.fmtStr(path)});
    const path_slice = std.mem.span(path orelse return @as([*:0]u8, @ptrFromInt(@intFromPtr("."))));
    const name = std.fs.path.basename(path_slice);
    const mut_ptr = @as([*:0]u8, @ptrFromInt(@intFromPtr(name.ptr)));
    if (name.len == 0) {
        if (path_slice.ptr[0] == '/') {
            path_slice.ptr[1] = 0;
            return path_slice.ptr;
        }
        return @as([*:0]u8, @ptrFromInt(@intFromPtr(".")));
    }
    if (mut_ptr[name.len] != 0) mut_ptr[name.len] = 0;
    return mut_ptr;
}

// --------------------------------------------------------------------------------
// termios
// --------------------------------------------------------------------------------
export fn tcgetattr(fd: c_int, ios: *linux.termios) callconv(.C) c_int {
    switch (os.errno(linux.tcgetattr(fd, ios))) {
        .SUCCESS => return 0,
        else => |errno| {
            c.errno = @intFromEnum(errno);
            return -1;
        },
    }
}

export fn tcsetattr(
    fd: c_int,
    optional_actions: c_int,
    ios: *const linux.termios,
) callconv(.C) c_int {
    switch (os.errno(linux.tcsetattr(fd, @as(linux.TCSA, @enumFromInt(optional_actions)), ios))) {
        .SUCCESS => return 0,
        else => |errno| {
            c.errno = @intFromEnum(errno);
            return -1;
        },
    }
}

// --------------------------------------------------------------------------------
// strings
// --------------------------------------------------------------------------------
export fn strcasecmp(a: [*:0]const u8, b: [*:0]const u8) callconv(.C) c_int {
    trace.log("strcasecmp {} {}", .{ trace.fmtStr(a), trace.fmtStr(b) });
    @panic("not impl");
    //    var a_next = a;
    //    var b_next = b;
    //    while (a_next[0] == b_next[0] and a_next[0] != 0) {
    //        a_next += 1;
    //        b_next += 1;
    //    }
    //    const result = @intCast(c_int, a_next[0]) -| @intCast(c_int, b_next[0]);
    //    trace.log("strcmp return {}", .{result});
    //    return result;
}

// --------------------------------------------------------------------------------
// sys/ioctl
// --------------------------------------------------------------------------------
export fn _ioctlArgPtr(fd: c_int, request: c_ulong, arg_ptr: *anyopaque) c_int {
    trace.log("ioctl fd={} request=0x{x} arg={*}", .{ fd, request, arg_ptr });
    const rc = linux.ioctl(fd, @as(u32, @intCast(request)), @intFromPtr(arg_ptr));
    switch (os.errno(rc)) {
        .SUCCESS => return @as(c_int, @intCast(rc)),
        else => |errno| {
            c.errno = @intFromEnum(errno);
            return -1;
        },
    }
}

// --------------------------------------------------------------------------------
// sys/select
// --------------------------------------------------------------------------------
export fn select(
    nfds: c_int,
    readfds: ?*c.fd_set,
    writefds: ?*c.fd_set,
    errorfds: ?*c.fd_set,
    timeout: ?*c.timespec,
) c_int {
    _ = nfds;
    _ = readfds;
    _ = writefds;
    _ = errorfds;
    _ = timeout;
    @panic("TODO: implement select");
}

// --------------------------------------------------------------------------------
// Windows
// --------------------------------------------------------------------------------
comptime {
    if (builtin.os.tag == .windows) {
        @export(fileno, .{ .name = "_fileno" });
        @export(isatty, .{ .name = "_isatty" });
        @export(popen, .{ .name = "_popen" });
        @export(pclose, .{ .name = "_pclose" });
    }
}
