module tests.it.runtime.dub;


import tests.it.runtime;
import reggae.reggae;
import reggae.path: deabsolutePath;
import std.path: buildPath;


@("dub project with no reggaefile ninja")
@Tags(["dub", "ninja"])
unittest {

    import std.string: join;
    import std.algorithm: filter;

    with(immutable ReggaeSandbox("dub")) {
        shouldNotExist("reggaefile.d");
        writelnUt("\n\nReggae output:\n\n", runReggae("-b", "ninja", "--dflags=-g -debug").lines.join("\n"), "-----\n");
        shouldExist("reggaefile.d");
        auto output = ninja.shouldExecuteOk;
        output.shouldContain("-g -debug");

        shouldSucceed("atest").filter!(a => a != "").should ==
            [
                "Why hello!",
                "I'm immortal!"
            ];

        // there's only one UT in main.d which always fails
        shouldFail("ut");
    }
}

@("dub project with no reggaefile tup")
@Tags(["dub", "tup"])
unittest {
    with(immutable ReggaeSandbox("dub")) {
        runReggae("-b", "tup", "--dflags=-g -debug").
            shouldThrowWithMessage("dub integration not supported with the tup backend");
    }
}


@("dub project with no reggaefile and prebuild command")
@Tags(["dub", "ninja"])
unittest {
    with(immutable ReggaeSandbox("dub_prebuild")) {
        runReggae("-b", "ninja", "--dflags=-g -debug");
        ninja.shouldExecuteOk;
        shouldSucceed("ut");
    }
}


@("dub project with postbuild command")
@Tags(["dub", "ninja"])
unittest {
    with(immutable ReggaeSandbox("dub_postbuild")) {
        runReggae("-b", "ninja", "--dflags=-g -debug");
        ninja.shouldExecuteOk;
        shouldExist("foo.txt");
        shouldSucceed("postbuild");
    }
}


@("project with dependencies not on file system already no dub.selections.json")
@Tags(["dub", "ninja"])
unittest {

    import std.file: exists, rmdirRecurse;
    import std.process: environment;
    import std.path: buildPath;

    const cerealedDir = buildPath(environment["HOME"], ".dub/packages/cerealed-0.6.8");
    if(cerealedDir.exists)
        rmdirRecurse(cerealedDir);

    with(immutable ReggaeSandbox()) {
        writeFile("dub.json", `
        {
          "name": "depends_on_cerealed",
          "license": "MIT",
          "targetType": "executable",
          "dependencies": { "cerealed": "==0.6.8" }
        }`);
        writeFile("source/app.d", "void main() {}");

        runReggae("-b", "ninja");
    }
}


@("simple dub project with no main function but with unit tests")
@Tags(["dub", "ninja"])
unittest {
    import std.file: mkdirRecurse;
    import std.path: buildPath;

    with(immutable ReggaeSandbox()) {
        writeFile("dub.json", `
            {
              "name": "depends_on_cerealed",
              "license": "MIT",
              "targetType": "executable",
              "dependencies": { "cerealed": "==0.6.8" }
            }`);

        writeFile("reggaefile.d", q{
            import reggae;
            mixin build!(dubTestTarget!(CompilerFlags("-g -debug")));
        });

        mkdirRecurse(buildPath(testPath, "source"));
        writeFile("source/foo.d", `unittest { assert(false); }`);
        runReggae("-b", "ninja");
        ninja.shouldExecuteOk;

        shouldFail("ut");
    }
}


@("reggae/dub build should rebuild if dub.selections.json changes")
@Tags(["dub", "make"])
unittest {

    import std.process: execute;
    import std.path: buildPath;

    with(immutable ReggaeSandbox("dub")) {
        runReggae("-b", "make", "--dflags=-g -debug");
        make(["VERBOSE=1"]).shouldExecuteOk.shouldContain("-g -debug");
        {
            const ret = execute(["touch", buildPath(testPath, "dub.selections.json")]);
            ret.status.shouldEqual(0);
        }
        {
            const ret = execute(["make", "-C", testPath]);
            ret.output.shouldContain("eggae");
        }
    }
}

@("version from main package is used in dependent packages")
@Tags(["dub", "ninja"])
unittest {
    with(immutable ReggaeSandbox()) {
        writeFile("dub.sdl", `
            name "foo"
            versions "lefoo"
            targetType "executable"
            dependency "bar" path="bar"
        `);
        writeFile("source/app.d", q{
            void main() {
                import bar;
                import std.stdio;
                writeln(lebar);
            }
        });
        writeFile("bar/dub.sdl", `
            name "bar"
        `);
        writeFile("bar/source/bar.d", q{
            module bar;
            version(lefoo)
                int lebar() { return 3; }
            else
                int lebar() { return 42; }
        });
        runReggae("-b", "ninja");
        ninja.shouldExecuteOk;
        shouldSucceed("foo").shouldEqual(
            [
                "3",
            ]
        );
    }
}


@("sourceLibrary dependency")
@Tags(["dub", "ninja"])
unittest {
    with(immutable ReggaeSandbox()) {
        writeFile("dub.sdl", `
            name "foo"
            targetType "executable"
            dependency "bar" path="bar"
        `);
        writeFile("source/app.d", q{
            void main() {
                import bar;
                import std.stdio;
                writeln(lebar);
            }
        });
        writeFile("bar/dub.sdl", `
            name "bar"
            targetType "sourceLibrary"
        `);
        writeFile("bar/source/bar.d", q{
            module bar;
            int lebar() { return 3; }
        });
        runReggae("-b", "ninja");
        ninja.shouldExecuteOk;
    }
}

@("object source files")
@Tags(["dub", "ninja"])
unittest {
    with(immutable ReggaeSandbox()) {
        writeFile("dub.sdl", `
            name "foo"
            targetType "executable"
            dependency "bar" path="bar"
        `);
        writeFile("source/app.d", q{
            extern(C) int lebaz();
            void main() {
                import bar;
                import std.stdio;
                writeln(lebar);
                writeln(lebaz);
            }
        });
        writeFile("bar/dub.sdl", `
            name "bar"
            sourceFiles "../baz.o"
        `);
        writeFile("bar/source/bar.d", q{
            module bar;
            int lebar() { return 3; }
        });
        writeFile("baz.d", q{
            module baz;
            extern(C) int lebaz() { return 42; }
        });

        ["dmd", "-c", "baz.d"].shouldExecuteOk;
        runReggae("-b", "ninja");
        ninja.shouldExecuteOk;
    }
}


@("dub objs option path dependency")
@Tags("dub", "ninja", "dubObjsDir")
unittest {

    with(immutable ReggaeSandbox()) {

        writeFile("reggaefile.d", q{
            import reggae;
            mixin build!(dubDefaultTarget!());
        });

        writeFile("dub.sdl",`
            name "foo"
            targetType "executable"
            dependency "bar" path="bar"
        `);

        writeFile("source/app.d", q{
            import bar;
            void main() { add(2, 3); }
        });

        writeFile("bar/dub.sdl", `
            name "bar"
        `);

        writeFile("bar/source/bar.d", q{
            module bar;
            int add(int i, int j) { return i + j; }
        });

        const dubObjsDir = buildPath(testPath, "objsdir");
        const output = runReggae("-b", "ninja", "--dub-objs-dir=" ~ dubObjsDir);
        writelnUt(output);
        ninja.shouldExecuteOk;

        import std.path: buildPath;
        shouldExist(buildPath("objsdir",
                              testPath.deabsolutePath,
                              "foo.objs",
                              testPath.deabsolutePath,
                              "bar",
                              "source.o"));
    }
}

@("dub objs option registry dependency")
@Tags("dub", "ninja", "dubObjsDir")
unittest {

    import reggae.path: dubPackagesDir, deabsolutePath;

    with(immutable ReggaeSandbox()) {

        writeFile("reggaefile.d", q{
            import reggae;
            mixin build!(dubDefaultTarget!());
        });

        writeFile("dub.sdl",`
            name "foo"
            targetType "executable"
            dependency "dubnull" version="==0.0.1"
        `);

        writeFile("source/app.d", q{
            import dubnull;
            void main() { dummy(); }
        });

        const dubObjsDir = buildPath(testPath, "objsdir");
        const output = runReggae("-b", "ninja", "--dub-objs-dir=" ~ dubObjsDir);
        writelnUt(output);

        ninja.shouldExecuteOk;

        import std.path: buildPath;
        const dubNullDir = buildPath(dubPackagesDir, "dubnull-0.0.1", "dubnull").deabsolutePath;
        shouldExist(buildPath("objsdir",
                              testPath.deabsolutePath,
                              "foo.objs",
                              dubNullDir,
                              "source.o"));
    }
}


@("object source files with dub objs option")
@Tags("dub", "ninja", "dubObjsDir")
unittest {
    with(immutable ReggaeSandbox()) {
        writeFile("dub.sdl", `
            name "foo"
            targetType "executable"
            dependency "bar" path="bar"
        `);
        writeFile("source/app.d", q{
            extern(C) int lebaz();
            void main() {
                import bar;
                import std.stdio;
                writeln(lebar);
                writeln(lebaz);
            }
        });
        writeFile("bar/dub.sdl", `
            name "bar"
            sourceFiles "../baz.o"
        `);
        writeFile("bar/source/bar.d", q{
            module bar;
            int lebar() { return 3; }
        });
        writeFile("baz.d", q{
            module baz;
            extern(C) int lebaz() { return 42; }
        });

        ["dmd", "-c", "baz.d"].shouldExecuteOk;

        const output = runReggae("-b", "ninja", "--dub-objs-dir=" ~ testPath);
        writelnUt(output);

        ninja.shouldExecuteOk;
    }
}


@("dub project that depends on package with prebuild")
@Tags(["dub", "ninja"])
unittest {

    import std.path;

    with(immutable ReggaeSandbox("dub_depends_on_prebuild")) {

        copyProject("dub_prebuild", buildPath("..", "dub_prebuild"));

        runReggae("-b", "ninja", "--dflags=-g -debug");
        ninja.shouldExecuteOk;
        shouldSucceed("app");
        shouldExist(inSandboxPath("../dub_prebuild/el_prebuildo.txt"));
    }
}


@("static library")
@Tags(["dub", "ninja", "posix"])
unittest {

    with(immutable ReggaeSandbox()) {
        writeFile("dub.sdl", `
            name "foo"
            targetType "executable"
            targetName "d++"

            configuration "executable" {
            }

            configuration "library" {
                targetType "library"
                targetName "dpp"
                excludedSourceFiles "source/main.d"
            }
        `);

        writeFile("reggaefile.d",
                  q{
                      import reggae;
                      alias lib = dubConfigurationTarget!(Configuration("library"));
                      enum mainObj = objectFile(SourceFile("source/main.d"));
                      alias exe = link!(ExeName("d++"), targetConcat!(lib, mainObj));
                      mixin build!(exe);
                  });

        writeFile("source/main.d", "void main() {}");
        writeFile("source/foo/bar/mod.d", "module foo.bar.mod; int add1(int i, int j) { return i + j + 1; }");

        runReggae("-b", "ninja");
        ninja.shouldExecuteOk;
        shouldSucceed("d++");
    }
}


@("dub project with failing prebuild command")
@Tags(["dub", "ninja"])
unittest {
    with(immutable ReggaeSandbox("dub_prebuild_oops")) {

        try
            runReggae("-b", "ninja", "--dflags=-g -debug");
        catch(Exception e) {
            version(Windows) {
                "Error calling foo bar baz quux:".should.be in e.msg;
                "'foo' is not recognized as an internal or external command".should.be in e.msg;
            } else
                  e.msg.should == "Error calling foo bar baz quux:\r\n/bin/sh: foo: command not found\n";
        }

    }
}
