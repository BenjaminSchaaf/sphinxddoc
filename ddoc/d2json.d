module d2json;

import std.json;
import std.stdio;
import std.array;
import std.string;
import std.format;
import std.typecons;
import std.algorithm;
import std.container;

import pyd.pyd;

import dparse.ast;
import dparse.lexer;
import dparse.parser;
import formatter = dparse.formatter;
import dparse.formatter : IndentStyle;
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

static SList!Attribute attributes;

auto parse(ubyte[] source, string filename) {
    auto config = LexerConfig(filename);
    auto stringCache = StringCache(StringCache.defaultBucketCount);
    auto tokens = getTokensForParser(source, config, &stringCache);
    RollbackAllocator allocator;
    auto mod = parseModule(tokens, filename, &allocator);
    return mod.toJson;
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
    assert(chain.identifiers);
    return chain.identifiers.map!(i => i.text).join(".");
}

JSONValue toJson(Declaration[] declarations) {
    JSONValue[] ret = [];
    foreach (decl; declarations) {
        // expand attribute declarations
        if (decl.declarations) {
            attributes.insert(decl.attributes);
            ret ~= toJson(decl.declarations).array;
            attributes.removeFront(decl.attributes.length);
            continue;
        }

        Nullable!JSONValue value;
        enum get(string name) = "if (decl."~name~") value = toJson(cast("~name[0..1].toUpper~name[1..$]~")decl."~name~");";
        mixin(get!"importDeclaration");
        mixin(get!"classDeclaration");
        mixin(get!"structDeclaration");
        mixin(get!"functionDeclaration");
        mixin(get!"constructor");
        mixin(get!"variableDeclaration");
        mixin(get!"aliasDeclaration");
        mixin(get!"templateDeclaration");

        if (!value.isNull) {
            // Set attributes
            if ("attributes" !in value.object) {
                value.object["attributes"] = attributes.array.map!getSig.array.toJson;
            }

            if ("doc" in value.object && value.object["doc"].str.toLower == "ditto") {
                ret[$-1].object["sig"].str = ret[$-1].object["sig"].str ~ "\n" ~ value.object["sig"].str;
            } else {
                ret ~= value.get;
            }
        }
    }
    return ret.filter!(d => "doc" !in d.object || d.object["doc"].str !is null)
              .array
              .toJson;
}

auto toJson(Attribute attr) {
    if (attr.attribute == tok!"") {
        return "!!";
    } else if (attr.identifierChain) {
        return attr.identifierChain.identifier_join;
    } else {
        return str(attr.attribute.type);
    }
}

auto toJson(StorageClass attr) {
    if (attr.token == tok!"") {
        return "!!";
    } else {
        return str(attr.token.type);
    }
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

auto toJson(StructDeclaration decl) {
    return JSONValue([
        "name": decl.name.text.toJson,
        "sig": decl.getSig.toJson,
        "doc": decl.comment.toJson,
        "kind": "struct".toJson,
        "members": toJson(decl.structBody.declarations),
    ]);
}

auto toJson(FunctionDeclaration decl) {
    return JSONValue([
        "name": decl.name.text.toJson,
        "sig": decl.getSig.toJson,
        "attributes": (attributes.array ~ decl.attributes).map!getSig.array.toJson,
        "doc": decl.comment.toJson,
        "kind": "function".toJson,
    ]);
}

auto toJson(Constructor decl) {
    return JSONValue([
        "name": "this".toJson,
        "sig": decl.getSig.toJson,
        "doc": decl.comment.toJson,
        "kind": "function".toJson,
    ]);
}

auto toJson(ImportDeclaration decl) {
    return JSONValue([
        "imported": decl.getImported,
        "kind": "import".toJson,
    ]);
}

auto getImported(SingleImport imp) {
    return JSONValue([
        "rename": imp.rename.text,
        "name": imp.identifierChain.identifier_join,
    ]);
}

auto getImported(ImportDeclaration decl) {
    return decl.singleImports.map!getImported.array.toJson;
}

auto toJson(VariableDeclaration decl) {
    if (decl.autoDeclaration) {
        return decl.autoDeclaration.toJson;
    }
    return JSONValue([
        "name": decl.declarators[0].name.text.toJson,
        "sig": decl.getSig.toJson,
        "doc": decl.comment.toJson,
        "kind": "variable".toJson,
    ]);
}

auto toJson(AutoDeclaration decl) {
    return JSONValue([
        "name": decl.identifiers[0].text.toJson,
        "sig": decl.getSig.toJson,
        "doc": decl.comment.toJson,
        "kind": "variable".toJson,
    ]);
}

auto toJson(AliasDeclaration decl) {
    return JSONValue([
        "name": decl.initializers[0].name.text.toJson,
        "sig": decl.getSig.toJson,
        "doc": decl.comment.toJson,
        "kind": "alias".toJson,
    ]);
}

auto toJson(TemplateDeclaration decl) {
    return JSONValue([
        "name": decl.name.text.toJson,
        "sig": decl.getSig.toJson,
        "doc": decl.comment.toJson,
        "kind": "template".toJson,
    ]);
}

string getSig(T)(T node) {
    string output;
    void toOutput(in string s) { output ~= s; }
    dformat(&toOutput, node);
    return output.strip;
}

void dformat(Sink, T)(Sink sink, T node) {
    Formatter!Sink formatter = new Formatter!Sink(sink, false, IndentStyle.otbs, 4);
    formatter.format(node);
}

/**
 * Slightly modified code from dparse.formatter to only format signatures of things.
 */
class Formatter(Sink) : formatter.Formatter!Sink {
    this(Sink sink, bool useTabs = false, IndentStyle style = IndentStyle.allman, uint indentWidth = 4) {
        super(sink, useTabs, style, indentWidth);
    }

    alias format = formatter.Formatter!Sink.format;

    override void format(const FunctionDeclaration decl, const Attribute[] attrs = attributes.array) {
        newThing(What.functionDecl);
        putAttrs(attrs);

        foreach (sc; decl.storageClasses) {
            format(sc);
            space();
        }

        if (decl.returnType) format(decl.returnType);

        space();
        format(decl.name);

        if (decl.templateParameters) format(decl.templateParameters);
        if (decl.parameters) format(decl.parameters);

        foreach (attr; decl.memberFunctionAttributes) {
            space();
            format(attr);
        }
        if (decl.constraint) {
            space();
            format(decl.constraint);
        }
    }

    override void format(const Constructor constructor, const Attribute[] attrs = attributes.array) {
        newThing(What.functionDecl);
        putAttrs(attrs);

        put("this");

        if (constructor.templateParameters) format(constructor.templateParameters);

        if (constructor.parameters) format(constructor.parameters);

        foreach (att; constructor.memberFunctionAttributes) {
            space();
            format(att);
        }

        if (constructor.constraint) {
            space();
            format(constructor.constraint);
        }
    }

    override void format(const TemplateDeclaration templateDeclaration, const Attribute[] attrs = attributes.array) {
        with(templateDeclaration) {
            newThing(What.other);
            putAttrs(attrs);

            put("template ");
            format(name);

            if (templateParameters) format(templateParameters);

            if (constraint) {
                space();
                format(constraint);
            }
        }
    }

    override void format(const AliasDeclaration aliasDeclaration, const Attribute[] attrs = attributes.array) {
        with(aliasDeclaration) {
            newThing(What.other);
            putAttrs(attrs);
            put("alias ");

            if (initializers.length) {
                foreach (count, init; initializers) {
                    if (count) put(", ");
                    format(init);
                }
            } else {
                foreach (storageClass; storageClasses) {
                    format(storageClass);
                    space();
                }

                if (type) {
                    format(type);
                    space();
                }
                format(identifierList);
            }
        }
    }

    override void format(const VariableDeclaration decl, const Attribute[] attrs = attributes.array) {
        newThing(What.variableDecl);
        putAttrs(attrs);

        if (decl.autoDeclaration) format(decl.autoDeclaration);
        else {
            foreach (c; decl.storageClasses) {
                format(c);
                space();
            }
            if (decl.type) format(decl.type);
            if (decl.declarators.length) space();
            foreach(count, d; decl.declarators) {
                if (count) put(", ");
                format(d);
            }
        }
    }

    override void format(const Constraint constraint) {
        if (constraint.expression) {
            put("if (");
            format(constraint.expression);
            put(")");
        }
    }

    override void format(const StructBody structBody) {}
    override void putComment(string c) {}
}
