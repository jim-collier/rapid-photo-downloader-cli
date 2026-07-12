# NSIS installer for the Windows build. makensis runs on Linux, so cicd/cicd.bash
# cross-produces a single self-contained setup .exe per arch (the rpdc binary is a
# static Go exe - no runtimes to bundle). Installs to Program Files, puts rpdc on
# the system PATH, and upgrades an existing install in place (detected via the
# uninstall registry key). .msi is deferred (needs WiX / a Windows runner).
#
# Driven with makensis defines from the pipeline:
#   -DVERSION=X.Y.Z  -DARCH=amd64|arm64  -DSRCEXE=<built exe>  -DOUTFILE=<setup exe>

Unicode true
ManifestDPIAware true

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "WinMessages.nsh"
!include "StrFunc.nsh"

# StrFunc: declare the helpers we use (install uses StrStr; uninstall uses StrRep).
${StrStr}
${UnStrRep}

!ifndef VERSION
  !define VERSION "0.0.0"
!endif
!ifndef ARCH
  !define ARCH "amd64"
!endif
!ifndef SRCEXE
  !error "SRCEXE not defined (path to the built rpdc windows .exe)"
!endif
!ifndef OUTFILE
  !define OUTFILE "rpdc-setup.exe"
!endif

!define APPNAME  "Rapid Photo Downloader CLI"
!define EXENAME  "rpdc.exe"
!define PUBLISHER "Jim Collier"
!define UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\rpdc"
!define ENVKEY    "System\CurrentControlSet\Control\Session Manager\Environment"

Name "${APPNAME}"
OutFile "${OUTFILE}"
InstallDir "$PROGRAMFILES64\${APPNAME}"
RequestExecutionLevel admin        # Program Files + system PATH need elevation
SetCompressor /SOLID lzma
BrandingText "${APPNAME} ${VERSION} (${ARCH})"

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName"    "${APPNAME}"
VIAddVersionKey "FileVersion"    "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "CompanyName"    "${PUBLISHER}"
VIAddVersionKey "FileDescription" "${APPNAME} installer"
VIAddVersionKey "LegalCopyright" "Copyright (C) 2026 ${PUBLISHER}"

!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

# Upgrade in place: if a prior install is recorded, install over it.
Function .onInit
	SetRegView 64
	ReadRegStr $0 HKLM "${UNINSTKEY}" "InstallLocation"
	${If} $0 != ""
		StrCpy $INSTDIR "$0"
	${EndIf}
FunctionEnd

# Append $INSTDIR to the system PATH, but only if it is not already there.
Function PathEnsure
	Push $0
	Push $1
	ReadRegStr $0 HKLM "${ENVKEY}" "Path"
	${StrStr} $1 "$0;" "$INSTDIR;"
	${If} $1 == ""
		${If} $0 == ""
			StrCpy $0 "$INSTDIR"
		${Else}
			StrCpy $0 "$0;$INSTDIR"
		${EndIf}
		WriteRegExpandStr HKLM "${ENVKEY}" "Path" "$0"
		SendMessage ${HWND_BROADCAST} ${WM_WININICHANGE} 0 "STR:Environment" /TIMEOUT=5000
	${EndIf}
	Pop $1
	Pop $0
FunctionEnd

Section "Install"
	SetRegView 64
	SetOutPath "$INSTDIR"
	File "/oname=${EXENAME}" "${SRCEXE}"
	WriteUninstaller "$INSTDIR\uninstall.exe"

	# Add/Remove Programs entry (drives clean upgrades + uninstall).
	WriteRegStr   HKLM "${UNINSTKEY}" "DisplayName"     "${APPNAME}"
	WriteRegStr   HKLM "${UNINSTKEY}" "DisplayVersion"  "${VERSION}"
	WriteRegStr   HKLM "${UNINSTKEY}" "Publisher"       "${PUBLISHER}"
	WriteRegStr   HKLM "${UNINSTKEY}" "InstallLocation" "$INSTDIR"
	WriteRegStr   HKLM "${UNINSTKEY}" "DisplayIcon"     "$INSTDIR\${EXENAME}"
	WriteRegStr   HKLM "${UNINSTKEY}" "UninstallString" "$INSTDIR\uninstall.exe"
	WriteRegStr   HKLM "${UNINSTKEY}" "QuietUninstallString" "$INSTDIR\uninstall.exe /S"
	WriteRegDWORD HKLM "${UNINSTKEY}" "NoModify" 1
	WriteRegDWORD HKLM "${UNINSTKEY}" "NoRepair" 1

	Call PathEnsure
SectionEnd

Function un.onInit
	SetRegView 64
FunctionEnd

Section "Uninstall"
	SetRegView 64
	Delete "$INSTDIR\${EXENAME}"
	Delete "$INSTDIR\uninstall.exe"
	RMDir  "$INSTDIR"
	DeleteRegKey HKLM "${UNINSTKEY}"

	# Drop our entry from the system PATH (all three join positions).
	ReadRegStr $0 HKLM "${ENVKEY}" "Path"
	${UnStrRep} $0 "$0" ";$INSTDIR" ""
	${UnStrRep} $0 "$0" "$INSTDIR;" ""
	${UnStrRep} $0 "$0" "$INSTDIR"  ""
	WriteRegExpandStr HKLM "${ENVKEY}" "Path" "$0"
	SendMessage ${HWND_BROADCAST} ${WM_WININICHANGE} 0 "STR:Environment" /TIMEOUT=5000
SectionEnd
