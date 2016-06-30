@echo off
color 8f
title Farm Foreman
echo Farm Foreman (Version 2.6)
echo Copyright (c) 2012 Lucas Bleackley Petter.
echo.
:LOOKFORAVAILABLEJOBS
   echo --------------------------------------------------
   echo.
   echo Looking for available render jobs...
   net use R: \\10.0.0.1\render /u:yourusername yourpassword > nul 2>nul
   setlocal EnableDelayedExpansion
   dir R:\FarmForeman\JobQueue /o:nd > nul 2>nul
   for /r R:\FarmForeman\JobQueue %%i in (*RenderJob*.txt*) do (
      set renderJobInputFile=%%i
      findstr /i /m /c:"Done render job." /c:"Job failed." %%i > nul 2>nul
      if !errorlevel! gtr 0 goto GETJOBVARIABLES
   )
   echo No jobs found. Waiting until a new one is added.
   goto WAITFORAVAILABLEJOBS
:WAITFORAVAILABLEJOBS
   timeout /t 600 /nobreak
   goto LOOKFORAVAILABLEJOBS
:GETJOBVARIABLES
   setlocal DisableDelayedExpansion
   for /f "tokens=1-8* eol=; delims=, " %%a in (%renderJobInputFile%) do (
      set renderName=%%a
      set /a startFrame=%%b
      set /a endFrame=%%c
      set /a byFrame=%%d
      set cameraName=%%e
      set projectFolder=%%f
      set sceneFile=%%g
      set emailAddress=%%h
   )
   echo Found job "%renderName%".
   echo Job will render frames %startframe%-%endFrame%, every %byFrame% frames, using camera "%cameraName%".
   echo.
:CHECKFORERRORS
   echo Checking for errors...
   if %startFrame% gtr %endFrame% (
      echo ;%date% %time%. Job failed. The starting frame is greater than the ending frame.>> %renderJobInputFile%
      echo Job failed. The starting frame is greater than the ending frame.
      echo Farm Foreman will wait a few minutes before reassessing available render jobs.
      goto WAITFORAVAILABLEJOBS
   )
   if not exist R:\%projectFolder% (
      echo ;%date% %time%. Job failed. The project folder specified does not exist.>> %renderJobInputFile%
      echo Job failed. The project folder specified does not exist.
      echo Farm Foreman will wait a few minutes before reassessing available render jobs.
      goto WAITFORAVAILABLEJOBS
   )
   if not exist R:\%projectFolder%\scenes\%sceneFile% (
      echo ;%date% %time%. Job failed. The scene file specified does not exist.>> %renderJobInputFile%
      echo Job failed. The scene file specified does not exist.
      echo Farm Foreman will wait a few minutes before reassessing available render jobs.
      goto WAITFORAVAILABLEJOBS
   )
   if not exist "C:\Program Files\Autodesk\Maya2013\bin\Render.exe" (
      echo ;%date% %time%. Could not proceed with rendering because Maya is not installed on this computer. [Worker %computername%]>> %renderJobInputFile%
      echo Could not proceed with rendering because Maya is not installed on this computer.
      echo Quitting Farm Foreman now.
      goto END
   )
   echo No errors found.
   echo.
:RENDERJOBSETUP
   echo Setting up and loading project...
   powercfg -change -standby-timeout-ac 0
   powercfg -change -hibernate-timeout-ac 0
   PATH=%PATH%;C:\Program Files\Autodesk\Maya2013\bin;
   md %temp%\fftemp > nul 2>nul
   set TEMP=%temp%\fftemp
   set TMPDIR=%TEMP%
   set /a frameNumber=%startFrame%
   set renderLog=R:\FarmForeman\JobLogs\RenderLog_%renderName%.txt
   xcopy /z /e /i R:\%projectFolder% %TEMP%\project /exclude:R:\FarmForeman\data\xcopyExcludeList.txt > nul 2>nul
   if %errorlevel% gtr 0 (
      echo ;%date% %time%. Job failed. Could not load the job's scene file.>> %renderJobInputFile%
      echo Job failed. Could not load the job's scene file.
      echo Farm Foreman will wait a few minutes before reassessing available render jobs.
      goto WAITFORAVAILABLEJOBS
   )
   echo Setup done, starting render now.
   echo.
   findstr /i /m /c:"Started render job." %renderJobInputFile% > nul 2>nul
   if %errorlevel% neq 0 (
      echo ;%date% %time%. Started render job.>> %renderJobInputFile%
   )
   findstr /i /m /c:"Started render job." %renderLog% > nul 2>nul
   if %errorlevel% neq 0 (
      echo %date% %time% - %renderName% - %cameraName% - Started render job. Frames %startFrame%-%endFrame%, every %byFrame% frames.>> %renderLog%
   )
:CHECKIFLASTFRAME
   if %frameNumber% leq %endFrame% (
      goto CHECKFORNEXTFRAME
   ) else (
      goto FINALREVIEW_WAITFOROTHERSTOFINISH
   )
:CHECKFORNEXTFRAME
   findstr /i /m /c:"Frame %frameNumber% - Rendering..." %renderLog% > nul 2>nul
   if %errorlevel%==0 (
      echo %time% - %renderName%, Frame %frameNumber% - Skipping.
      set /a frameNumber+=%byFrame%
      goto CHECKIFLASTFRAME
   ) else (
      goto RENDER
   )
:RENDER
   echo %date% %time% - %renderName% - %cameraName% - Frame %frameNumber% - Rendering... [Worker %computername%]>> %renderLog%
   echo %time% - %renderName%, Frame %frameNumber% - Rendering...
   "C:\Program Files\Autodesk\Maya2013\bin\Render" -r file -s %frameNumber% -e %frameNumber% -b 1 -cam %cameraName% -mr:rt 8 -mr:v 0 -rd "R:\FarmForeman\RenderImages\%renderName%" -proj "%TEMP%\project" "%TEMP%\project\scenes\%sceneFile%" > nul 2>nul
   if %errorlevel%==0 (
      echo %date% %time% - %renderName% - %cameraName% - Frame %frameNumber% - Done. [Worker %computername%]>> %renderLog%
      echo %time% - %renderName%, Frame %frameNumber% - Done. Out of %endFrame%.
   ) else (
      echo %date% %time% - %renderName% - %cameraName% - Frame %frameNumber% - Error! %errorlevel% There was a problem rendering this frame. [Worker %computername%]>> %renderLog%
      echo %time% - %renderName%, Frame %frameNumber% - Error! There was a problem rendering this frame.
   )
   if %frameNumber% equ %endFrame% (
      echo %date% %time% - %renderName% - %cameraName% - Done the last frame in the sequence.>> %renderLog%
      echo Done the last frame in the sequence.
      echo Waiting for other workers to finish the final frames.
      timeout /t 900 /nobreak
      echo.
   )
   if %byFrame% gtr 1 (
      set /a byFrameEndCheck=%frameNumber%+%byFrame%-1
   ) else (
      set byFrameEndCheck=null
   )
   if %byFrameEndCheck% equ %endFrame% (
      echo %date% %time% - %renderName% - %cameraName% - Done the last frame in the sequence.>> %renderLog%
      echo Done the last frame in the sequence.
      echo Waiting for other workers to finish the final frames.
      timeout /t 900 /nobreak
      echo.
   )
   set /a frameNumber+=%byFrame%
   goto CHECKIFLASTFRAME
:FINALREVIEW_WAITFOROTHERSTOFINISH
   findstr /i /m /c:"Done the last frame in the sequence." %renderLog% > nul 2>nul
   if %errorlevel%==0 (
      set /a frameNumber=%startFrame%
      echo Checking for missing frames...
      goto FINALREVIEW_CHECKIFLASTFRAME
   ) else (
      echo.
      echo Waiting for other workers to finish the final frames.
      timeout /t 120 /nobreak
      goto FINALREVIEW_WAITFOROTHERSTOFINISH
   )
:FINALREVIEW_CHECKIFLASTFRAME
   if %frameNumber% leq %endFrame% (
      goto FINALREVIEW_CHECKFORNEXTFRAME
   ) else (
      echo Waiting for other workers to finish any missing frames.
      timeout /t 900 /nobreak
      echo Done checking for missing frames.
      echo.
      goto CLEANUP
   )
:FINALREVIEW_CHECKFORNEXTFRAME
   findstr /i /m /c:"Frame %frameNumber% - Done." %renderLog% > nul 2>nul
   if %errorlevel%==0 (
      set /a frameNumber+=%byFrame%
      goto FINALREVIEW_CHECKIFLASTFRAME
   ) else (
      goto FINALREVIEW_RENDERMISSINGFRAME
   )
:FINALREVIEW_RENDERMISSINGFRAME
   echo %date% %time% - %renderName% - %cameraName% - Frame %frameNumber% - Rendering missing frame... [Worker %computername%]>> %renderLog%
   echo %time% - %renderName%, Frame %frameNumber% - Was not fully rendered, rendering now...
   "C:\Program Files\Autodesk\Maya2013\bin\Render" -r file -s %frameNumber% -e %frameNumber% -b 1 -cam %cameraName% -mr:rt 8 -mr:v 0 -rd "R:\FarmForeman\RenderImages\%renderName%" -proj "%TEMP%\project" "%TEMP%\project\scenes\%sceneFile%" > nul 2>nul
   if %errorlevel%==0 (
      echo %date% %time% - %renderName% - %cameraName% - Frame %frameNumber% - Done. [Worker %computername%]>> %renderLog%
      echo %time% - %renderName%, Frame %frameNumber% - Done.
   ) else (
      echo %date% %time% - %renderName% - %cameraName% - Frame %frameNumber% - Error! %errorlevel% There was a problem rendering this missing frame. [Worker %computername%]>> %renderLog%
      echo %time% - %renderName%, Frame %frameNumber% - Error! There was a problem rendering this missing frame.
   )
   set /a frameNumber+=%byFrame%
   goto FINALREVIEW_CHECKIFLASTFRAME
:CLEANUP
   echo Cleaning up...
   findstr /i /m /c:"Done render job." %renderJobInputFile% > nul 2>nul
   if %errorlevel% neq 0 (
      echo ;%date% %time%. Done render job.>> %renderJobInputFile%
   )
   findstr /i /m /c:"Done render job." %renderLog% > nul 2>nul
   if %errorlevel% neq 0 (
      echo %date% %time% - %renderName% - %cameraName% - Done render job.>> %renderLog%
      echo Archiving images into zip file...
      call R:\FarmForeman\data\zip\zip.exe -9 -r %TEMP%\RenderedImages_%renderName%.zip R:\FarmForeman\RenderImages\%renderName% > nul 2>nul
      echo Computing checksum for zip file...
      echo File size in bytes, SHA1 checksum and filename for the uploaded zip file:>> %renderLog%
      call R:\FarmForeman\data\sha1deep\sha1deep64.exe -b -z %TEMP%\RenderedImages_%renderName%.zip>> %renderLog%
      echo Uploading zip file...
      call R:\FarmForeman\data\curl\curl.exe --upload-file %TEMP%\RenderedImages_%renderName%.zip ftp://yourusername:yourpassword@yourdomain.com > nul 2>nul
      echo Moving images into place...
      md R:\%projectFolder%\images\%renderName%
      move /y R:\FarmForeman\RenderImages\%renderName%\* R:\%projectFolder%\images\%renderName% > nul 2>nul
      call R:\FarmForeman\data\blat\blat.exe -to %emailAddress% -f farmforeman@example.com -server smtp.yourdomain.com -subject "Render Job [%renderName%] Has Finished" -body "Farm Foreman finished rendering the job [%renderName%] on %date% at %time%. The job's log file is attached and the images have been uploaded to your FTP server." -attach %renderLog% > nul 2>nul
   )
   rd %TEMP% /s /q > nul 2>nul
   echo Done cleaning up.
   echo.
   echo Done render job "%renderName%".
   echo.
   goto LOOKFORAVAILABLEJOBS
:END
   rd %TEMP% /s /q > nul 2>nul
   net use R: /delete /yes > nul 2>nul
   exit
