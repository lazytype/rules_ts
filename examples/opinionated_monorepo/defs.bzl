load("@aspect_bazel_lib//lib:write_source_files.bzl", "write_source_files")
load("@aspect_rules_ts//ts:defs.bzl", "ts_config", _ts_project = "ts_project")

def opinionated_ts_project(
        name,
        deps = [],
        **kwargs):
    tsconfig_result = _ts_config(
        project_name = name,
        tsconfig_name = "tsconfig",
    )

    _ts_project(
        name = name,
        deps = deps,
        tsconfig = tsconfig_result["target_name"],
        composite = True,
        transpiler = "tsc",
        **kwargs
    )

def _generate_tsconfig_file(project_name, tsconfig_name, tsconfig, tags = []):
    gen_target_name = "{}_tsconfig.update".format(project_name)
    gen_command = "bazel run //{}:{}".format(native.package_name(), gen_target_name)

    genrule_target_name = "{}_tsconfig".format(project_name)
    native.genrule(
        name = genrule_target_name,
        srcs = [],
        outs = ["{}_{}.generated.json".format(project_name, tsconfig_name)],
        cmd = "echo '// Generated, DO NOT EDIT MANUALLY. To update, run \"{gen_command}\"\n{tsconfig_contents}' > $@".format(
            gen_command = gen_command,
            tsconfig_contents = json.encode_indent(tsconfig, indent = "  "),
        ),
    )

    write_source_files(
        name = gen_target_name,
        files = {
            "{}.json".format(tsconfig_name): ":{}".format(genrule_target_name),
        },
        tags = tags + ["tsconfig"],
    )

def _ts_config(
        project_name,
        tsconfig_name,
        tsconfig_overrides = None,
        project_references = [],
        type_roots = [],
        visibility = None):
    """
    Generate a tsconfig.json for local development.

    Args:
        tsconfig_name: The name of the tsconfig file.
        tsconfig_overrides: A dictionary of tsconfig.json overrides.
        project_references: A list of project references.
        type_roots: A list of type roots.
        visibility: The visibility of the tsconfig.json file.
    """
    if tsconfig_overrides == None:
        tsconfig_overrides = {}

    relative_to_root = "/".join([".." for _ in native.package_name().split("/")])

    tsconfig_options = get_tsconfig_options(
        tsconfig = {
            "extends": "{}/tsconfig.base.json".format(relative_to_root),
        },
        project_references = project_references,
        type_roots = type_roots,
    )

    tsconfig = tsconfig_options["tsconfig"]

    paths = (
        tsconfig.get("compilerOptions", {}).get("paths", {}) |
        tsconfig_overrides.get("compilerOptions", {}).get("paths", {})
    )

    compiler_options = (
        tsconfig.get("compilerOptions", {}) |
        tsconfig_overrides.get("compilerOptions", {}) |
        ({"paths": paths} if paths else {})
    )

    tsconfig = (
        tsconfig |
        tsconfig_overrides |
        ({"compilerOptions": compiler_options} if compiler_options else {})
    )

    _generate_tsconfig_file(
        project_name = project_name,
        tsconfig_name = tsconfig_name,
        tsconfig = tsconfig,
    )

    ts_config(
        name = tsconfig_name,
        src = ":{}.json".format(tsconfig_name),
        deps = ["//:tsconfig_base"],
        visibility = visibility,
    )

    return dict(target_name = tsconfig_name)

TS_CONFIG = {}

def get_tsconfig_options(
        tsconfig = TS_CONFIG,
        project_references = [],
        type_roots = []):
    """
    Get the tsconfig.json options for a given tsconfig.json file.

    Args:
        tsconfig: The tsconfig.json file.
        project_references: A list of project references.
        type_roots: A list of type roots.

    Returns:
        A dictionary with the following keys:
            tsconfig: The tsconfig.json file.
            tsconfig_deps: A list of tsconfig.json dependencies.
    """
    tsconfig_deps = ["//:tsconfig_base"]
    tsconfig_references = []
    type_root_paths = []
    package_name = native.package_name()

    for ref in project_references:
        ref_path = ref.lstrip("/")
        relative_path = _relative_path(ref_path, package_name)
        tsconfig_references.append({"path": "{}/tsconfig.json".format(relative_path)})
        tsconfig_deps.append("{}:tsconfig".format(ref))

    current_package_depth = len(package_name.split("/"))
    relative_to_root = "/".join([".." for _ in range(current_package_depth)])

    paths = (
        tsconfig.get("compilerOptions", {}).get("paths", {}) |
        {"*": ["%s/*" % relative_to_root]}
    )

    type_root_paths.extend(tsconfig.get("compilerOptions", {}).get("typeRoots", []))
    for type_root in type_roots:
        type_root_paths.append(_relative_path(type_root.lstrip("/"), native.package_name()))

    exclude_patterns = tsconfig.get("exclude", []) + [
        "./{subpackage}/**/*".format(subpackage = subpackage)
        for subpackage in native.subpackages(include = ["*"], allow_empty = True)
    ]

    compiler_options = (
        tsconfig.get("compilerOptions", {}) |
        ({"composite": True}) |
        ({"paths": paths} if paths else {}) |
        ({"typeRoots": type_root_paths + ["{}/node_modules/@types".format(relative_to_root)]} if type_roots else {})
    )

    # Tests are always root nodes, so not composite
    test_compiler_options = compiler_options | {"composite": False}

    tsconfig = (
        tsconfig |
        ({"compilerOptions": compiler_options} if compiler_options else {}) |
        ({"references": tsconfig_references} if tsconfig_references else {}) |
        ({"exclude": exclude_patterns} if exclude_patterns else {})
    )

    test_tsconfig = (
        tsconfig |
        ({"compilerOptions": test_compiler_options} if test_compiler_options else {})
    )

    return dict(
        tsconfig = tsconfig,
        tsconfig_deps = tsconfig_deps,
        test_tsconfig = test_tsconfig,
    )

def _relative_path(target, start):
    """Copied from https://github.com/bazelbuild/bazel-skylib/pull/44

    Returns a relative path to `target` from `start`.

    Args:
      target: path that we want to get relative path to.
      start: path to directory from which we are starting.

    Returns:
      string: relative path to `target`.
    """
    t_pieces = target.split("/")
    s_pieces = start.split("/")
    common_part_len = 0

    for tp, rp in zip(t_pieces, s_pieces):
        if tp == rp:
            common_part_len += 1
        else:
            break

    result = [".."] * (len(s_pieces) - common_part_len)
    result += t_pieces[common_part_len:]

    path = "/".join(result) if len(result) > 0 else "."
    if not path.startswith("."):
        path = "./{}".format(path)

    return path
