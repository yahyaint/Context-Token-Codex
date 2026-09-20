' SPDX-License-Identifier: MIT
Option Explicit
Dim shell, fso, folder, command
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
folder = fso.GetParentFolderName(WScript.ScriptFullName)
command = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & folder & "\Overlay.ps1"""
If WScript.Arguments.Count > 0 Then
  If WScript.Arguments(0) = "/watch" Then command = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & folder & "\Watch-App.ps1"""
End If
shell.Run command, 0, False
