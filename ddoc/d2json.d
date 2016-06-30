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

static SList!string attributes;

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
            attributes.insert(decl.attributes.map!toJson);
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

        if (!value.isNull) {
            // Set attributes
            if ("attributes" !in value.object) {
                value.object["attributes"] = attributes.array.toJson;
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

auto getSig(ClassDeclaration decl) {
    auto name = decl.name.text;
    auto ret = "class %s".format(name);
    if (decl.templateParameters) ret ~= decl.templateParameters.getSig;
    return ret;
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

auto getSig(StructDeclaration decl) {
    auto name = decl.name.text;
    auto ret = "struct %s".format(name);
    if (decl.templateParameters) ret ~= decl.templateParameters.getSig;
    return ret;
}

auto toJson(FunctionDeclaration decl) {
    return JSONValue([
        "name": decl.name.text.toJson,
        "sig": decl.getSig.toJson,
        "attributes": (attributes.array ~ decl.attributes.map!toJson.array).toJson,
        "doc": decl.comment.toJson,
        "kind": "function".toJson,
    ]);
}

auto getSig(FunctionDeclaration decl) {
    string ret = "";
    if (decl.returnType) {
        ret ~= "%s ".format(decl.returnType.getSig);
    } else {
        ret ~= "auto ";
    }
    if (decl.hasAuto) ret ~= "auto ";
    if (decl.hasRef) ret ~= "ref ";
    ret ~= "%s%s".format(decl.name.text, decl.parameters.getSig);
    return ret;
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

auto getSig(VariableDeclaration decl) {
    return "%s %s".format(decl.type.getSig, decl.declarators.map!getSig.join(", "));
}

auto getSig(Declarator decl) {
    return decl.name.text;
}

auto toJson(AutoDeclaration decl) {
    return JSONValue([
        "name": decl.identifiers[0].text.toJson,
        "sig": decl.getSig.toJson,
        "doc": decl.comment.toJson,
        "kind": "variable".toJson,
    ]);
}

auto getSig(AutoDeclaration decl) {
    return "auto %s".format(decl.identifiers.map!(i => i.text).join(", "));
}

string getSig(Type type) {
    auto suffix = type.typeSuffixes.map!getSig.join("");
    return "%s%s".format(type.type2.getSig, suffix);
}

auto getSig(TypeSuffix suffix) {
    if (suffix.star != tok!"") {
        return suffix.star.text;
    } if (suffix.array) {
        if (suffix.type) {
            return "[%s]".format(suffix.type.getSig);
        }
        return "[]";
    } if (suffix.parameters) {
        return " %s%s".format(str(suffix.delegateOrFunction.type),
                              suffix.parameters.getSig);
    }
    return "?1";
}

string getSig(Type2 type) {
    if (type.builtinType != 0) {
        return str(type.builtinType);
    } if (type.identifierOrTemplateChain) {
        return type.identifierOrTemplateChain.getSig;
    } if (type.symbol) {
        return type.symbol.identifierOrTemplateChain.getSig;
    }
    return "?2";
}

string getSig(IdentifierOrTemplateChain chain) {
    return chain.identifiersOrTemplateInstances
                .map!getSig.array.join("");
}

string getSig(IdentifierOrTemplateInstance iort) {
    if (iort.templateInstance) {
        return iort.templateInstance.getSig;
    }
    return iort.identifier.text;
}

string getSig(TemplateInstance inst) {
    return "%s!%s".format(inst.identifier.text, inst.templateArguments.getSig);
}

string getSig(TemplateArguments args) {
    if (args.templateArgumentList) {
        return args.templateArgumentList.getSig;
    }
    return args.templateSingleArgument.token.text;
}

string getSig(TemplateArgumentList list) {
    return "(%s)".format(list.items.map!getSig.join(", "));
}

string getSig(TemplateArgument arg) {
    if (arg.type) {
        return arg.type.getSig;
    }
    return "?4";
}

string getSig(Parameters params) {
    return "(%s)".format(params.parameters.map!getSig.join(", "));
}

string getSig(Parameter param) {
    if (param.name.type == tok!"") {
        return param.type.getSig;
    }
    return "%s %s".format(param.type.getSig, param.name.text);
}

string getSig(TemplateParameters params) {
    return "(%s)".format(params.templateParameterList.items.map!getSig.join(", "));
}

string getSig(TemplateParameter param) {
    if (param.templateTypeParameter) {
        return param.templateTypeParameter.getSig;
    } if (param.templateValueParameter) {
        return param.templateValueParameter.getSig;
    }
    return "?5";
}

string getSig(TemplateTypeParameter param) {
    return param.identifier.text;
}

string getSig(TemplateValueParameter param) {
    return "%s %s".format(param.type.getSig, param.identifier.text);
}

string getSig(AssignExpression assign) {
    string output;
    void myprint(in string s) { output ~= s; }
    formatter.format(&myprint, assign);
    return output;
}
