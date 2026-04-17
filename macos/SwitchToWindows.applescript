-- Monitor Switcher - Switch to Windows
-- This AppleScript will run the monitor switcher command

-- Get the directory containing this script
set scriptPath to POSIX path of ((path to me as text) & "::")
set projectRoot to do shell script "dirname " & quoted form of scriptPath

do shell script "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH && " & quoted form of (projectRoot & "/switch.sh") & " windows"
