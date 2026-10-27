Option Explicit
Dim shell, fso, base, command
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName)
command = Chr(34) & base & "\Start_HEX.cmd" & Chr(34)
shell.Run command, 0, False
