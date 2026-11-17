---
name: ue-add-test
description: Write automation tests for a specific class, function or behavior of an Unreal C++ project - picks spec vs legacy test, creates the file from the devops_ue templates, writes the real Describe/It checks with the right category, adds missing Build.cs modules, then builds and runs only the new test until it passes. Use when asked to add, write, cover or generate a test for some code (not just to run existing tests - that is ue-run-tests).
---

# Add a test for some code

Talk to the user in their language. Scaffolding and running are done by the `ue-run-tests` skill next to this one
(`../ue-run-tests/scripts/run_tests.ps1`); this skill is the **writing** workflow: the template alone is an empty shell.

## 1. Understand what to test

Ask only if unclear: which class/function/behavior, and what counts as correct. Read the code under test and its
header; list the observable behaviors (return values, state changes, delegates broadcast, clamping/edge cases, failure
paths). Prefer a few sharp tests over many shallow ones. Check `Source\<Project>\Tests` for existing tests and
mirror their style, naming and helpers.

## 2. Pick the kind

* **Spec** (`-NewSpec`, `Describe`/`It`, default choice): grouped behaviors of a class, shared setup in `BeforeEach`.
* **Legacy** (`-NewTest`, `IMPLEMENT_SIMPLE_AUTOMATION_TEST`, `.h/.cpp`): one self-contained check, math/utility functions.
* Needs a world, actors or input -> use `EAutomationTestFlags::EditorContext` plus the helpers in
  `devops_ue\tests\Utils` (`TestUtils.h` - create/destroy a test world, spawn actors, `JsonUtils`, `InputRecordingUtils`);
  copy the ones you need into `Source\<Project>\Tests\Utils` and fix their include paths.
* Pure logic (no UObjects) -> plain objects, no world, fastest.

## 3. Create the file

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<run-tests skill dir>/scripts/run_tests.ps1" -ProjectPath "<project>" -NewSpec <ClassName>Tests -Dir Tests\<Area>
powershell -NoProfile -ExecutionPolicy Bypass -File "<run-tests skill dir>/scripts/run_tests.ps1" -ProjectPath "<project>" -NewTest <Name> -Dir Tests
```

Creates `Source\<Project>\<Dir>\<Name>.spec.cpp` (or `.h/.cpp`) with the project's copyright, formatted by clang-format.
It refuses to overwrite an existing file. The project needs a `Source\<Project>` module (not Blueprint-only).

## 4. Write the real test

* Category: replace `"Category"` with `<Project>.<Area>.<Class>` - the default filter is the project name, so a wrong
  category means the test is never run.
* Replace the empty `Describe`/`It` (or `RunTest`) with checks: `TestEqual`, `TestTrue/False`, `TestNotNull`,
  `TestNearlyEqual` for floats, `AddExpectedError` for errors the code logs on purpose. One behavior per `It`, named as a
  sentence ("clamps health to the max").
* Include the header of the class under test with its path from the module root. Tests only compile in
  non-Shipping builds: keep the `#if WITH_AUTOMATION_TESTS` guard.
* Missing modules: tests that use JSON/UMG/functional helpers need `"Json", "JsonUtilities", "UMG"` and, for
  `FunctionalTesting`, a non-Shipping `PublicDependencyModuleNames.Add("FunctionalTesting")` in `<Project>.Build.cs`
  (see `devops_ue\tests\README.md`). Add them only when the test actually needs them.
* Don't change production code just to make it testable without telling the user what and why.

## 5. Run only this test until green

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<run-tests skill dir>/scripts/run_tests.ps1" -ProjectPath "<project>" -Filter "<Project>.<Area>.<Class>"
```

The first run builds the editor target (minutes - run in the background). Fix compile errors, then failures:
a failing new test means either the test or the code is wrong - say which, with the evidence, and **never loosen the
assertion just to pass**. Use `-SkipBuild` only when no C++ changed. Finally run the whole suite (default `-Filter`) to
be sure nothing else broke, and optionally `-Coverage` to show what the new test covers.

## Report

Created file(s), the test category/path, what each `It` verifies, run result (passed/failed counts), Build.cs changes,
and behaviors deliberately left untested.
