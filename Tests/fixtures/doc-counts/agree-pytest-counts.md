x

| `python3 -m pytest Tests/` | The agent, in 3 files: `test_alpha.py` (5) -- a; `test_beta.py` (7, plus subtests) -- b; `test_gamma.py` -- no count |
| `pytest Tests/test_beta.py` | 7 | b |
| `pytest Tests/test_gamma.py` | 9 (+ subtests) | g |
| `pytest Tests/test_alpha.py` | -- | no count |
| `pytest Tests/test_other.py` | in the pytest row | no count |
