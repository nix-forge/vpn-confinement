"""Fuzz nftables JSON normalization used by read-only policy diagnostics."""

import copy
import importlib.util
import json
import sys
from pathlib import Path

import atheris

SCRIPT = Path(__file__).resolve().parents[1] / "modules/vpn-confinement/doctor.py"
with atheris.instrument_imports():
    spec = importlib.util.spec_from_file_location("vpn_doctor", SCRIPT)
    assert spec is not None and spec.loader is not None
    doctor = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(doctor)
    atheris.instrument_func(doctor.normalized_policy)


@atheris.instrument_func
def test_one_input(data: bytes) -> None:
    if len(data) > 16384:
        return
    try:
        raw = json.loads(data)
    except (ValueError, UnicodeError, RecursionError):
        pass
    else:
        original = copy.deepcopy(raw)
        normalized = doctor.normalized_policy(raw)
        assert raw == original
        assert normalized == doctor.normalized_policy(json.loads(json.dumps(raw)))

    provider = atheris.FuzzedDataProvider(data)
    chain = provider.ConsumeUnicodeNoSurrogates(24)
    elements = [provider.ConsumeIntInRange(0, 65535) for _ in range(8)]
    rule = {
        "rule": {
            "chain": chain,
            "expr": [{"accept": None}],
            "handle": provider.ConsumeIntInRange(0, 65535),
        }
    }
    table = {"nftables": [{"set": {"elem": elements}}, rule]}
    original = copy.deepcopy(table)
    normalized = doctor.normalized_policy(table)
    assert table == original
    assert normalized is not None
    table["nftables"][0]["set"]["elem"].reverse()
    table["nftables"][1]["rule"]["handle"] += 1
    assert doctor.normalized_policy(table) == normalized


if __name__ == "__main__":
    atheris.Setup(sys.argv, test_one_input)
    atheris.Fuzz()
