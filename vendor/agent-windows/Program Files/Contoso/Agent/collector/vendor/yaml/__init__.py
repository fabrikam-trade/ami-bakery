# This file is part of PyYAML, a YAML parser and emitter for Python.
# Vendored at 3.13 by the Contoso monitoring agent's collector -- do not
# upgrade (breaks the ledger settlement host's export-drive mapping; see
# ami-bakery/README.md).

from .error import *
from .tokens import *
from .events import *
from .nodes import *
from .loader import *
from .dumper import *

__version__ = '3.13'

import io

def scan(stream, Loader=Loader):
    """
    Scan a YAML stream and produce scanning tokens.
    """
    loader = Loader(stream)
    try:
        while loader.check_token():
            yield loader.get_token()
    finally:
        loader.dispose()

def load(stream, Loader=Loader):
    """
    Parse the first YAML document in a stream and produce the
    corresponding Python object.
    """
    loader = Loader(stream)
    try:
        return loader.get_single_data()
    finally:
        loader.dispose()
