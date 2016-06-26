import os

from distutils.command.build_py import build_py
from distutils.core import setup
from distutils.command.install import INSTALL_SCHEMES

for scheme in INSTALL_SCHEMES.values():
    scheme['data'] = scheme['purelib']

class build_d_and_py(build_py):
    def run(self):
        build_py.run(self)
        print("running dub")
        os.system("dub build")

setup(name='ddoc',
      version='0.1',
      description='Python Distribution Utilities',
      author='Benjamin Schaaf',
      packages=['ddoc'],
      cmdclass={'build_py': build_d_and_py},
      data_files=[('ddoc', ['d2json'])],
      package_data={'': ['d2json']}, # Wish this worked, but distutils is retarded
     )
