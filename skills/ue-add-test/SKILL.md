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

## 2a. Where the tests live: offer a separate test module

Before the first test of a project / plugin, **ask the user** (once, with a recommendation) where to put the tests:

* **Separate test module** (recommended for plugins and bigger projects): an Editor-only module that depends on the module
  under test, e.g. `OpenAITestRunner` next to `OpenAI` and `OpenAIEditor` in the plugin
  <https://github.com/life-exe/UnrealOpenAIPlugin/tree/master/Source>. Production code stays free of test code and
  `FunctionalTesting`, the tests are never packaged, and the plugin can ship without them. Cost: the tests see only the
  **public** headers of the module under test (say so, and offer to move a header to `Public` when a test needs it),
  and a new module needs project files regenerated and an editor restart.
* **Inside the game module** (`Source\<Project>\Tests`): simplest, can reach private headers; fine for a small project.

If an existing test module is already there (`Source\*Tests*`, `*TestRunner*`), use it and do not ask. For a separate module:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<run-tests skill dir>/scripts/run_tests.ps1" -ProjectPath "<project>" -NewTestModule <Name> [-Plugin <PluginName>] [-TestedModule <Module>]
```

Name it `<Plugin>TestRunner` / `<Project>Tests`. It creates `Source\<Name>` (or `Plugins\<Plugin>\Source\<Name>`) with `Build.cs`
(depends on the module under test, `FunctionalTesting` for non-Shipping), module `.h/.cpp`, and adds an `Editor` module entry
to the `.uproject` / `.uplugin`. Then regenerate the project files (`devops_data\generate_project_files.bat`), editor closed.
Test data files (images, ini, json) go to `<Module>\Data`, the way `OpenAITestRunner\Data` does. The test category must still
start with the project name (or run with `-Filter <prefix>`), see step 4.

## 3. Create the file

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<run-tests skill dir>/scripts/run_tests.ps1" -ProjectPath "<project>" -NewSpec <ClassName>Tests -Dir Tests\<Area>
powershell -NoProfile -ExecutionPolicy Bypass -File "<run-tests skill dir>/scripts/run_tests.ps1" -ProjectPath "<project>" -NewTest <Name> -Dir Tests
```

With a test module add `-Module <Name>` (`-Dir` is then relative to the module's `Private`, default `Private` itself):
`... -NewSpec <ClassName>Tests -Module <Name> [-Dir <Area>]`.

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
