import os
import pathlib

from distutils.core import setup
from pyd.support import setup, Extension

dmodules = ['ddoc/d2json.d']
for folder in ['std', 'dparse']:
    path = pathlib.Path(os.path.join('ddoc', folder))
    dmodules += map(str, path.rglob('*.d'))

setup(name='ddoc',
      version='0.1',
      description='Python Distribution Utilities',
      author='Benjamin Schaaf',
      packages=['ddoc'],
      ext_modules=[
          Extension(
              'd2json', dmodules,
              extra_compile_args=['-w', '-Iddoc', '-debug'],
              build_deimos=True,
              d_lump=True,
          ),
      ]
     )
