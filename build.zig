const std = @import("std");
const GitRepoStep = @import("GitRepoStep.zig");
const libcbuild = @import("ziglibcbuild.zig");
const luabuild = @import("luabuild.zig");
const awkbuild = @import("awkbuild.zig");
const gnumakebuild = @import("gnumakebuild.zig");

pub fn build(b: *std.Build) void {
    const trace_enabled = b.option(bool, "trace", "enable libc tracing") orelse false;

    {
        const exe = b.addExecutable(.{
            .name = "genheaders",
            .root_source_file = b.path("src" ++ std.fs.path.sep_str ++ "genheaders.zig"),
            .target = b.resolveTargetQuery(std.Target.Query.parse(.{}) catch unreachable),
        });
        const run = b.addRunArtifact(exe);
        run.addArg(b.pathFromRoot("capi.txt"));
        b.step("genheaders", "Generate C Headers").dependOn(&run.step);
    }

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const generate_endian_header = b.addWriteFile(
        b.pathFromRoot("inc/gnu/endian.h"),
        b.fmt(
            \\#ifndef _ZIGLIBC_ENDIAN_H
            \\#define _ZIGLIBC_ENDIAN_H
            \\
            \\#define __BYTE_ORDER {d}
            \\#define _BYTE_ORDER __BYTE_ORDER
            \\#define BYTE_ORDER __BYTE_ORDER
            \\#define __LITTLE_ENDIAN 0
            \\#define __BIG_ENDIAN 1
            \\#define _LITTLE_ENDIAN 0
            \\#define _BIG_ENDIAN 1
            \\#define LITTLE_ENDIAN 0
            \\#define BIG_ENDIAN 1
            \\#endif
            \\
        , .{@intFromBool(target.result.cpu.arch.endian() == .big)}),
    );

    const zig_start = libcbuild.addZigStart(b, target, optimize);
    b.step("start", "").dependOn(&installArtifact(b, zig_start).step);

    const libc_full_static = libcbuild.addLibc(b, .{
        .variant = .full,
        .link = .static,
        .start = .ziglibc,
        .trace = trace_enabled,
        .target = target,
        .optimize = optimize,
    });
    libc_full_static.step.dependOn(&generate_endian_header.step);
    b.installArtifact(libc_full_static);
    const libc_full_shared = libcbuild.addLibc(b, .{
        .variant = .full,
        .link = .shared,
        .start = .ziglibc,
        .trace = trace_enabled,
        .target = target,
        .optimize = optimize,
    });
    libc_full_shared.step.dependOn(&generate_endian_header.step);
    b.step("libc-full-shared", "").dependOn(&installArtifact(b, libc_full_shared).step);
    // TODO: create a specs file?
    //       you can add -specs=file to the gcc command line to override values in the spec

    const libc_only_std_static = libcbuild.addLibc(b, .{
        .variant = .only_std,
        .link = .static,
        .start = .ziglibc,
        .trace = trace_enabled,
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(libc_only_std_static);
    const libc_only_std_shared = libcbuild.addLibc(b, .{
        .variant = .only_std,
        .link = .shared,
        .start = .ziglibc,
        .trace = trace_enabled,
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(libc_only_std_shared);

    const libc_only_posix = libcbuild.addLibc(b, .{
        .variant = .only_posix,
        .link = .static,
        .start = .ziglibc,
        .trace = trace_enabled,
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(libc_only_posix);

    const libc_only_linux = libcbuild.addLibc(b, .{
        .variant = .only_linux,
        .link = .static,
        .start = .ziglibc,
        .trace = trace_enabled,
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(libc_only_linux);

    const libc_only_gnu = libcbuild.addLibc(b, .{
        .variant = .only_gnu,
        .link = .static,
        .start = .ziglibc,
        .trace = trace_enabled,
        .target = target,
        .optimize = optimize,
    });
    libc_only_gnu.step.dependOn(&generate_endian_header.step);
    b.installArtifact(libc_only_gnu);

    const test_step = b.step("test", "Run unit tests");

    const test_env_exe = b.addExecutable(.{
        .name = "testenv",
        .root_source_file = b.path("test" ++ std.fs.path.sep_str ++ "testenv.zig"),
        .target = target,
        .optimize = optimize,
    });

    {
        const exe = addTest("hello", b, target, optimize, libc_only_std_static, zig_start);
        const run_step = b.addRunArtifact(exe);
        run_step.addCheck(.{ .expect_stdout_exact = "Hello\n" });
        test_step.dependOn(&run_step.step);
    }
    {
        const exe = addTest("strings", b, target, optimize, libc_only_std_static, zig_start);
        const run_step = b.addRunArtifact(exe);
        run_step.addCheck(.{ .expect_stdout_exact = "Success!\n" });
        test_step.dependOn(&run_step.step);
    }
    {
        const exe = addTest("fs", b, target, optimize, libc_only_std_static, zig_start);
        const run_step = b.addRunArtifact(test_env_exe);
        run_step.addArtifactArg(exe);
        run_step.addCheck(.{ .expect_stdout_exact = "Success!\n" });
        test_step.dependOn(&run_step.step);
    }
    {
        const exe = addTest("format", b, target, optimize, libc_only_std_static, zig_start);
        const run_step = b.addRunArtifact(test_env_exe);
        run_step.addArtifactArg(exe);
        run_step.addCheck(.{ .expect_stdout_exact = "Success!\n" });
        test_step.dependOn(&run_step.step);
    }
    {
        const exe = addTest("types", b, target, optimize, libc_only_std_static, zig_start);
        const run_step = b.addRunArtifact(exe);
        run_step.addArg(b.fmt("{}", .{@divExact(target.result.ptrBitWidth(), 8)}));
        run_step.addCheck(.{ .expect_stdout_exact = "Success!\n" });
        test_step.dependOn(&run_step.step);
    }
    {
        const exe = addTest("scanf", b, target, optimize, libc_only_std_static, zig_start);
        const run_step = b.addRunArtifact(exe);
        run_step.addCheck(.{ .expect_stdout_exact = "Success!\n" });
        test_step.dependOn(&run_step.step);
    }
    {
        const exe = addTest("strto", b, target, optimize, libc_only_std_static, zig_start);
        const run_step = b.addRunArtifact(exe);
        run_step.addCheck(.{ .expect_stdout_exact = "Success!\n" });
        test_step.dependOn(&run_step.step);
    }
    {
        const exe = addTest("getopt", b, target, optimize, libc_only_std_static, zig_start);
        addPosix(exe, libc_only_posix);
        {
            const run = b.addRunArtifact(exe);
            run.addCheck(.{ .expect_stdout_exact = "aflag=0, c_arg='(null)'\n" });
            test_step.dependOn(&run.step);
        }
        {
            const run = b.addRunArtifact(exe);
            run.addArgs(&.{"-a"});
            run.addCheck(.{ .expect_stdout_exact = "aflag=1, c_arg='(null)'\n" });
            test_step.dependOn(&run.step);
        }
        {
            const run = b.addRunArtifact(exe);
            run.addArgs(&.{ "-c", "hello" });
            run.addCheck(.{ .expect_stdout_exact = "aflag=0, c_arg='hello'\n" });
            test_step.dependOn(&run.step);
        }
    }

    // this test only works on linux right now
    if (target.result.os.tag == .linux) {
        const exe = addTest("jmp", b, target, optimize, libc_only_std_static, zig_start);
        const run_step = b.addRunArtifact(exe);
        run_step.addCheck(.{ .expect_stdout_exact = "Success!\n" });
        test_step.dependOn(&run_step.step);
    }

    addLibcTest(b, target, optimize, libc_only_std_static, zig_start, libc_only_posix);
    addTinyRegexCTests(b, target, optimize, libc_only_std_static, zig_start, libc_only_posix);
    _ = addLua(b, target, optimize, libc_only_std_static, libc_only_posix, zig_start);
    _ = addCmph(b, target, optimize, libc_only_std_static, zig_start, libc_only_posix);
    _ = addYacc(b, target, optimize, libc_only_std_static, zig_start, libc_only_posix);
    _ = addYabfc(b, target, optimize, libc_only_std_static, zig_start, libc_only_posix, libc_only_gnu);
    _ = addSecretGame(b, target, optimize, libc_only_std_static, zig_start, libc_only_posix, libc_only_gnu);
    _ = awkbuild.addAwk(b, target, optimize, libc_only_std_static, libc_only_posix, zig_start);
    _ = gnumakebuild.addGnuMake(b, target, optimize, libc_only_std_static, libc_only_posix, zig_start);

    _ = @import("busybox/build.zig").add(b, target, optimize, libc_only_std_static, libc_only_posix);
    _ = @import("ncurses/build.zig").add(b, target, optimize, libc_only_std_static, libc_only_posix);
}

// re-implements Build.installArtifact but also returns it
fn installArtifact(b: *std.Build, artifact: anytype) *std.Build.Step.InstallArtifact {
    const install = b.addInstallArtifact(artifact, .{});
    b.getInstallStep().dependOn(&install.step);
    return install;
}

fn addPosix(artifact: *std.Build.Step.Compile, zig_posix: *std.Build.Step.Compile) void {
    artifact.linkLibrary(zig_posix);
    artifact.addIncludePath(artifact.root_module.owner.path("inc" ++ std.fs.path.sep_str ++ "posix"));
}

fn addTest(
    comptime name: []const u8,
    b: *std.Build,
    target: anytype,
    optimize: anytype,
    libc_only_std_static: *std.Build.Step.Compile,
    zig_start: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path("test" ++ std.fs.path.sep_str ++ name ++ ".c"),
        .target = target,
        .optimize = optimize,
    });
    exe.addCSourceFiles(.{ .files = &.{"test" ++ std.fs.path.sep_str ++ "expect.c"}, .flags = &[_][]const u8{} });
    exe.addIncludePath(b.path("inc" ++ std.fs.path.sep_str ++ "libc"));
    exe.addIncludePath(b.path("inc" ++ std.fs.path.sep_str ++ "posix"));
    exe.linkLibrary(libc_only_std_static);
    exe.linkLibrary(zig_start);
    // TODO: should libc_only_std_static and zig_start be able to add library dependencies?
    if (target.result.os.tag == .windows) {
        exe.linkSystemLibrary("ntdll");
        exe.linkSystemLibrary("kernel32");
    }
    return exe;
}

fn addLibcTest(
    b: *std.Build,
    target: anytype,
    optimize: anytype,
    libc_only_std_static: *std.Build.Step.Compile,
    zig_start: *std.Build.Step.Compile,
    libc_only_posix: *std.Build.Step.Compile,
) void {
    const libc_test_repo = GitRepoStep.create(b, .{
        .url = "git://nsz.repo.hu:49100/repo/libc-test",
        .sha = "b7ec467969a53756258778fa7d9b045f912d1c93",
        .branch = null,
        .fetch_enabled = true,
    });
    const libc_test_path = libc_test_repo.path;
    const libc_test_step = b.step("libc-test", "run tests from the libc-test project");

    // inttypes
    inline for (.{
        "aio",
        "arpa_inet",
        "assert",
        "complex",
        "cpio",
        "ctype",
        "dirent",
        "dlfcn",
        "errno",
        "fcntl",
        "fenv",
        "float",
        "fmtmsg",
        "fnmatch",
        "ftw",
        "glob",
        "grp",
        "iconv",
        "inttypes",
        "iso646",
        "langinfo",
        "libgen",
        "limits",
        "locale",
        "main",
        "Makefile",
        "math",
        "monetary",
        "mqueue",
        "ndbm",
        "netdb",
        "net_if",
        "netinet_in",
        "netinet_tcp",
        "nl_types",
        "poll",
        "pthread",
        "pwd",
        "regex",
        "sched",
        "search",
        "semaphore",
        "setjmp",
        "signal",
        "spawn",
        "stdarg",
        "stdbool",
        "stddef",
        "stdint",
        "stdio",
        "stdlib",
        "string",
        "strings",
        "sys_ipc",
        "syslog",
        "sys_mman",
        "sys_msg",
        "sys_resource",
        "sys_select",
        "sys_sem",
        "sys_shm",
        "sys_socket",
        "sys_stat",
        "sys_statvfs",
        "sys_time",
        "sys_times",
        "sys_types",
        "sys_uio",
        "sys_un",
        "sys_utsname",
        "sys_wait",
        "tar",
        "termios",
        "tgmath",
        "time",
        "unistd",
        "utmpx",
        "wchar",
        "wctype",
        "wordexp",
    }) |name| {
        const lib = b.addObject(.{
            .name = "libc-test-api-" ++ name,
            .target = target,
            .optimize = optimize,
        });
        lib.addCSourceFile(.{ .file = .{ .cwd_relative = b.pathJoin(&.{ libc_test_path, "src", "api", name ++ ".c" }) } });
        lib.addIncludePath(b.path("inc" ++ std.fs.path.sep_str ++ "libc"));
        lib.step.dependOn(&libc_test_repo.step);
        libc_test_step.dependOn(&lib.step);
    }
    const libc_inc_path = b.pathJoin(&.{ libc_test_path, "src", "common" });
    const common_src = &[_][]const u8{
        "fdfill",
        "memfill",
        "mtest",
        "path",
        "print",
        "rand",
        "runtest",
        "setrlim",
        "utf8",
        "vmfill",
    };

    // strtol, it seems there might be some disagreement between libc-test/glibc
    // about how strtoul interprets negative numbers, so leaving out strtol for now
    inline for (.{
        "argv",
        "basename",
        "clocale_mbfuncs",
        "clock_gettime",
        "crypt",
        "dirname",
        "dlopen",
        "dlopen_dso",
        "env",
        "fcntl",
        "fdopen",
        "fnmatch",
        "fscanf",
        "fwscanf",
        "iconv_open",
        "inet_pton",
        "ipc_msg",
        "ipc_sem",
        "ipc_shm",
        "mbc",
        "memstream",
        "popen",
        "pthread_cancel",
        "pthread_cancel-points",
        "pthread_cond",
        "pthread_mutex",
        "pthread_mutex_pi",
        "pthread_robust",
        "pthread_tsd",
        "qsort",
        "random",
        "search_hsearch",
        "search_insque",
        "search_lsearch",
        "search_tsearch",
        "sem_init",
        "sem_open",
        "setjmp",
        "snprintf",
        "socket",
        "spawn",
        "sscanf",
        "sscanf_long",
        "stat",
        "strftime",
        "string",
        "string_memcpy",
        "string_memmem",
        "string_memset",
        "string_strchr",
        "string_strcspn",
        "string_strstr",
        "strptime",
        "strtod",
        "strtod_long",
        "strtod_simple",
        "strtof",
        "strtol",
        "strtold",
        "swprintf",
        "tgmath",
        "time",
        "tls_align",
        "tls_align_dlopen",
        "tls_align_dso",
        "tls_init",
        "tls_init_dlopen",
        "tls_init_dso",
        "tls_local_exec",
        "udiv",
        "ungetc",
        "utime",
        "vfork",
        "wcsstr",
        "wcstol",
    }) |name| {
        const exe = b.addExecutable(.{
            .name = "libc-test-functional-" ++ name,
            .target = target,
            .optimize = optimize,
        });
        exe.addCSourceFile(.{ .file = .{ .cwd_relative = b.pathJoin(&.{ libc_test_path, "src", "functional", name ++ ".c" }) } });
        exe.addCSourceFiles(.{
            .files = common_src,
            .root = .{ .cwd_relative = b.pathJoin(&.{ libc_test_path, "src", "common" }) },
            .flags = &.{},
        });
        exe.step.dependOn(&libc_test_repo.step);
        exe.addIncludePath(.{ .cwd_relative = libc_inc_path });
        exe.addIncludePath(b.path("inc" ++ std.fs.path.sep_str ++ "libc"));
        exe.addIncludePath(b.path("inc" ++ std.fs.path.sep_str ++ "posix"));
        exe.linkLibrary(libc_only_std_static);
        exe.linkLibrary(zig_start);
        exe.linkLibrary(libc_only_posix);
        // TODO: should libc_only_std_static and zig_start be able to add library dependencies?
        if (target.result.os.tag == .windows) {
            exe.linkSystemLibrary("ntdll");
            exe.linkSystemLibrary("kernel32");
        }
        libc_test_step.dependOn(&b.addRunArtifact(exe).step);
    }
}

fn addTinyRegexCTests(
    b: *std.Build,
    target: anytype,
    optimize: anytype,
    libc_only_std_static: *std.Build.Step.Compile,
    zig_start: *std.Build.Step.Compile,
    zig_posix: *std.Build.Step.Compile,
) void {
    const repo = GitRepoStep.create(b, .{
        .url = "https://github.com/marler8997/tiny-regex-c",
        .sha = "95ef2ad35d36783d789b0ade3178b30a942f085c",
        .branch = "nocompile",
        .fetch_enabled = true,
    });

    const re_step = b.step("re-tests", "run the tiny-regex-c tests");
    inline for (&[_][]const u8{ "test1", "test3" }) |test_name| {
        const exe = b.addExecutable(.{
            .name = "re" ++ test_name,
            .root_source_file = null,
            .target = target,
            .optimize = optimize,
        });
        //b.installArtifact(exe);
        exe.step.dependOn(&repo.step);
        const repo_path = repo.getPath(&exe.step);
        var files = std.ArrayList([]const u8).init(b.allocator);
        const sources = [_][]const u8{
            "re.c", "tests" ++ std.fs.path.sep_str ++ test_name ++ ".c",
        };
        for (sources) |src| {
            files.append(src) catch unreachable;
        }

        exe.addCSourceFiles(.{
            .files = files.toOwnedSlice() catch unreachable,
            // HACK: absolute path
            .root = .{ .cwd_relative = repo_path },
            .flags = &[_][]const u8{
                "-std=c99",
            },
        });
        exe.addIncludePath(.{ .cwd_relative = repo_path });
        exe.addIncludePath(b.path("inc/libc"));
        exe.addIncludePath(b.path("inc/posix"));
        exe.linkLibrary(libc_only_std_static);
        exe.linkLibrary(zig_start);
        exe.linkLibrary(zig_posix);
        // TODO: should libc_only_std_static and zig_start be able to add library dependencies?
        if (target.result.os.tag == .windows) {
            exe.linkSystemLibrary("ntdll");
            exe.linkSystemLibrary("kernel32");
        }

        //const step = b.step("re", "build the re (tiny-regex-c) tool");
        //step.dependOn(&exe.install_step.?.step);
        const run = b.addRunArtifact(exe);
        re_step.dependOn(&run.step);
    }
}

fn addLua(
    b: *std.Build,
    target: anytype,
    optimize: anytype,
    libc_only_std_static: *std.Build.Step.Compile,
    libc_only_posix: *std.Build.Step.Compile,
    zig_start: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const lua_repo = GitRepoStep.create(b, .{
        .url = "https://github.com/lua/lua",
        .sha = "5d708c3f9cae12820e415d4f89c9eacbe2ab964b",
        .branch = "v5.4.4",
        .fetch_enabled = true,
    });
    const lua_exe = b.addExecutable(.{
        .name = "lua",
        .target = target,
        .optimize = optimize,
    });
    lua_exe.step.dependOn(&lua_repo.step);
    const install = b.addInstallArtifact(lua_exe, .{});
    // doesn't compile for windows for some reason
    if (target.result.os.tag != .windows) {
        b.getInstallStep().dependOn(&install.step);
    }
    const lua_repo_path = lua_repo.getPath(&lua_exe.step);
    var files = std.ArrayList([]const u8).init(b.allocator);
    files.append("lua.c") catch unreachable;
    inline for (luabuild.core_objects) |obj| {
        files.append(obj ++ ".c") catch unreachable;
    }
    inline for (luabuild.aux_objects) |obj| {
        files.append(obj ++ ".c") catch unreachable;
    }
    inline for (luabuild.lib_objects) |obj| {
        files.append(obj ++ ".c") catch unreachable;
    }

    lua_exe.addCSourceFiles(.{
        .files = files.toOwnedSlice() catch unreachable,
        .root = .{ .cwd_relative = lua_repo_path },
        .flags = &[_][]const u8{
            "-nostdinc",
            "-nostdlib",
            "-std=c99",
        },
    });

    lua_exe.addIncludePath(b.path("inc" ++ std.fs.path.sep_str ++ "libc"));
    lua_exe.linkLibrary(libc_only_std_static);
    lua_exe.linkLibrary(libc_only_posix);
    lua_exe.linkLibrary(zig_start);
    // TODO: should libc_only_std_static and zig_start be able to add library dependencies?
    if (target.result.os.tag == .windows) {
        lua_exe.addIncludePath(b.path("inc/win32"));
        lua_exe.linkSystemLibrary("ntdll");
        lua_exe.linkSystemLibrary("kernel32");
    }

    const step = b.step("lua", "build/install the LUA interpreter");
    step.dependOn(&install.step);

    const test_step = b.step("lua-test", "Run the lua tests");

    for ([_][]const u8{ "bwcoercion.lua", "tracegc.lua" }) |test_file| {
        var run_test = b.addRunArtifact(lua_exe);
        run_test.addArg(b.pathJoin(&.{ lua_repo_path, "testes", test_file }));
        test_step.dependOn(&run_test.step);
    }

    return lua_exe;
}

fn addCmph(
    b: *std.Build,
    target: anytype,
    optimize: anytype,
    libc_only_std_static: *std.Build.Step.Compile,
    zig_start: *std.Build.Step.Compile,
    zig_posix: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const repo = GitRepoStep.create(b, .{
        //.url = "https://git.code.sf.net/p/cmph/git",
        .url = "https://github.com/bonitao/cmph",
        .sha = "abd5e1e17e4d51b3e24459ab9089dc0522846d0d",
        .branch = null,
        .fetch_enabled = true,
    });

    const config_step = b.addWriteFile(
        b.pathJoin(&.{ repo.path, "src", "config.h" }),
        "#define VERSION \"1.0\"",
    );
    config_step.step.dependOn(&repo.step);

    const exe = b.addExecutable(.{
        .name = "cmph",
        .target = target,
        .optimize = optimize,
    });
    const install = installArtifact(b, exe);
    exe.step.dependOn(&repo.step);
    exe.step.dependOn(&config_step.step);
    const repo_path = repo.getPath(&exe.step);
    const sources = [_][]const u8{
        "main.c",        "cmph.c",         "hash.c",           "chm.c",             "bmz.c",          "bmz8.c",   "brz.c",          "fch.c",
        "bdz.c",         "bdz_ph.c",       "chd_ph.c",         "chd.c",             "jenkins_hash.c", "graph.c",  "vqueue.c",       "buffer_manager.c",
        "fch_buckets.c", "miller_rabin.c", "compressed_seq.c", "compressed_rank.c", "buffer_entry.c", "select.c", "cmph_structs.c",
    };

    exe.addCSourceFiles(.{
        .files = &sources,
        .root = .{ .cwd_relative = b.pathJoin(&.{ repo_path, "src" }) },
        .flags = &[_][]const u8{
            "-std=c11",
        },
    });

    exe.addIncludePath(b.path("inc/libc"));
    exe.addIncludePath(b.path("inc/posix"));
    exe.addIncludePath(b.path("inc/gnu"));
    exe.linkLibrary(libc_only_std_static);
    exe.linkLibrary(zig_start);
    exe.linkLibrary(zig_posix);
    // TODO: should libc_only_std_static and zig_start be able to add library dependencies?
    if (target.result.os.tag == .windows) {
        exe.linkSystemLibrary("ntdll");
        exe.linkSystemLibrary("kernel32");
    }

    const step = b.step("cmph", "build the cmph tool");
    step.dependOn(&install.step);

    return exe;
}

fn addYacc(
    b: *std.Build,
    target: anytype,
    optimize: anytype,
    libc_only_std_static: *std.Build.Step.Compile,
    zig_start: *std.Build.Step.Compile,
    zig_posix: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const repo = GitRepoStep.create(b, .{
        .url = "https://github.com/ibara/yacc",
        .sha = "1a4138ce2385ec676c6d374245fda5a9cd2fbee2",
        .branch = null,
        .fetch_enabled = true,
    });

    const config_step = b.addWriteFile(b.pathJoin(&.{ repo.path, "config.h" }),
        \\// for simplicity just don't supported __unused
        \\#define __unused
        \\// for simplicity we're just not supporting noreturn
        \\#define __dead
        \\//#define HAVE_PROGNAME
        \\//#define HAVE_ASPRINTF
        \\//#define HAVE_PLEDGE
        \\//#define HAVE_REALLOCARRAY
        \\#define HAVE_STRLCPY
        \\
    );
    config_step.step.dependOn(&repo.step);
    const gen_progname_step = b.addWriteFile(b.pathJoin(&.{ repo.path, "progname.c" }),
        \\// workaround __progname not defined, https://github.com/ibara/yacc/pull/1
        \\char *__progname;
        \\
    );
    gen_progname_step.step.dependOn(&repo.step);

    const exe = b.addExecutable(.{
        .name = "yacc",
        .target = target,
        .optimize = optimize,
    });
    const install = installArtifact(b, exe);
    exe.step.dependOn(&repo.step);
    exe.step.dependOn(&config_step.step);
    exe.step.dependOn(&gen_progname_step.step);
    const repo_path = repo.getPath(&exe.step);
    const sources = [_][]const u8{
        "closure.c",  "error.c",  "lalr.c",    "lr0.c",      "main.c",     "mkpar.c",    "output.c", "reader.c",
        "skeleton.c", "symtab.c", "verbose.c", "warshall.c", "portable.c", "progname.c",
    };
    exe.addCSourceFiles(.{
        .files = &sources,
        .root = .{ .cwd_relative = repo_path },
        .flags = &[_][]const u8{
            "-std=c90",
        },
    });

    exe.addIncludePath(b.path("inc/libc"));
    exe.addIncludePath(b.path("inc/posix"));
    exe.linkLibrary(libc_only_std_static);
    exe.linkLibrary(zig_start);
    exe.linkLibrary(zig_posix);
    // TODO: should libc_only_std_static and zig_start be able to add library dependencies?
    if (target.result.os.tag == .windows) {
        exe.linkSystemLibrary("ntdll");
        exe.linkSystemLibrary("kernel32");
    }

    const step = b.step("yacc", "build the yacc tool");
    step.dependOn(&install.step);

    return exe;
}

fn addYabfc(
    b: *std.Build,
    target: anytype,
    optimize: anytype,
    libc_only_std_static: *std.Build.Step.Compile,
    zig_start: *std.Build.Step.Compile,
    zig_posix: *std.Build.Step.Compile,
    zig_gnu: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const repo = GitRepoStep.create(b, .{
        .url = "https://github.com/julianneswinoga/yabfc",
        .sha = "a789be25a0918d330b7a4de12db0d33e0785f244",
        .branch = null,
        .fetch_enabled = true,
    });

    const exe = b.addExecutable(.{
        .name = "yabfc",
        .target = target,
        .optimize = optimize,
    });
    const install = installArtifact(b, exe);
    exe.step.dependOn(&repo.step);
    const repo_path = repo.getPath(&exe.step);
    const sources = [_][]const u8{
        "assembly.c", "elfHelper.c", "helpers.c", "optimize.c", "yabfc.c",
    };
    exe.addCSourceFiles(.{
        .files = &sources,
        .root = .{ .cwd_relative = repo_path },
        .flags = &[_][]const u8{
            "-std=c99",
        },
    });

    exe.addIncludePath(b.path("inc/libc"));
    exe.addIncludePath(b.path("inc/posix"));
    exe.addIncludePath(b.path("inc/linux"));
    exe.addIncludePath(b.path("inc/gnu"));
    exe.linkLibrary(libc_only_std_static);
    exe.linkLibrary(zig_start);
    exe.linkLibrary(zig_posix);
    exe.linkLibrary(zig_gnu);
    // TODO: should libc_only_std_static and zig_start be able to add library dependencies?
    if (target.result.os.tag == .windows) {
        exe.linkSystemLibrary("ntdll");
        exe.linkSystemLibrary("kernel32");
    }

    const step = b.step("yabfc", "build/install the yabfc tool (Yet Another BrainFuck Compiler)");
    step.dependOn(&install.step);

    return exe;
}

fn addSecretGame(
    b: *std.Build,
    target: anytype,
    optimize: anytype,
    libc_only_std_static: *std.Build.Step.Compile,
    zig_start: *std.Build.Step.Compile,
    zig_posix: *std.Build.Step.Compile,
    zig_gnu: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const repo = GitRepoStep.create(b, .{
        .url = "https://github.com/ethinethin/Secret",
        .sha = "8ec8442f84f8bed2cb3985455e7af4d1ce605401",
        .branch = null,
        .fetch_enabled = true,
    });

    const exe = b.addExecutable(.{
        .name = "secret",
        .target = target,
        .optimize = optimize,
    });
    const install = b.addInstallArtifact(exe, .{});
    exe.step.dependOn(&repo.step);
    const repo_path = repo.getPath(&exe.step);

    const sources = [_][]const u8{
        "main.c", "inter.c", "input.c", "items.c", "rooms.c", "linenoise/linenoise.c",
    };
    exe.addCSourceFiles(.{
        .files = &sources,
        .root = .{ .cwd_relative = repo_path },
        .flags = &[_][]const u8{
            "-std=c90",
        },
    });

    exe.addIncludePath(b.path("inc/libc"));
    exe.addIncludePath(b.path("inc/posix"));
    exe.addIncludePath(b.path("inc/linux"));
    exe.addIncludePath(b.path("inc/gnu"));
    exe.linkLibrary(libc_only_std_static);
    exe.linkLibrary(zig_start);
    exe.linkLibrary(zig_posix);
    exe.linkLibrary(zig_gnu);
    // TODO: should libc_only_std_static and zig_start be able to add library dependencies?
    if (target.result.os.tag == .windows) {
        exe.linkSystemLibrary("ntdll");
        exe.linkSystemLibrary("kernel32");
    }

    const step = b.step("secret", "build/install the secret game");
    step.dependOn(&install.step);

    return exe;
}
