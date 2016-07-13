from six import itervalues
from sphinx.util.compat import Directive
from sphinx.util.docstrings import prepare_docstring
from sphinx.ext import autodoc

from ddoc.d import DModule
from ddoc import parse

class Documenter(autodoc.Documenter):
    def __init__(self, directive, name, indent=u'', object=None, objpath=None):
        super().__init__(directive, name, indent)
        self.object = object
        self.objpath = objpath

    def get_real_modname(self):
        return self.object["name"]

    def parse_name(self):
        if self.objpath is not None: return True

        lookup_path = self.env.config.autodoc_lookup_path
        self.objpath = parse.lookup_module_file(lookup_path, self.name)

        if self.objpath is None:
            self.directive.warn("Couldn't find module (%s)" % self.name)
            return False

        self.fullname = self.name
        self.modname = self.name

        return True

    def import_object(self):
        if self.object is not None: return True

        self.object = parse.parse_file(self.objpath)
        self.directive.filename_set.add(self.objpath)

        return True

    def format_name(self):
        return self.name

    def format_signature(self):
        return self.object["sig"]

    def get_doc(self, encoding=None, ignore=1):
        return [prepare_docstring(self.object['doc'], ignore)]

    def get_object_members(self, want_all):
        if "members" not in self.object:
            return []

        members = [obj for obj in self.object["members"] if "name" in obj]
        return [(obj["name"], obj) for obj in members]

    def add_directive_header(self, sig):
        domain = getattr(self, 'domain', 'd')
        directive = getattr(self, 'directivetype', self.objtype)
        sourcename = self.get_sourcename()
        self.add_line(u'.. %s:%s:: %s' % (domain, directive, sig),
                      sourcename)
        #self.add_line(u'   %s' % sig, sourcename)
        self.add_line(u'   :name: %s' % self.name, sourcename)
        #if self.options.noindex:
        #    self.add_line(u'   :noindex:', sourcename)
        #if self.objpath:
        #    # Be explicit about the module, this is necessary since .. class::
        #    # etc. don't support a prepended module name
        #    self.add_line(u'   :module: %s' % self.modname, sourcename)

    def document_imports(self):
        if 'members' not in self.object:
            return

        imports = self.object["members"]
        imports = [imp for imp in imports if imp["kind"] == 'import' and 'public' in imp['attributes']]

        if len(imports) == 0:
            return

        sourcename = self.get_sourcename()
        self.add_line(u'Public Imports:', sourcename)
        self.add_line(u'', sourcename)
        for imp in imports:
            for name in imp['imported']:
                if name['rename']:
                    self.add_line(u'  | %s = :d:mod:`%s`' % (name['rename'], name['name']), sourcename)
                else:
                    self.add_line(u'  | :d:mod:`%s`' % (name['name']), sourcename)

    def document_examples(self):
        if 'examples' not in self.object:
            return

        examples = self.object['examples']
        if len(examples) == 0:
            return

        sourcename = self.get_sourcename()
        self.add_line(u'Examples:', sourcename)
        for example in examples:
            if example['doc']:
                self.add_line(u'    %s' % example['doc'], sourcename)
                self.add_line(u'', sourcename)
            self.add_line(u'    .. code-block:: d', sourcename)
            self.add_line(u'', sourcename)

            test_file = open(self.objpath, 'r')
            test_file.seek(example['startLocation'])
            test = test_file.read(example['endLocation'] - example['startLocation'])
            for line in test.split('\n'):
                self.add_line(u'        %s' % line, sourcename)

    def document_members(self, all_members=False):
        """Generate reST for member documentation.

        If *all_members* is True, do all members, else those given by
        *self.options.members*.
        """
        self.document_imports()
        self.document_examples()

        want_all = all_members or self.options.inherited_members or \
            self.options.members is autodoc.ALL
        members = self.get_object_members(want_all)

        # remove members given by exclude-members
        if self.options.exclude_members:
            members = [(membername, member) for (membername, member) in members
                       if membername not in self.options.exclude_members]

        # document non-skipped members
        memberdocumenters = []
        for (mname, member) in members:
            klass = autodoc.AutoDirective._registry.get(member["kind"], None)
            if not klass:
                # don't know how to document this member
                continue

            full_mname = "%s.%s" % (self.name, mname)
            documenter = klass(self.directive, full_mname, self.indent,
                               object=member, objpath=self.objpath)
            memberdocumenters.append(documenter)

        for documenter in memberdocumenters:
            documenter.generate(
                all_members=True, real_modname=self.real_modname,
                check_module=False)

class ModuleDocumenter(Documenter):
    objtype = 'module'

class FunctionDocumenter(Documenter):
    objtype = 'function'

class ClassDocumenter(Documenter):
    objtype = 'class'

class StructDocumenter(Documenter):
    objtype = 'struct'

class VariableDocumenter(Documenter):
    objtype = 'variable'

class EnumDocumenter(Documenter):
    objtype = 'enum'

class AliasDocumenter(Documenter):
    objtype = 'alias'

class TemplateDocumenter(Documenter):
    objtype = 'template'

def setup(app):
    documenters = [
        ModuleDocumenter,
        FunctionDocumenter,
        ClassDocumenter,
        StructDocumenter,
        VariableDocumenter,
        EnumDocumenter,
        AliasDocumenter,
        TemplateDocumenter,
    ]
    for documenter in documenters:
        app.add_autodocumenter(documenter)

    app.add_config_value('autoclass_content', 'class', True)
    app.add_config_value('autodoc_member_order', 'alphabetic', True)
    app.add_config_value('autodoc_default_flags', [], True)
    app.add_config_value('autodoc_docstring_signature', True, True)
    app.add_config_value('autodoc_mock_imports', [], True)
    app.add_config_value('autodoc_lookup_path', 'source', True)
    app.add_event('autodoc-process-docstring')
    app.add_event('autodoc-process-signature')
    app.add_event('autodoc-skip-member')

    return {'version': '0.1'}
