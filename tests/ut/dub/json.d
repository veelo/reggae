module tests.ut.dub.json;


import unit_threaded;
import reggae;
import reggae.dub.json;
import std.string;

@("foobar.json gets parsed correctly")
unittest {
    import std.format: format;
    const path = "/path/to";
    const info = getDubInfo(import("foobar.json").format(path, path, path, path, path, path, path, path, path, path, path));
    info.shouldEqual(
        DubInfo(
            [
                DubPackage(
                    "foo", //name
                    "/path/to", //path
                    "/path/to/source/app.d", // mainSourceFile
                    "foo", // targetFileName
                    [], // dflags
                    [], // lflags
                    ["/path/to/source/", "/path/to/bar/source/"], // importPaths
                    [], // stringImportPaths
                    ["/path/to/source/app.d"], // sourceFiles
                    TargetType.executable,
                    ["lefoo", "Have_foo", "Have_bar"], // versions
                    ["bar"], // dependencies
                    [], // libs
                    true, // active
                    [], // preBuildCommands
                    [], //postBuildCommands
                ),
                DubPackage(
                    "bar", //name
                    "/path/to/bar", //path
                    "", // mainSourceFile
                    "bar", // targetFileName
                    [], // dflags
                    [], // lflags
                    ["/path/to/bar/source/"], // importPaths
                    [], // stringImportPaths
                    ["/path/to/bar/source/bar.d"], // sourceFiles
                    TargetType.staticLibrary,
                    ["lefoo", "Have_bar"], // versions
                    [], // dependencies
                    [], // libs
                    true, // active
                    [], // preBuildCommands
                    [], //postBuildCommands
                ),
            ]
        )
    );
}

@("PACKAGE_DIR")
unittest {
    const jsonString = q{
        {
            "targets": [
                {
                    "buildSettings": {
                        "targetName": "lepackage",
                        "targetPath": "/dub/packages/lepackage",
                        "dflags": [],
                        "lflags": ["-L$PACKAGE_DIR"],
                        "importPaths": ["$PACKAGE_DIR/imports"],
                        "stringImportPaths": ["$PACKAGE_DIR/stringImports"],
                        "sourceFiles": [
                            "$PACKAGE_DIR/foo.o",
                            "src/file.d"
                        ]
                    }
                },
                {
                    "buildSettings": {
                        "targetName": "dep",
                        "targetPath": "/dub/packages/dep",
                        "dflags": [],
                        "lflags": [],
                        "importPaths": [],
                        "stringImportPaths": [],
                        "sourceFiles": [
                            "$PACKAGE_DIR/bar.o",
                            "src/dep.d"
                        ]
                    }
                }
            ]
        }
    };

    getDubInfo(jsonString).shouldEqual(
        DubInfo(
            [
                DubPackage(
                    "lepackage",
                    "/dub/packages/lepackage",
                    "", // mainSourceFile
                    "lepackage", // targetFileName
                    [], // dflags
                    ["-L/dub/packages/lepackage"],
                    ["/dub/packages/lepackage/imports"],
                    ["/dub/packages/lepackage/stringImports"],
                    ["/dub/packages/lepackage/foo.o", "src/file.d"],
                    TargetType.autodetect, // targetType
                    [], // versions
                    [], // dependencies
                    [], // libs
                    true, // active
                ),
                DubPackage(
                    "dep",
                    "/dub/packages/dep",
                    "", // mainSourceFile
                    "dep", //targetFileName
                    [], // dflags
                    [], // lflags
                    [], // importPaths
                    [], // stringImportPaths
                    ["/dub/packages/dep/bar.o", "src/dep.d"],
                    TargetType.autodetect, // targetType
                    [], // versions
                    [], // dependencies
                    [], // libs
                    true, // active
                ),
            ]
    ));
}


@("travis string")
unittest {
    getDubInfo(import("travis.json"));
}