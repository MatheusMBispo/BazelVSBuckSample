load("@rules_cc//cc:defs.bzl", "objc_library")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test", "ios_application")
load("@build_bazel_rules_apple//apple:apple.bzl", "apple_dynamic_framework_import")
load("@build_bazel_rules_apple//apple:resources.bzl", "apple_resource_bundle", "apple_resource_group")
load("//config:constants.bzl", "MINIMUM_OS_VERSION", "PRODUCT_BUNDLE_IDENTIFIER_PREFIX", "SWIFT_DEBUG_COMPILER_FLAGS")
load("//config:functions.bzl", "get_basename")

build_system = "bazel"

def exports_files_interface(
    files,
    ):
    native.exports_files(
        srcs = files,
        visibility = ["//visibility:public"],
    )

def resources_group_interface(
    name,
    files,
    bundled,
    ):
    if bundled:
        apple_resource_bundle(
            name = name,
            resources = files,
        )
    else:
        apple_resource_group(
            name = name,
            resources = files,
        )

def objc_library_interface(
    name,
    tests, # Unused for now, only used in buck
    srcs,
    headers,
    deps,
    resources,
    ):
    basenamed_headers = []
    exported_headers = []
    if len(headers) > 0:
        # Bazel does not support objc_library that depend on other objc_library
        # The following genrule is a workaround for it
        # See: https://github.com/bazelbuild/bazel/issues/9461 and https://github.com/thii/rules_apple_extras
        exported_headers_rule_name = name + "ExportedHeaders"
        exported_headers_path = "includedir"
        native.genrule(
            name = exported_headers_rule_name,
            srcs = headers,
            # Headers can be nested multiple levels, so we have to calculate their basenames
            outs = [exported_headers_path + "/" + name + "/" + get_basename(x) for x in headers],
            # Finally we copy all headers to the `exported_headers_path` directory
            cmd  = "cp $(SRCS) $(RULEDIR)" + "/" + exported_headers_path + "/" + name,
        )
        exported_headers = [":" + exported_headers_rule_name]

        # Bazel requires headers to be specified relative to the workspace
        # In order to work around that, it is possible to use a genrule to place all
        # headers under the same directory
        # See: https://docs.bazel.build/versions/master/be/objective-c.html#objc_library.includes
        basenamed_headers_rule_name = name + "BasenamedHeaders"
        basenamed_headers_path = "basenamed"
        native.genrule(
            name = basenamed_headers_rule_name,
            srcs = headers,
            outs = [basenamed_headers_path + "/" + get_basename(x) for x in headers],
            cmd  = "cp $(SRCS) $(RULEDIR)" + "/" + basenamed_headers_path,
        )
        basenamed_headers = [":" + basenamed_headers_rule_name]

    objc_library(
        name = name,
        srcs = srcs,
        # In order to make sure that the headers under the `exported_headers_path` directory are inside the sandbox 
        # we have to make the `basenamed_headers` and `exported_headers` a dependency of the `objc_library`: 
        # we can do that by setting it as the value for the `hdrs` argument
        # We also need the normal headers, so they appear when generating the xcode project
        hdrs = basenamed_headers + exported_headers + headers,
        deps = deps,
        data = resources,
        module_name = name,
        # Include the directory where the headers are. This will also be passed to rules depending on this one
        # See: https://docs.bazel.build/versions/master/be/objective-c.html#objc_library.includes
        includes = [exported_headers_path, basenamed_headers_path],
        enable_modules = True,
        visibility = ["//visibility:public"],
    )

def swift_library_interface(
    name,
    tests, # Unused for now, only used in buck
    srcs,
    deps,
    swift_compiler_flags,
    swift_version,
    resources,
    ):
    swift_library(
        name = name,
        srcs = srcs,
        deps = deps,
        data = resources,
        module_name = name,
        copts = swift_compiler_flags + ["-swift-version", swift_version],
        visibility = ["//visibility:public"],
    )

def objc_test_interface(
    name,
    srcs,
    deps,
    host_app,
    ):
    # return
    # For now having objc tests of objc libraries seems not possible. 
    # See: https://github.com/bazelbuild/bazel/pull/5905#issuecomment-535735561

    test_lib_name = name + "Lib"

    objc_library(
        name = test_lib_name,
        srcs = srcs,
        deps = deps,
        module_name = test_lib_name,
        enable_modules = True,
    )

    ios_unit_test(
        name = name,
        deps = [":" + test_lib_name],
        minimum_os_version = MINIMUM_OS_VERSION,
        runner = "//config/bazel_config:test_runner",
        test_host = host_app,
    )

def swift_test_interface(
    name,
    srcs,
    deps,
    swift_version,
    host_app,
    ):
    test_lib_name = name + "Lib"

    swift_library(
        name = test_lib_name,
        srcs = srcs,
        deps = deps,
        module_name = test_lib_name,
        copts = ["-swift-version", swift_version] + SWIFT_DEBUG_COMPILER_FLAGS,
    )

    ios_unit_test(
        name = name,
        deps = [":" + test_lib_name],
        minimum_os_version = MINIMUM_OS_VERSION,
        runner = "//config/bazel_config:test_runner",
        test_host = host_app,
    )

def prebuilt_dynamic_framework_interface(
    name,
    path,
    ):
    apple_dynamic_framework_import(
        name = name,
        framework_imports = native.glob([path + "/**",]),
        visibility = ["//visibility:public"],
    )


def application_interface(
    name,
    infoplist,
    main_target,
    strip_unused_symbols,
    ):
    linkopts = []
    if strip_unused_symbols == False:
        linkopts = ["-all_load"]

    ios_application(
        name = name,
        bundle_id = PRODUCT_BUNDLE_IDENTIFIER_PREFIX + name,
        families = ["iphone", "ipad",],
        infoplists = [infoplist],
        minimum_os_version = MINIMUM_OS_VERSION,
        deps = [main_target],
        linkopts = linkopts,
        visibility = ["//visibility:public"],
    )