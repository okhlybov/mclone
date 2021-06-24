// PATH management extension for the Inno Setup installer generatior
// Version: 1.0
// Author: Oleg A. Khlybov <fougas@mail.ru>
// Homepage: https://bitbucket.org/fougas/isx
// License: 3-clause BSD
// Inno Setup target version: 5.5

type
  PathType = (UserPath, SystemPath);
  PathMode = (Append, Prepend);
  Paths = array of String;

var
  preUsr, postUsr, preSys, postSys, addUsr, addSys : Paths;

procedure AddToPaths(var ps: Paths; s: String);
var
  i: Integer;
begin
  i := Length(ps);
  SetLength(ps, i+1);
  ps[i] := ExpandConstant(s);
end;

procedure JoinPaths(var dst: Paths; src: Paths);
var
  i: Integer;
begin
  for i :=0 to Length(src)-1 do AddToPaths(dst, src[i]);
end;

function MergePaths(paths: Paths): String;
var
  i: Integer;
begin
  if Length(paths) > 0 then begin
    if paths[0] <> '' then result := paths[0];
    for i := 1 to Length(paths)-1 do begin
      if paths[i] <> '' then result := result + ';' + paths[i];
    end;
  end;
end;

function SplitPaths(path: String): Paths;
var
  first, last, count, total: Integer;
begin
  first := 1;
  last := 1;
  count := 0;
  total := Length(path);
  while last <= total do begin
    while (last <= total) and (path[last] <> ';') do Inc(last);
    if last > first then begin
      Inc(count);
      SetLength(result, count);
      result[count-1] := Copy(path, first, last-first);
      first := last+1;
      Inc(last);
    end
    else begin
      Inc(first);
      Inc(last);
    end;
  end;
end;

procedure RegisterPath(path: String; t: PathType; m: PathMode);
begin
  case t of
    UserPath:
      case m of
        Prepend: AddToPaths(preUsr, path);
        Append: AddToPaths(postUsr, path);
      end;
    SystemPath:
      case m of
        Prepend: AddToPaths(preSys, path);
        Append: AddToPaths(postSys, path);
      end;
  end;
end;

procedure RegisterPaths; forward; // A madnadory user-supplied procedure

const
  SysPathKey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment';
  UsrPathKey = 'Environment';

function GetSysPaths: Paths;
var
  path: String;
begin
  RegQueryStringValue(HKLM, 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment', 'PATH', path);
  result := SplitPaths(path);
end;

procedure SetSysPaths(paths: Paths);
begin
  RegWriteStringValue(HKLM, 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment', 'PATH', MergePaths(paths));
end;

function GetUsrPaths: Paths;
var
  path: String;
begin
  RegQueryStringValue(HKCU, 'Environment', 'PATH', path);
  result := SplitPaths(path);
end;

procedure SetUsrPaths(paths: Paths);
begin
  RegWriteStringValue(HKCU, 'Environment', 'PATH', MergePaths(paths));
end;

procedure InstallPaths(s: TSetupStep);
var
  uninstaller: String;
  paths: Paths;
begin
  uninstaller := ExpandConstant('Software\Microsoft\Windows\CurrentVersion\Uninstall\{#emit SetupSetting("AppId")}_is1');
  if s = ssInstall then begin
    RegisterPaths;
    // Construct system-wide paths
    SetLength(paths, 0);
    JoinPaths(paths, preSys);
    JoinPaths(paths, GetSysPaths);
    JoinPaths(paths, postSys);
      SetSysPaths(paths);
    SetLength(addSys, 0);
    JoinPaths(addSys, preSys);
    JoinPaths(addSys, postSys);
    // Construct per-user paths
    SetLength(paths, 0);
    JoinPaths(paths, preUsr);
    JoinPaths(paths, GetUsrPaths);
    JoinPaths(paths, postUsr);
      SetUsrPaths(paths);
    SetLength(addUsr, 0);
    JoinPaths(addUsr, preUsr);
    JoinPaths(addUsr, postUsr);
  end else if s = ssPostInstall then begin
      RegWriteStringValue(HKLM, uninstaller, 'AddedSystemPaths', MergePaths(addSys)); // Remember added system paths
      RegWriteStringValue(HKLM, uninstaller, 'AddedUserPaths', MergePaths(addUsr)); // Remember added user paths
  end;
end;

procedure SubtractPaths(var dst: Paths; src: Paths);
var
  s, d: Integer;
  dst2, src2: Paths;
begin
  // Perform case-insensitive comparison
  SetLength(src2, Length(src));
  for s := 0 to Length(src)-1 do src2[s] := AnsiLowercase(src[s]);
  SetLength(dst2, Length(dst));
  for d := 0 to Length(dst)-1 do dst2[d] := AnsiLowercase(dst[d]);
  for d := 0 to Length(dst2)-1 do begin
    for s := 0 to Length(src2)-1 do begin
      if dst2[d] = src2[s] then begin dst[d] := ''; end;
    end;
  end;
end;

procedure RevertPaths(s: TUninstallStep);
var
  path, uninstaller: String;
  paths, usrPaths, sysPaths: Paths;
begin
  uninstaller := ExpandConstant('Software\Microsoft\Windows\CurrentVersion\Uninstall\{#emit SetupSetting("AppId")}_is1');
  path := '';
  RegQueryStringValue(HKLM, uninstaller, 'AddedSystemPaths', path);
  if path <> '' then begin
    sysPaths := SplitPaths(path);
    paths := GetSysPaths;
    SubtractPaths(paths, sysPaths);
    SetSysPaths(paths);
  end;
  path := '';
  RegQueryStringValue(HKLM, uninstaller, 'AddedUserPaths', path);
  if path <> '' then begin
    usrPaths := SplitPaths(path);
    paths := GetUsrPaths;
    SubtractPaths(paths, usrPaths);
    SetUsrPaths(paths);
  end;
end;

procedure CurStepChanged(s: TSetupStep);
begin
  InstallPaths(s); { Include this call upon rolling out the custom CurStepChanged() procedure }
end;

procedure CurUninstallStepChanged(s: TUninstallStep);
begin
  RevertPaths(s);  { Include this call upon rolling out the custom CurUninstallStepChanged() procedure }
end;