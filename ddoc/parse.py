import os
import json
import subprocess
import d2json

PARSER = os.path.join(os.path.split(__file__)[0], "d2json")

def lookup_module_file(directory, name):
    names = name.split(".")

    path = os.path.join(directory, *names[:-1])
    name = names[-1]

    direct_file_path = os.path.join(path, name + ".d")
    if os.path.isfile(direct_file_path):
        return direct_file_path

    package_file_path = os.path.join(path, name, "package.d")
    if os.path.isfile(package_file_path):
        return package_file_path

def parse_file(path):
    output = d2json.d2json(path)
    return json.loads(output)
