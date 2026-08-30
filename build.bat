@echo off
setlocal

rem cl and clang++ are only on PATH inside a developer prompt. Locating the
rem toolchain here is what lets `devrun task build-instruments` work from any
rem shell. vcvars is silenced because it reports on stderr even when it
rem succeeds; the `where cl` below is the real success check.
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
set VSPATH=
where cl >nul 2>&1 || for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSPATH=%%i"
if defined VSPATH call "%VSPATH%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
where cl >nul 2>&1 || (echo ABORTING: no MSVC toolchain found & exit /b 1)

set HaveClang=1
where clang++ >nul 2>&1 || set HaveClang=0
if "%HaveClang%"=="0" echo Skipping the clang variants: clang++ is not on PATH.

if not exist obj mkdir obj

rem _CRT_SECURE_NO_WARNINGS because -WX promotes the C4996 deprecation notices
rem on fopen and sprintf to errors, and the _s replacements MSVC suggests do not
rem exist on the clang path in build.sh.
set CLLinkFlags=-incremental:no -opt:ref -machine:x64 -manifest:no -subsystem:console kernel32.lib user32.lib
set CLCompileFlags=-D_CRT_SECURE_NO_WARNINGS -Zi -Fdobj\ -d2Zi+ -Gy -GF -GR- -EHs- -EHc- -EHa- -WX -W4 -nologo -FC -Gm- -diagnostics:column -fp:except- -fp:fast
set CLRelease=-Oi -Oxb2 -O2
set CLANGCompileFlags=-g 
set CLANGLinkFlags=-fuse-ld=lld -Wl,-subsystem:console,kernel32.lib,user32.lib

echo -----------------
echo Building termbench debug:
call cl -Fetermbench_debug_msvc.exe -Foobj\termbench_debug_msvc.obj -Od %CLCompileFlags% termbench.cpp /link %CLLinkFlags% -PDB:obj\termbench_debug_msvc.pdb -RELEASE
if "%HaveClang%"=="1" call clang++ %CLANGCompileFlags% %CLANGLinkFlags% termbench.cpp -o termbench_debug_clang.exe

echo -----------------
echo Building termbench release:
call cl -Fetermbench_release_msvc.exe -Foobj\termbench_release_msvc.obj %CLRelease% %CLCompileFlags% termbench.cpp /link %CLLinkFlags% -PDB:obj\termbench_release_msvc.pdb -RELEASE
if "%HaveClang%"=="1" call clang++ -O3 %CLANGCompileFlags% %CLANGLinkFlags% termbench.cpp -o termbench_release_clang.exe

rem alacritree-ab/round.ps1 loads these three from the repo root by name, so the
rem names here are the interface and not a preference.
echo -----------------
echo Building the instruments the harnesses load:
call cl -Fetermbench_ab.exe -Foobj\termbench_ab.obj %CLRelease% %CLCompileFlags% termbench.cpp /link %CLLinkFlags% -PDB:obj\termbench_ab.pdb -RELEASE
call cl -Fesgrtest.exe -Foobj\sgrtest.obj %CLRelease% %CLCompileFlags% sgrtest.cpp /link %CLLinkFlags% -PDB:obj\sgrtest.pdb -RELEASE
call cl -Fescrolltest_ab.exe -Foobj\scrolltest_ab.obj %CLRelease% %CLCompileFlags% scrolltest.cpp /link %CLLinkFlags% -PDB:obj\scrolltest_ab.pdb -RELEASE
