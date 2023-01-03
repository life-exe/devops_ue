# Unreal Engine scripts for docs generation

## Requirements
* [Doxygen](https://doxygen.nl)
* [Pyhton](https://doxygen.nl)
* Current folder has 3 submodules. You need to launch a command:
```
git submodule update --init --recursive --remote
```
## How To
* Launching **config_doxygen.bat** will create **Doxyfile** in **devops_data** from **setup/Doxyfile.template**. **Doxyfile** is already there if you launched **setup.bat** before.
* You can generate your own **Doxyfile** from scratch if you like with a command:
```
doxygen -g Doxyfile
```
* Launching **generate_docs.bat** will create complete documentation for your project in the **Documentation** folder at the root of your project:
```
+- Source
+- Content
+- Config
+- Documentation
+- ...
+- devops_ue
+- devops_data
```
## [For more information you can watch following video](https://youtu.be/wvy6lLt1YfY)
