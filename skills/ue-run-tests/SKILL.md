---
name: ue-run-tests
description: Run Unreal Engine automation tests of a C++ project headless (build the editor target, Automation RunTests, parse the report) and report passed/failed tests with the failure messages; optionally code coverage (OpenCppCoverage), a JUnit xml for CI, listing tests, and creating new spec/legacy test files from the devops_ue templates. Use when asked to run, list, write or add tests, check coverage, or why a test fails.
---

# Run automation tests

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/run_tests.ps1" -ProjectPath "<project>" [-Filter "<Game.Area>"] [-Coverage] [-JUnit] [-SkipBuild] [-WithRHI]
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/run_tests.ps1" -ProjectPath "<project>" -List [-Filter ...]
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/run_tests.ps1" -ProjectPath "<project>" -NewSpec <Name> [-Dir Tests\Area]
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/run_tests.ps1" -ProjectPath "<project>" -NewTest <Name> [-Dir Tests]
```

Talk to the user in their language. Needs a C++ module (`Source\<Name>`); the engine comes from
`devops_data\config.bat`, else the `.uproject` association (`ue-create-project` skill next to this one).

## Run

* `-Filter`: what `Automation RunTests` gets - tests whose full path starts with / contains it. Default:
  `TestNames` from `config.bat`, else the project name. Ask if the user means a subset.
* The script builds `<Name>Editor Win64 Development` (skip with `-SkipBuild`), runs `UnrealEditor-Cmd` with
  `-nullrhi` (`-WithRHI` for rendering/screenshot tests), timeout `-TimeoutMinutes` (60).
  Builds take minutes: run in the background.
* Results: `Build\Tests\index.json` (+ `Tests.log`); the script prints totals and every failed test with its
  error messages and file:line. Exit code 1 when a test failed or nothing matched.
* `-Coverage`: OpenCppCoverage (path from `config.bat` `OpenCPPCoveragePath`, default Program Files), sources
  `Source\`, excluded paths from `ExcludedPathForTestReport` -> `Build\Tests\Coverage\CodeCoverageReport\index.html`
  and cobertura xml (line rate printed). Missing tool -> offer `ue-install-env -Tools opencppcoverage`.
* `-JUnit`: `Build\Tests\junit.xml` via `devops_ue\tests\ue_report_to_junit.py` (Jenkins/GitHub CI).

## Failures

For each failed test: open the test source (file:line from the report) and the code under test, explain the cause,
propose a fix; re-run only that test with `-Filter <its full path> -SkipBuild` when no C++ changed, without
`-SkipBuild` after a code change. Don't weaken a test to make it pass without saying so.

## New tests

`-NewSpec <Name>` -> `Source\<Project>\<Dir>\<Name>.spec.cpp`; `-NewTest <Name>` -> `<Name>.h/.cpp` (legacy
`IMPLEMENT_SIMPLE_AUTOMATION_TEST`). Templates: `devops_ue\tests\templates`, copyright from `config.bat` /
`DefaultGame.ini`, clang-format applied. Then **write the real test**: replace the placeholder category with
`<Project>.<Area>.<Name>` (so the default filter finds it) and the empty `It(...)`/`RunTest` body with checks
(`TestEqual`, `TestTrue`, `TestNotNull`...). Helpers: `devops_ue\tests\Utils` (see its README for the Build.cs modules).

## Report

Totals, failed tests with causes, coverage %, report paths, warnings, the `Time:` block.
