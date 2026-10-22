```powershell
tkTestToolkit            # 3 suites, 60 assertions
```

```bash
python3 -m pytest Tests/     # 12 passed, 1 skipped, 40 subtests -- the agent
cd web && npm test           # 5 build-contract checks, then 7 suites, 55 tests -- the shell
```

**The counts, after a merge.** A full run ends with:

```text
  Counts for docs/TESTING.md's paste block, from this run:
  Consts 10, Compat 20, Menu 30
  3 suites, 60 assertions
  pytest: 12 passed, 1 skipped, 40 subtests
  web: 7 suites, 55 tests
```

| Runner | What |
| --- | --- |
| `tkTestToolkit` | The CLI, per suite: Consts 10, Compat 20, Menu 30. This row is the one place. |
