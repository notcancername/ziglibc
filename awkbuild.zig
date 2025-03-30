const std = @import("std");
const GitRepoStep = @import("GitRepoStep.zig");

pub fn addAwk(
    b: *std.Build,
    target: anytype,
    optimize: anytype,
    libc_only_std_static: *std.Build.Step.Compile,
    zig_start: *std.Build.Step.Compile,
    zig_posix: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const repo = GitRepoStep.create(b, .{
        .url = "https://github.com/onetrueawk/awk",
        .sha = "9e248c317b88470fc86aa7c988919dc49452c88c",
        .branch = null,
    });

    //    const config_step = b.addWriteFile(
    //        b.pathJoin(&.{repo.path, "src", "config.h"}),
    //        "#define VERSION \"1.0\"",
    //    );
    //    config_step.step.dependOn(&repo.step);

    const exe = b.addExecutable(.{
        .name = "awk",
        .target = target,
        .optimize = optimize,
    });
    const install = b.addInstallArtifact(exe, .{});
    exe.step.dependOn(&repo.step);
    //    exe.step.dependOn(&config_step.step);
    const repo_path = repo.getPath(&exe.step);
    const sources = [_][]const u8{
        "main.c",
        "parse.c",
        "proto.c",
        "run.c",
        "tran.c",
        "b.c",
        "lex.c",
        "lib.c",
        "maketab.c",
    };

    exe.addCSourceFiles(.{
        .files = &sources,
        .root = .{ .cwd_relative = b.pathJoin(&.{repo_path}) },
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

    const step = b.step("awk", "build awk");
    step.dependOn(&install.step);

    return exe;
}
