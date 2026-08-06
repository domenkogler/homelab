@echo off
REM Update the pi coding agent AND sync this repo's skills into pi's agent
REM skills dir (~/.pi/agent/skills). The repo skills/ folder is the source of
REM truth: edit there, commit, then run this to deploy to pi.
REM Note: robocopy exit codes 0-7 are success; only >=8 is a real failure.

volta install @earendil-works/pi-coding-agent

set "PI_SKILLS=%USERPROFILE%\.pi\agent\skills"
robocopy "%~dp0skills\plan-task"     "%PI_SKILLS%\plan-task"     /E /NFL /NDL /NJH /NJS
robocopy "%~dp0skills\run-task"       "%PI_SKILLS%\run-task"       /E /NFL /NDL /NJH /NJS
robocopy "%~dp0skills\platform-env"   "%PI_SKILLS%\platform-env"   /E /NFL /NDL /NJH /NJS
robocopy "%~dp0skills\mikrotik"       "%PI_SKILLS%\mikrotik"       /E /NFL /NDL /NJH /NJS
robocopy "%~dp0skills\shelly"         "%PI_SKILLS%\shelly"         /E /NFL /NDL /NJH /NJS

REM Session-start config: AGENTS.md (auto-loaded) + /start prompt template.
REM NOTE: robocopy overwrites ~/.pi/agent\AGENTS.md and ~/.pi/agent\prompts\*.
set "PI_CONFIG=%USERPROFILE%\.pi\agent"
robocopy "%~dp0pi-agent" "%PI_CONFIG%" /E /NFL /NDL /NJH /NJS
