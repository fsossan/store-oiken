"""A small generated scenario for the screening tests, made with the sibling
injection-scenarios tool (3 networks, 2 days), removed afterwards."""
import shutil
import sys
import warnings
from pathlib import Path

import pytest

GEN = Path(__file__).resolve().parents[2] / "injection-scenarios"
sys.path.insert(0, str(GEN))
warnings.filterwarnings("ignore")
NAME = "_test_screening"


@pytest.fixture(scope="session")
def test_scenario_folder():
    from scengen.config import OUTPUT_DIR, SCENARIOS_DIR, load_config
    from scengen.generate import generate, new_scenario_config, write_scenario_config
    for d in (SCENARIOS_DIR / NAME, OUTPUT_DIR / NAME):
        shutil.rmtree(d, ignore_errors=True)
    scfg = new_scenario_config(load_config(), "sc1_2030", NAME)
    scfg["time"] = {"step_min": 15, "days": 2, "yearly": {"enabled": False}}
    write_scenario_config(scfg)
    folder = generate(NAME, ["LV_Grid_101", "LV_Grid_412", "LV_Grid_230"], verbose=False)
    yield folder
    for d in (SCENARIOS_DIR / NAME, OUTPUT_DIR / NAME):
        shutil.rmtree(d, ignore_errors=True)
