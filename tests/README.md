# Unreal Engine scripts for testing

## Requirements
* [Python](https://www.python.org)
* [OpenCppCoverage](https://github.com/OpenCppCoverage/OpenCppCoverage/releases/tag/release-0.9.9.0)
* [nodejs](https://nodejs.org/en/download)

## Test files creation
* **create_spec_file.bat** helps to create a spec file for testing
* **create_test_file.bat** helps to create a legacy test file

## Setup and run
* **setup_tests.bat** installs all requirement files to **data** for local test running (**data** folder added in **.gitignore** file of repository)
* **run_tests.bat** runs all tests of your project and shows the test report and the test coverage report

## Utils
* **Utils** contains helpful files for test writing. You can add these files to your project, inside **Tests** subfolder for instance. Don't forget to edit generic include lines:
```
#include "<Path>/Utils/JsonUtils.h"
```
* For usage, you need to add the following modules to your project build file **MyGame.Build.cs**
```
PublicDependencyModuleNames.AddRange(new string[] { "Json", "JsonUtilities", "UMG"});

if (Target.Configuration != UnrealTargetConfiguration.Shipping)
{
    PublicDependencyModuleNames.Add("FunctionalTesting");
}
```