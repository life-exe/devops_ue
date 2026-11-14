# Copyright LifeEXE. All Rights Reserved.
# Creates an empty level. Runs inside the editor:
#   UnrealEditor-Cmd.exe Project.uproject -run=pythonscript -script="create_main_level.py"
# Level path is taken from UE_NEW_LEVEL_PATH env var (default: /Game/Maps/MainLevel).

import os
import unreal

level_path = os.environ.get("UE_NEW_LEVEL_PATH", "/Game/Maps/MainLevel")

world = unreal.EditorLoadingAndSavingUtils.new_blank_map(False)
if world is None:
    unreal.log_error("[create_main_level] Failed to create a blank map")
else:
    if unreal.EditorLoadingAndSavingUtils.save_map(world, level_path):
        unreal.log("[create_main_level] Saved " + level_path)
    else:
        unreal.log_error("[create_main_level] Failed to save " + level_path)
