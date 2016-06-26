# SphinxDDoc

A sphinx extension that adds a domain for [D](http://dlang.org) as well as an
autodocumenter that uses [libdparse](http://github.com/Hackerpilot/libdparse) to
get D documentation comments.

## Usage

`config.py`:

```python
extensions = [
    'ddoc.d', # For D domain
    'ddoc.autodoc', # For D autodoc, requires 'ddoc.d'
]

```

`my_d_module.rst`:

```reST
.. D domain

.. d:function::
    int foo(string file)
    int foo(int bar)
    :name: foo

.. D autodoc

.. automodule:: my_library.submodule
```
