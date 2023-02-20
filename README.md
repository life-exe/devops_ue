# Unreal Engine devops

![alt text](https://github.com/life-exe/devops_ue/blob/master/assets/logo.png)

This lightweight repository is a part of [Unreal Engine Automation and Testing course](https://youtube.com/playlist?list=PL2XQZYeh2Hh-PdSglBEm520Eboph1GcA2).
You can use it with any Unreal Engine project to speed to up your development process.

The course has its [own wiki](https://lifeexe-art.gitbook.io/unreal-automation).

Each subfolder of the current repo has an additional readme page for further information.

## Features

* UE source automatization (clone, setup, build, custom installed build)
* UE projects automatization (build, cook, package)
* Game, Client, Server (dedicated, listen) builds
* Code format with .clang-format
* Test automation, code coverage
* Documentation generation with doxygen
* Jenkins' pipelines
* GitHub webhooks, slack notifications, scheldures, ngrok etc.

## How To Setup

* Add this repository as a submodule for your UE project:

```
git submodule add https://github.com/life-exe/devops_ue
```

* Launch following bat file inside **devops_ue** folder (you can skip the current step if you don't need docs generation):

```
update_submodules.bat
```

* Next launch the following bat file inside **devops_ue** folder:

```
setup.bat
```

* **Setup.bat** will create **devops_data** folder in the root of your main project with the following artifacts:

```
+- Source
+- Content
+- Config
+- ...
+- devops_ue
|    +- update_submodules.bat
|    +- setup.bat
|    +- ...
+- devops_data
|    +- config.bat
|    +- format_all_files.bat
|    +- generate_project_files.bat
|    +- clean_intermediate_files.bat
|    +- run_tests.bat
|    +- generate_docs.bat
|    +- .clang-format
|    +- .gitignore
|    +- Doxyfile
|    +- LICENSE.md
|    +- README.md
```

* The main file that you need to config is **config.bat**
* Required variables you need to edit accordingly to your local path in this file are: **EnginePath, ProjectPureName, VersionSelector**
* Commit **config.bat** to your repository if you are working alone, otherwise don't do this and just keep this file as local
* **Doxyfile** is for docs generation with doxygen. You can edit all properties that you need and then commit **Doxyfile** to your repo. Or just delete this file if you don't need docs generation. Most important property to edit:

```
PROJECT_NAME           = "My Project"
```

* All other artifacts are optional, you can move them to the root of your repo, commit and use or just delete them. The final version of your repo might look like this:

```
+- Source
+- Content
+- Config
+- ...
+- devops_ue
|    +- update_submodules.bat
|    +- setup.bat
|    +- ...
+- devops_data
|    +- config.bat
|    +- Doxyfile
+- format_all_files.bat
+- generate_project_files.bat
+- clean_intermediate_files.bat
+- run_tests.bat
+- generate_docs.bat
+- .clang-format
+- .gitignore
+- LICENSE.md
+- README.md
```

* Now you can quickly generate project files, format all source files with **.clang-format**, clean intermediates, run tests and docs generation
* More useful scripts can be found inside other folders of **devops_ue**

## Resources

* [youtube playlist of the course](https://www.youtube.com/watch?v=25Ru2h4G0aQ&list=PL2XQZYeh2Hh-PdSglBEm520Eboph1GcA2)
* [wiki](https://lifeexe-art.gitbook.io/unreal-automation)
* [docs](https://life-exe.github.io/UnrealTPSGame)

## Enjoy! 🚀️