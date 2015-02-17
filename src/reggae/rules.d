module reggae.rules;


import reggae.build;
import std.path : baseName, stripExtension, defaultExtension;
import std.algorithm: map;
import std.array: array;

version(Windows) {
    immutable objExt = ".obj";
    immutable exeExt = ".exe";
} else {
    immutable objExt = ".o";
    immutable exeExt = "";
}


private string objFileName(in string srcFileName) @safe pure nothrow {
    return srcFileName.baseName.stripExtension.defaultExtension(objExt);
}


private string exeFileName(in string srcFileName) @safe pure nothrow {
    immutable stripped = srcFileName.baseName.stripExtension;
    return exeExt == "" ? stripped : stripped.defaultExtension(exeExt);
}


Target dCompile(in string srcFileName, in string flags = "", in string[] includePaths = []) @safe pure nothrow {
    immutable includes = includePaths.map!(a => "-I$project/" ~ a).join(",");
    return Target(srcFileName.objFileName, "_dcompile " ~ includes,
                  [Target(srcFileName)]);
}


Target cppCompile(in string srcFileName, in string flags = "", in string[] includePaths = []) @safe pure nothrow {
    immutable includes = includePaths.map!(a => "-I$project/" ~ a).join(",");
    return Target(srcFileName.objFileName, "_cppcompile " ~ includes,
                  [Target(srcFileName)]);
}


Target cCompile(in string srcFileName, in string flags = "", in string[] includePaths = []) @safe pure nothrow {
    return cppCompile(srcFileName, flags, includePaths);
}


Target dExe(in string srcFileName, in string flags = "",
            in string[] includePaths = [], in string stringPaths = [],
            in Target[] linkWith = []) @safe pure nothrow {
    const dependencies = [Target(srcFileName)] ~ linkWith;
    return Target(srcFileName.exeFileName, "_dlink", dependencies);
}
