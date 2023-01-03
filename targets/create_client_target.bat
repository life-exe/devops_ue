:: Copyright LifeEXE. All Rights Reserved.
@echo off

call "%~dp0..\..\devops_data\config.bat"

set TARGET_TYPE=Client
set MODULE_NAME=%ProjectPureName%
set TargetFileName=%MODULE_NAME%%TARGET_TYPE%.Target.cs
set TargetFilePath=%SourceCodePath%\%TargetFileName%

call "%~dp0create_target_template.bat"
