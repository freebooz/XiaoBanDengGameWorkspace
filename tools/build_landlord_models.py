"""Compatibility entrypoint; every poker game uses the canonical model source."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).with_name("build_poker_models.py")), run_name="__main__")
