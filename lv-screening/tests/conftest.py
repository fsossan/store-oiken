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
    from scengen.grid import load_grid
    from scengen.injections import prepare
    from scengen.output import write
    from scengen.scenario import new_scenario, write_scenario
    for d in (SCENARIOS_DIR / NAME, OUTPUT_DIR / NAME):
        shutil.rmtree(d, ignore_errors=True)
    scenario = new_scenario(load_config(), "sc1_2030", NAME)
    scenario["time"] = {"step_min": 15, "days": 2, "yearly": {"enabled": False}}
    write_scenario(scenario)
    folder = write(prepare(load_grid(), scenario), ["LV_Grid_101", "LV_Grid_412", "LV_Grid_230"], verbose=False)
    yield folder
    for d in (SCENARIOS_DIR / NAME, OUTPUT_DIR / NAME):
        shutil.rmtree(d, ignore_errors=True)
