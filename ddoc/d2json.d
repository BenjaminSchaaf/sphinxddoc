module d2json;

import std.json;
import std.stdio;
import std.array;
import std.string;
import std.format;
import std.typecons;
import std.algorithm;

import pyd.pyd;

import dparse.ast;
import dparse.lexer;
import dparse.parser;
import dparse.rollback_allocator;

string d2json(string path) {
    auto file = File(path, "r");
    auto data = file.byChunk(4096).join;
    auto mod = parse(data, file.name);
    auto json = mod.toJson;
    return toJSON(&json, true);
}

extern (C) void PydMain() {
    def!d2json;

    module_init();
}

auto parse(ubyte[] source, string filename) {
    auto stringCache = new StringCache(4);
    auto config = LexerConfig(filename);
    auto tokens = getTokensForParser(source, config, stringCache);
    auto allocator = new RollbackAllocator;
    return parseModule(tokens, filename, allocator);
}

auto toJson(T)(T value) {
    return JSONValue(value);
}

auto toJson(Module mod) {
    auto name = mod.moduleDeclaration.moduleName.identifier_join;
    return JSONValue([
        "name": name.toJson,
        "sig": "module %s".format(name).toJson,
        "doc": mod.moduleDeclaration.comment.toJson,
        "kind": "module".toJson,
        "members": toJson(mod.declarations),
    ]);
}

auto identifier_join(IdentifierChain chain) {
    return chain.identifiers.map!(i => i.text).join(".");
}

JSONValue toJson(Declaration[] declarations) {
    JSONValue[] ret = [];
    foreach (decl; declarations) {
        Nullable!JSONValue value;
        enum get(string name) = "if (decl."~name~") value = toJson(cast("~name[0..1].toUpper~name[1..$]~")decl."~name~");";

        mixin(get!"classDeclaration");
        mixin(get!"functionDeclaration");
        mixin(get!"constructor");

        if (!value.isNull) {
            if (value.object["doc"].str.toLower == "ditto") {
                ret[$-1].object["sig"].str = ret[$-1].object["sig"].str ~ "\n" ~ value.object["sig"].str;
            } else{
                ret ~= value.get;
            }
        }
    }
    return ret.filter!(d => d.object["doc"].str != "").array.toJson;
}

auto toJson(ClassDeclaration decl) {
    return JSONValue([
        "name": decl.name.text.toJson,
        "sig": decl.getSig.toJson,
        "doc": decl.comment.toJson,
        "kind": "class".toJson,
        "members": toJson(decl.structBody.declarations),
    ]);
}

auto getSig(ClassDeclaration decl) {
    auto name = decl.name.text;
    return "class %s".format(name);
}

auto toJson(FunctionDeclaration decl) {
    return JSONValue([
        "name": decl.name.text.toJson,
        "sig": decl.getSig.toJson,
        "doc": decl.comment.toJson,
        "kind": "function".toJson,
    ]);
}

auto getSig(FunctionDeclaration decl) {
    auto name = decl.name.text;
    return " %s".format(name);
}

auto toJson(Constructor decl) {
    return JSONValue([
        "name": "this".toJson,
        "sig": decl.getSig.toJson,
        "doc": decl.comment.toJson,
        "kind": "function".toJson,
    ]);
}

auto getSig(Constructor decl) {
    return "this";
}
