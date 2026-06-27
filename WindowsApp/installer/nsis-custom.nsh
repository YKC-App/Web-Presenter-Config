; NDI Monitor — custom NSIS script fragments
; Included by electron-builder's NSIS target.

; Check for NDI Runtime and prompt install if missing
!macro customInstall
  ; Check if NDI runtime DLL is present (from Vizrt NDI Tools)
  IfFileExists "$SYSDIR\Processing.NDI.Lib.x64.dll" ndi_ok
    MessageBox MB_YESNO|MB_ICONQUESTION \
      "NDI Runtime is not installed. $\n\
      NDI Monitor requires the free NDI Tools from ndi.video.$\n\
      $\n\
      Would you like to open the NDI Tools download page now?" \
      IDNO ndi_skip
    ExecShell "open" "https://ndi.video/tools/ndi-tools/"
    ndi_skip:
  ndi_ok:
!macroend

!macro customUnInstall
  ; Nothing extra to do on uninstall
!macroend
