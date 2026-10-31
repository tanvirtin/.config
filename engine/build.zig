const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const yaml_mod = b.createModule(.{
        .root_source_file = b.path("src/lib/yaml.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "tin",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("yaml", yaml_mod);
    b.installArtifact(exe);
    const install_tin_step = b.step("install-tin", "Install only Tin to the selected prefix");
    install_tin_step.dependOn(&b.addInstallArtifact(exe, .{}).step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const test_yaml_exe = b.addExecutable(.{
        .name = "test_yaml_one",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/test_yaml_one.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_yaml_exe.root_module.addImport("yaml", yaml_mod);
    b.installArtifact(test_yaml_exe);

    const yaml_suite_exe = b.addExecutable(.{
        .name = "test_yaml_suite",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/test_yaml_suite.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const yaml_fixture_exe = b.addExecutable(.{
        .name = "test_yaml_fixture",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/test_yaml_fixture.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const yaml_suite_options = b.addOptions();
    yaml_suite_options.addOptionPath("suite_exe", yaml_suite_exe.getEmittedBin());
    yaml_suite_options.addOptionPath("fixture_exe", yaml_fixture_exe.getEmittedBin());

    const yaml_suite_regression = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/test_yaml_suite_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    yaml_suite_regression.root_module.addOptions("build_options", yaml_suite_options);

    const run_step = b.step("run", "Run tin");
    run_step.dependOn(&run_cmd.step);

    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    bench_exe.root_module.addImport("yaml", yaml_mod);

    const bench_run = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run performance benchmarks");
    bench_step.dependOn(&bench_run.step);

    const unit_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    unit_test.root_module.addImport("yaml", yaml_mod);

    const flow_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/test_flow_parse.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    flow_test.root_module.addImport("yaml", yaml_mod);

    const test_runner_exe = b.addExecutable(.{
        .name = "test_runner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/test_runner.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const expression_suite_exe = b.addExecutable(.{
        .name = "expression_suite",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/expression_suite_main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    expression_suite_exe.root_module.addImport("yaml", yaml_mod);

    const test_run = b.addRunArtifact(test_runner_exe);
    test_run.addArtifactArg(exe);
    test_run.addArtifactArg(unit_test);
    test_run.addArtifactArg(flow_test);
    test_run.addArtifactArg(expression_suite_exe);
    test_run.addFileArg(b.path("tests/expression_suite.yml"));

    const test_step = b.step("test", "Run the local suite: unit, integration, flow, expressions, and yaml runner");
    test_step.dependOn(&test_run.step);
    test_step.dependOn(&b.addRunArtifact(yaml_suite_regression).step);

    const yaml_unit_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib/yaml.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(yaml_unit_test).step);

    const yamll_unit_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib/yamll.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    yamll_unit_test.root_module.addImport("yaml", yaml_mod);
    test_step.dependOn(&b.addRunArtifact(yamll_unit_test).step);

    const unit_step = b.step("test-unit", "Run unit tests only");
    unit_step.dependOn(&b.addRunArtifact(unit_test).step);
    unit_step.dependOn(&b.addRunArtifact(yaml_unit_test).step);
    unit_step.dependOn(&b.addRunArtifact(yamll_unit_test).step);

    const test_yaml_step = b.step("test-yaml", "Run YAML conformance against an explicit corpus: zig build test-yaml -- <corpus-dir>");
    const yaml_run = b.addRunArtifact(yaml_suite_exe);
    yaml_run.addArtifactArg(test_yaml_exe);
    yaml_run.addPassthruArgs();
    test_yaml_step.dependOn(&yaml_run.step);
}
