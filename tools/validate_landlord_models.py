"""Compatibility entrypoint for independent shared poker asset validation."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).with_name("validate_poker_models.py")), run_name="__main__")
