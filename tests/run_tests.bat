:: Copyright LifeEXE. All Rights Reserved.
@echo off

call "%~dp0..\..\devops_data\config.bat"

:: https://stackoverflow.com/a/20999154
set Before=public bool UnoptimizedCode = false;
set After=public bool UnoptimizedCode = true;
set File=%SourceCodePath%\%ProjectPureName%Editor.Target.cs
powershell -Command "(gc '%File%') -replace '%Before%', '%After%' | Out-File  '%File%'"

rem build sources
call "%RunUATPath%" BuildCookRun ^
-project="%ProjectPath%" ^
-platform="%Platform%" ^
-clientconfig="%Configuration%" ^
-build -cook -ubtargs="-UnoptimizedCode"

rem run tests
set TestRunner="%EditorPath%" "%ProjectPath%" -ExecCmds="Automation RunTests %TestNames%;Quit" ^
-log -abslog="%TestOutputLogPath%" -nosplash -ReportExportPath="%ReportOutputPath%"

rem run code coverage
::set ExportType=cobertura:%ReportOutputPath%\Coverage\CodeCoverageReport.xml
set ExportType=html:%ReportOutputPath%\Coverage\CodeCoverageReport

call :NORMALIZEPATH "%ProjectRoot%"
set Module=%RETVAL%

call :NORMALIZEPATH "%SourceCodePath%"
set Sources=%RETVAL%

call :NORMALIZEPATH "%ExludedPathForTestReport%"
set ExludedSources=%RETVAL%

"%OpenCPPCoveragePath%" --modules="%Module%" --sources="%Sources%" ^
--excluded_sources="%ExludedSources%" --export_type="%ExportType%" -v -- %TestRunner%

rem clean obsolete artifacts
del /q LastCoverageResults.log
powershell -Command "(gc '%File%') -replace '%After%', '%Before%' | Out-File  '%File%'"

rem copy test artifacts
set TestsDir=%~dp0
set TestsDataDir=%~dp0data
robocopy "%TestsDataDir%" "%ReportOutputPath%" /E

rem start local server and show report
set Port=8081
set Localhost=http://localhost:%Port%

pushd "%ReportOutputPath%"
start "" "%Localhost%"
start "" "%Localhost%\Coverage\CodeCoverageReport\index.html"
call http-server -p="%Port%"
popd

:: ========== FUNCTIONS ==========
goto:EOF

:NORMALIZEPATH
  SET RETVAL=%~f1
  EXIT /B
