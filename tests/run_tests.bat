:: Copyright LifeEXE. All Rights Reserved.
@echo off

call "%~dp0..\..\devops_data\config.bat"

:: https://stackoverflow.com/a/20999154
set Before=public bool UnoptimizedCode = false;
set After=public bool UnoptimizedCode = true;
set File=%SourceCodePath%\%ProjectPureName%Editor.Target.cs
call :REPLACEINFILE "%File%" "%Before%" "%After%"

rem build sources
call "%RunUATPath%" BuildCookRun ^
-project="%ProjectPath%" ^
-platform="%Platform%" ^
-clientconfig="%Configuration%" ^
-build -cook -ubtargs="-UnoptimizedCode"
set BuildResult=%errorlevel%

rem restore target file right after the build
call :REPLACEINFILE "%File%" "%After%" "%Before%"
if not "%BuildResult%"=="0" (
    echo Build failed with code %BuildResult%
    exit /b %BuildResult%
)

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

if not defined ExcludedPathForTestReport set ExcludedPathForTestReport=%ExludedPathForTestReport%
call :NORMALIZEPATH "%ExcludedPathForTestReport%"
set ExcludedSources=%RETVAL%

"%OpenCPPCoveragePath%" --modules="%Module%" --sources="%Sources%" ^
--excluded_sources="%ExcludedSources%" --export_type="%ExportType%" -v -- %TestRunner%

rem clean obsolete artifacts
if exist LastCoverageResults.log del /q LastCoverageResults.log

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

:: Replaces text in a file only if it is there. Keeps UTF-8 (Out-File in Windows PowerShell writes UTF-16).
:REPLACEINFILE
  powershell -NoProfile -Command "$f = '%~1'; if (Test-Path -LiteralPath $f) { $t = [IO.File]::ReadAllText($f); $n = $t.Replace('%~2', '%~3'); if ($n -ne $t) { [IO.File]::WriteAllText($f, $n) } }"
  EXIT /B
