module reggae.build;

import reggae.rules.defaults;
import std.string: replace;
import std.algorithm: map;
import std.path: buildPath;
import std.typetuple: allSatisfy;
import std.traits: Unqual, isSomeFunction, ReturnType, arity;
import std.array: array, join;


Target createTargetFromTarget(in Target target) {
    return Target(target.outputs,
                  target._command.removeBuilddir,
                  target.dependencies.map!(a => a.enclose(target)).array,
                  target.implicits.map!(a => a.enclose(target)).array);
}


struct Build {
    const(Target)[] targets;

    this(in Target[] targets) {
        this.targets = targets.map!createTargetFromTarget.array;
    }

    this(T...)(in T targets) {
        foreach(t; targets) {
            static if(isSomeFunction!(typeof(t))) {
                const target = t();
            } else {
                const target = t;
            }

            this.targets ~= createTargetFromTarget(target);
        }
    }
}

//a directory for each top-level target no avoid name clashes
//@trusted because of map -> buildPath -> array
Target enclose(in Target target, in Target topLevel) @trusted {
    if(target.isLeaf) return Target(target.outputs.map!(a => a.removeBuilddir).array,
                                    target._command.removeBuilddir,
                                    target.dependencies,
                                    target.implicits);

    immutable dirName = buildPath("objs", topLevel.outputs[0] ~ ".objs");
    return Target(target.outputs.map!(a => realTargetPath(dirName, a)).array,
                  target._command.removeBuilddir,
                  target.dependencies.map!(a => a.enclose(topLevel)).array,
                  target.implicits.map!(a => a.enclose(topLevel)).array);
}

immutable gBuilddir = "$builddir";


private string realTargetPath(in string dirName, in string output) @trusted pure {
    import std.algorithm: canFind;

    return output.canFind(gBuilddir)
        ? output.removeBuilddir
        : buildPath(dirName, output);
}

private string removeBuilddir(in string output) @trusted pure {
    import std.path: buildNormalizedPath;
    import std.algorithm;
    return output.
        splitter.
        map!(a => a.canFind(gBuilddir) ? a.replace(gBuilddir, ".").buildNormalizedPath : a).
        join(" ");
}

enum isTarget(alias T) = is(Unqual!(typeof(T)) == Target) ||
    isSomeFunction!T && is(ReturnType!T == Target);

unittest {
    auto  t1 = Target();
    const t2 = Target();
    static assert(isTarget!t1);
    static assert(isTarget!t2);
}

mixin template build(T...) if(allSatisfy!(isTarget, T)) {
    Build buildFunc() {
        return Build(T);
    }
}


package template isBuildFunction(alias T) {
    static if(!isSomeFunction!T) {
        enum isBuildFunction = false;
    } else {
        enum isBuildFunction = is(ReturnType!T == Build) && arity!T == 0;
    }
}

unittest {
    Build myBuildFunction() { return Build(); }
    static assert(isBuildFunction!myBuildFunction);
    float foo;
    static assert(!isBuildFunction!foo);
}


struct Target {
    const(string)[] outputs;
    const(Target)[] dependencies;
    const(Target)[] implicits;

    this(in string output) @safe pure nothrow {
        this(output, null, null);
    }

    this(in string output, string command, in Target dependency,
         in Target[] implicits = []) @safe pure nothrow {
        this([output], command, [dependency], implicits);
    }

    this(in string output, string command,
         in Target[] dependencies, in Target[] implicits = []) @safe pure nothrow {
        this([output], command, dependencies, implicits);
    }

    this(in string[] outputs, string command,
         in Target[] dependencies, in Target[] implicits = []) @safe pure nothrow {
        this.outputs = outputs;
        this.dependencies = dependencies;
        this.implicits = implicits;
        this._command = command;
    }

    @property string dependencyFilesString(in string projectPath = "") @safe pure const nothrow {
        return depFilesStringImpl(dependencies, projectPath);
    }

    @property string implicitFilesString(in string projectPath = "") @safe pure const nothrow {
        return depFilesStringImpl(implicits, projectPath);
    }

    @property string command(in string projectPath = "") @trusted pure const nothrow {
        //functional didn't work here, I don't know why so sticking with loops for now
        string[] depOutputs;
        foreach(dep; dependencies) {
            foreach(output; dep.outputs) {
                //leaf objects are references to source files in the project path
                //those need their path built. Any other dependencies are in the
                //build path, so they don't need the same treatment
                depOutputs ~= dep.isLeaf ? buildPath(projectPath, output) : output;
            }
        }
        auto replaceIn = _command.replace("$in", depOutputs.join(" "));
        auto replaceOut = replaceIn.replace("$out", outputs.join(" "));
        return replaceOut.replace("$project", projectPath);
    }

    bool isLeaf() @safe pure const nothrow {
        return dependencies is null && implicits is null;
    }

    //@trusted because of replace
    string rawCmdString(in string projectPath) @trusted pure nothrow const {
        return _command.replace("$project", projectPath);
    }


    string shellCommand(in string projectPath = "") @safe pure const {
        immutable rawCmdLine = rawCmdString(projectPath);
        if(rawCmdLine.isDefaultCommand) {
            return defaultCommand(projectPath, rawCmdLine);
        } else {
            return command(projectPath);
        }
    }

    string[] outputsInProjectPath(in string projectPath) @safe pure nothrow const {
        return outputs.map!(a => isLeaf ? buildPath(projectPath, a) : a).array;
    }

private:

    string _command;

    //@trusted because of join
    string depFilesStringImpl(in Target[] deps, in string projectPath) @trusted pure const nothrow {
        import std.conv;
        string files;
        //join doesn't do const, resort to loops
        foreach(i, dep; deps) {
            files ~= text(dep.outputsInProjectPath(projectPath).join(" "));
            if(i != deps.length - 1) files ~= " ";
        }
        return files;
    }

    //this function returns a string to be run by the shell with `std.process.execute`
    //it does 'normal' commands, not built-in rules
    string defaultCommand(in string projectPath, in string rawCmdLine) @safe pure const {
        import reggae.config: dCompiler, cppCompiler, cCompiler;

        immutable flags = rawCmdLine.getDefaultRuleParams("flags", []).join(" ");
        immutable includes = rawCmdLine.getDefaultRuleParams("includes", []).join(" ");
        immutable depfile = outputs[0] ~ ".dep";

        string ccCommand(in string compiler) {
            import std.stdio;
            debug writeln("ccCommand with compiler ", compiler);
            return [compiler, flags, includes, "-MMD", "-MT", outputs[0],
                    "-MF", depfile, "-o", outputs[0], "-c",
                    dependencyFilesString(projectPath)].join(" ");
        }


        immutable rule = rawCmdLine.getDefaultRule;
        import std.stdio;
        debug writeln("rule: ", rule);

        switch(rule) {

        case "_dcompile":
            immutable stringImports = rawCmdLine.getDefaultRuleParams("stringImports", []).join(" ");
            immutable command = [".reggae/dcompile",
                                 "--objFile=" ~ outputs[0],
                                 "--depFile=" ~ depfile, dCompiler,
                                 flags, includes, stringImports,
                                 dependencyFilesString(projectPath),
                ].join(" ");

            return command;

        case "_cppcompile": return ccCommand(cppCompiler);
        case "_ccompile":   return ccCommand(cCompiler);
        case "_dlink":
            return [dCompiler, "-of" ~ outputs[0],
                    flags,
                    dependencyFilesString(projectPath)].join(" ");
        default:
            assert(0, "Unknown default rule " ~ rule);
        }
    }
}