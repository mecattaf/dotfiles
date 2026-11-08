"""Load the real standalone helper without running its CLI."""
import importlib.machinery
import os
from pathlib import Path
import sys
import types

source = os.environ.get('RECORDING_STAGE_SCRIPT',
                        str(Path(__file__).parents[2] / 'home/dot_local/bin/recording-transcript-stage'))
module = types.ModuleType(__name__)
importlib.machinery.SourceFileLoader(__name__, source).exec_module(module)
sys.modules[__name__] = module
