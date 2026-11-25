# Anno Mods fuer World of Tanks - Installer (Hitzone-Skins Erweiterung + Anpassen-Suche)
# Installiert zz_hitzone_friends.wotmod (+ optional hitzone.nostyle) in den Mod-Ordner,
# den WoT gerade laedt (paths.xml), und baut den T-832-Skin aus DEINEM eigenen
# Emets/PRO-Tanki-Hitzone-Paket (T32-Texturen). Einfach nach jedem Aslain-Lauf oder
# WoT-Patch nochmal starten.
#
# Aufruf ohne Parameter = Menue. Fuer Profis:
#   installer.ps1 -Aktion installieren|pruefen|entfernen|update [-Wot <Ordner>] [-NoStyle ja|nein] [-Anpassen ja|nein] [-KeinPause]
param(
  [string]$Aktion = '',
  [string]$Wot = '',
  [string]$NoStyle = '',
  [string]$Anpassen = '',
  [switch]$KeinPause
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$DATA = Split-Path -Parent $MyInvocation.MyCommand.Path      # ...\dateien
$ROOT = Split-Path -Parent $DATA                              # Installer-Ordner
$SETF = Join-Path $ROOT 'hitzone_einstellungen.txt'
$LOGF = Join-Path $ROOT 'hitzone_installer_log.txt'
$SRC_FRIENDS = Join-Path $DATA 'zz_hitzone_friends.wotmod'
$SRC_NOSTYLE = Join-Path $DATA 'hitzone.nostyle_1.1.0.wotmod'
$SRC_T832    = Join-Path $DATA 't832'
$SRC_ANNO    = Get-ChildItem -LiteralPath $DATA -Filter 'anno.c11n_search_*.wotmod' -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
$N_FRIENDS = 'zz_hitzone_friends.wotmod'
$N_T832    = 'zz_hitzone_t832.wotmod'
$N_NOSTYLE = 'hitzone.nostyle_1.1.0.wotmod'
$NOSTYLE_PYC = 'res/scripts/client/gui/mods/mod_hitzone_nostyle.pyc'
$SKINPFX = 'res/vehicles/tv.protanki.skinner/'
$GH_REPO  = 'Anno2003-TM/Mods-WOT-Anno'
$GH_ASSET = 'Anno_Mods_WoT.zip'
$VERF     = Join-Path $DATA 'version.txt'
# T-832 = T32-Reskin mit gleicher Texturaufteilung: Ziel <- Quelle
$T832_MAP = [ordered]@{
  'res/vehicles/tv.protanki.skinner/american/A158_T832/T832_hull_01_AM.dds'   = 'res/vehicles/tv.protanki.skinner/american/A12_T32/T32_hull_01_AM.dds'
  'res/vehicles/tv.protanki.skinner/american/A158_T832/T832_turret_01_AM.dds' = 'res/vehicles/tv.protanki.skinner/american/A12_T32/T32_turret_02_AM.dds'
}

try { Set-Content -LiteralPath $LOGF -Value ("Anno-Mods-Installer " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding UTF8 } catch {}
function Say([string]$t, [string]$c = 'Gray') {
  Write-Host $t -ForegroundColor $c
  try { Add-Content -LiteralPath $LOGF -Value $t -Encoding UTF8 } catch {}
}
function Ok([string]$t)   { Say ("  OK      " + $t) 'Green' }
function Warn([string]$t) { Say ("  ACHTUNG " + $t) 'Yellow' }
function Bad([string]$t)  { Say ("  FEHLER  " + $t) 'Red' }
function Done([int]$code) {
  if (-not $KeinPause) { Write-Host ''; Read-Host 'Enter zum Schliessen' | Out-Null }
  exit $code
}

# ---------- kleiner ZIP-Schreiber: unkomprimiert (Methode 0), wie WoT es fuer .wotmod braucht ----------
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
public static class HzZip {
  static uint[] table;
  static uint Crc(byte[] d) {
    if (table == null) {
      table = new uint[256];
      for (uint i = 0; i < 256; i++) {
        uint c = i;
        for (int k = 0; k < 8; k++) c = ((c & 1) != 0) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
        table[i] = c;
      }
    }
    uint r = 0xFFFFFFFFu;
    for (int i = 0; i < d.Length; i++) r = table[(r ^ d[i]) & 0xFF] ^ (r >> 8);
    return r ^ 0xFFFFFFFFu;
  }
  public static void Write(string path, string[] names, byte[][] data) {
    List<string> all = new List<string>();
    List<byte[]> dat = new List<byte[]>();
    HashSet<string> dirs = new HashSet<string>();
    for (int i = 0; i < names.Length; i++) {
      string n = names[i].Replace('\\', '/');
      string[] p = n.Split('/');
      string acc = "";
      for (int j = 0; j < p.Length - 1; j++) {
        acc += p[j] + "/";
        if (dirs.Add(acc)) { all.Add(acc); dat.Add(new byte[0]); }
      }
      all.Add(n); dat.Add(data[i]);
    }
    ushort dtime = 0;
    ushort ddate = (ushort)(((2026 - 1980) << 9) | (1 << 5) | 1);
    List<long> offs = new List<long>();
    List<uint> crcs = new List<uint>();
    using (FileStream fs = new FileStream(path, FileMode.Create, FileAccess.Write))
    using (BinaryWriter w = new BinaryWriter(fs)) {
      for (int i = 0; i < all.Count; i++) {
        byte[] nb = Encoding.UTF8.GetBytes(all[i]);
        byte[] d = dat[i];
        uint crc = Crc(d);
        offs.Add(fs.Position); crcs.Add(crc);
        w.Write((uint)0x04034b50); w.Write((ushort)10); w.Write((ushort)0); w.Write((ushort)0);
        w.Write(dtime); w.Write(ddate); w.Write(crc); w.Write((uint)d.Length); w.Write((uint)d.Length);
        w.Write((ushort)nb.Length); w.Write((ushort)0); w.Write(nb); w.Write(d);
      }
      long cd = fs.Position;
      for (int i = 0; i < all.Count; i++) {
        byte[] nb = Encoding.UTF8.GetBytes(all[i]);
        bool isDir = all[i].EndsWith("/");
        w.Write((uint)0x02014b50); w.Write((ushort)20); w.Write((ushort)10); w.Write((ushort)0); w.Write((ushort)0);
        w.Write(dtime); w.Write(ddate); w.Write(crcs[i]); w.Write((uint)dat[i].Length); w.Write((uint)dat[i].Length);
        w.Write((ushort)nb.Length); w.Write((ushort)0); w.Write((ushort)0); w.Write((ushort)0); w.Write((ushort)0);
        w.Write((uint)(isDir ? 0x10 : 0)); w.Write((uint)offs[i]); w.Write(nb);
      }
      long cdEnd = fs.Position;
      w.Write((uint)0x06054b50); w.Write((ushort)0); w.Write((ushort)0);
      w.Write((ushort)all.Count); w.Write((ushort)all.Count);
      w.Write((uint)(cdEnd - cd)); w.Write((uint)cd); w.Write((ushort)0);
    }
  }
}
'@

# ---------- Hilfsfunktionen ----------
function Read-Settings {
  $h = @{}
  if (Test-Path -LiteralPath $SETF) {
    foreach ($l in Get-Content -LiteralPath $SETF) { if ($l -match '^\s*([^=#]+?)\s*=\s*(.*)$') { $h[$Matches[1]] = $Matches[2].Trim() } }
  }
  return $h
}
function Save-Settings($h) {
  try { $h.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" } | Set-Content -LiteralPath $SETF -Encoding UTF8 } catch {}
}
function Is-WotDir([string]$p) {
  if (-not $p) { return $false }
  return (Test-Path -LiteralPath (Join-Path $p 'paths.xml')) -and (Test-Path -LiteralPath (Join-Path $p 'mods'))
}
function Find-WotDirs {
  $c = New-Object System.Collections.Generic.List[string]
  # 1) Installer liegt im WoT-Ordner (oder einem Unterordner davon)
  foreach ($p in @($ROOT, (Split-Path -Parent $ROOT))) { if ($p) { $c.Add($p) } }
  # 2) Wargaming Game Center merkt sich die Spielordner
  foreach ($f in @("$env:APPDATA\Wargaming.net\GameCenter\preferences.xml", "$env:ProgramData\Wargaming.net\GameCenter\preferences.xml")) {
    if (Test-Path -LiteralPath $f) {
      try { foreach ($m in [regex]::Matches((Get-Content -LiteralPath $f -Raw), '<working_dir>\s*([^<]+?)\s*</working_dir>')) { $c.Add($m.Groups[1].Value) } } catch {}
    }
  }
  # 3) uebliche Orte auf allen Laufwerken
  $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | ForEach-Object { $_.Root }
  foreach ($d in $drives) {
    foreach ($sub in @('Games\World_of_Tanks_EU', 'World_of_Tanks_EU', 'Wargaming.net\World_of_Tanks_EU', 'Program Files (x86)\World_of_Tanks_EU',
                       'Program Files\World_of_Tanks_EU', 'World of tanks\World_of_Tanks_EU', 'Spiele\World_of_Tanks_EU', 'Games\World_of_Tanks',
                       'World_of_Tanks', 'Games\World_of_Tanks_NA', 'World_of_Tanks_NA')) {
      $c.Add((Join-Path $d $sub))
    }
  }
  $seen = @{}; $out = @()
  foreach ($p in $c) {
    try { $full = [IO.Path]::GetFullPath($p.Trim('"').TrimEnd('\')) } catch { continue }
    if ($seen.ContainsKey($full.ToLower())) { continue }
    $seen[$full.ToLower()] = 1
    if (Is-WotDir $full) { $out += $full }
  }
  return ,$out
}
function Get-ModsDir([string]$wot) {
  # Den Ordner nehmen, den das Spiel wirklich laedt (paths.xml), nicht die hoechste Versionsnummer:
  # vor einem Patch liegt oft schon ein Ordner fuer die naechste Version da.
  try {
    $txt = Get-Content -LiteralPath (Join-Path $wot 'paths.xml') -Raw
    $m = [regex]::Match($txt, '<Path[^>]*\*\.wotmod[^>]*>\s*\./mods/([^<\s]+)\s*</Path>')
    if ($m.Success) {
      $d = Join-Path (Join-Path $wot 'mods') ($m.Groups[1].Value -replace '/', '\')
      if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
      return $d
    }
  } catch {}
  $v = Get-ChildItem -LiteralPath (Join-Path $wot 'mods') -Directory | Where-Object { $_.Name -match '^\d+(\.\d+)+$' } |
       Sort-Object { [version]$_.Name } | Select-Object -Last 1
  if ($v) { return $v.FullName }
  return $null
}
function Open-Zip([string]$p) { try { return [IO.Compression.ZipFile]::OpenRead($p) } catch { return $null } }
function Entry-Bytes($e) {
  $s = $e.Open(); $ms = New-Object IO.MemoryStream
  try { $s.CopyTo($ms) } finally { $s.Close() }
  return ,$ms.ToArray()
}
function Same-File([string]$a, [string]$b) {
  if (-not (Test-Path -LiteralPath $a) -or -not (Test-Path -LiteralPath $b)) { return $false }
  $x = Get-Item -LiteralPath $a; $y = Get-Item -LiteralPath $b
  return ($x.Length -eq $y.Length) -and ([math]::Abs(($x.LastWriteTimeUtc - $y.LastWriteTimeUtc).TotalSeconds) -lt 3)
}
function Rel([string]$p) { if ($p.StartsWith($script:WOTDIR)) { return $p.Substring($script:WOTDIR.Length).TrimStart('\') } return $p }

# Emets-Pakete (american_dds / *_scrpts) nach T32-Texturen und evtl. schon vorhandenem T-832 durchsuchen
function Get-EmetsInfo([string]$sk) {
  $r = @{ T32 = @{}; HasT832 = $false; Dds = $null }
  $files = @(Get-ChildItem -LiteralPath $sk -Filter '*.wotmod' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike 'zz_hitzone*' })
  foreach ($f in $files) {
    $z = Open-Zip $f.FullName
    if (-not $z) { continue }
    try {
      foreach ($e in $z.Entries) {
        $n = $e.FullName
        if ($n -like '*/american/A158_T832/*' -and $n -notlike '*/') { $r.HasT832 = $true }
        foreach ($src in $T832_MAP.Values) { if ($n -eq $src -and -not $r.T32.ContainsKey($src)) { $r.T32[$src] = $f.FullName } }
      }
    } finally { $z.Dispose() }
  }
  return $r
}

function Build-T832([string]$sk, $info) {
  $out = Join-Path $sk $N_T832
  $names = New-Object System.Collections.Generic.List[string]
  $datas = New-Object System.Collections.Generic.List[byte[]]
  foreach ($k in $T832_MAP.Keys) {
    $src = $T832_MAP[$k]
    $z = Open-Zip $info.T32[$src]
    try {
      $e = $null
      foreach ($x in $z.Entries) { if ($x.FullName -eq $src) { $e = $x; break } }
      $b = Entry-Bytes $e
      $names.Add($k); $datas.Add([byte[]]$b)
    } finally { $z.Dispose() }
  }
  $base = (Get-Item -LiteralPath $SRC_T832).FullName
  foreach ($f in Get-ChildItem -LiteralPath $base -Recurse -File) {
    $names.Add(($f.FullName.Substring($base.Length + 1) -replace '\\', '/'))
    $datas.Add([IO.File]::ReadAllBytes($f.FullName))
  }
  $tmp = $out + '.neu'
  [HzZip]::Write($tmp, $names.ToArray(), $datas.ToArray())
  # Gegenprobe: laesst sich die neue Datei lesen und ist alles drin?
  $z = Open-Zip $tmp
  if (-not $z) { throw 'neu gebaute T-832-Datei ist kaputt' }
  $cnt = @($z.Entries | Where-Object { $_.FullName -notlike '*/' }).Count
  $z.Dispose()
  if ($cnt -ne $names.Count) { throw "neu gebaute T-832-Datei unvollstaendig ($cnt von $($names.Count))" }
  Move-Item -LiteralPath $tmp -Destination $out -Force
  return $out
}

# Alle Hitzone-Pakete im geladenen Mod-Ordner ausser den richtigen Zielen finden.
# Eigene Dateien (friends / t832 / nostyle) -> einfach loeschen (der Installer hat die Originale),
# fremde Pakete (z.B. zz_hitzone_test oder andere mit dem nostyle-Skript) -> nach hitzone_backup verschieben.
function Find-Extra([string]$mods, [string[]]$targets) {
  $t = @{}; foreach ($x in $targets) { $t[$x.ToLower()] = 1 }
  $out = @()
  foreach ($f in Get-ChildItem -LiteralPath $mods -Recurse -File -Filter '*.wotmod' -ErrorAction SilentlyContinue) {
    if ($t.ContainsKey($f.FullName.ToLower())) { continue }
    $n = $f.Name.ToLower()
    $own = ($n -like 'zz_hitzone_friends*') -or ($n -like 'zz_hitzone_t832*') -or ($n -like 'hitzone.nostyle*')
    $hit = $own -or ($n -like 'zz_hitzone*')
    if (-not $hit) {
      $z = Open-Zip $f.FullName
      if ($z) { try { foreach ($e in $z.Entries) { if ($e.FullName -eq $NOSTYLE_PYC) { $hit = $true; break } } } finally { $z.Dispose() } }
    }
    if ($hit) { $out += [pscustomobject]@{ Path = $f.FullName; Own = $own } }
  }
  return ,$out
}

# Dateien, die in einem unserer Pakete UND in einem anderen Paket stecken (fuehrt zu Konflikten im Log)
function Find-Conflicts([string]$mods, [string[]]$ours) {
  $mine = @{}
  foreach ($p in $ours) {
    if (-not (Test-Path -LiteralPath $p)) { continue }
    $z = Open-Zip $p; if (-not $z) { continue }
    try { foreach ($e in $z.Entries) { if ($e.FullName -notlike '*/') { $mine[$e.FullName.ToLower()] = 1 } } } finally { $z.Dispose() }
  }
  $o = @{}; foreach ($x in $ours) { $o[$x.ToLower()] = 1 }
  $hits = @{}; $n = 0
  foreach ($f in Get-ChildItem -LiteralPath $mods -Recurse -File -Filter '*.wotmod' -ErrorAction SilentlyContinue) {
    if ($o.ContainsKey($f.FullName.ToLower())) { continue }
    $z = Open-Zip $f.FullName; if (-not $z) { continue }
    try {
      foreach ($e in $z.Entries) {
        $k = $e.FullName.ToLower()
        if ($k -like '*/' ) { continue }
        if ($mine.ContainsKey($k)) {
          $n++
          $parts = $e.FullName.Split('/')
          if ($parts.Length -gt 5) { $hits[$parts[4]] = $f.Name }
        }
      }
    } finally { $z.Dispose() }
  }
  return @{ Count = $n; Tanks = $hits }
}

function Wait-WotClosed {
  while (Get-Process -Name 'WorldOfTanks' -ErrorAction SilentlyContinue) {
    Warn 'World of Tanks laeuft noch. Bitte WoT schliessen (Hangar beenden), dann Enter druecken.'
    Read-Host | Out-Null
  }
}

# ---------- Start ----------
Write-Host ''
Write-Host '  Anno Mods - Installer' -ForegroundColor Cyan
Write-Host '  Hitzone-Skins Erweiterung (Stufe IV-XI) + Anpassen-Suche' -ForegroundColor Cyan
Write-Host '  Hitzone-Daten: WOTInspector / Armor Inspector (reven86)' -ForegroundColor DarkGray
Write-Host ''

if (-not (Test-Path -LiteralPath $SRC_FRIENDS)) {
  Bad "zz_hitzone_friends.wotmod fehlt im Ordner 'dateien'. Bitte die Zip zuerst komplett entpacken (Rechtsklick > Alle extrahieren) und dann Anno_Mods_installieren.bat im entpackten Ordner starten."
  Done 1
}

$set = Read-Settings

# WoT-Ordner bestimmen
$script:WOTDIR = $null
if ($Wot) { if (Is-WotDir $Wot) { $script:WOTDIR = [IO.Path]::GetFullPath($Wot.TrimEnd('\')) } else { Bad "Kein WoT-Ordner: $Wot"; Done 1 } }
elseif ($set['wot'] -and (Is-WotDir $set['wot'])) { $script:WOTDIR = $set['wot'] }
else {
  $found = Find-WotDirs
  if ($found.Count -eq 1) { $script:WOTDIR = $found[0] }
  elseif ($found.Count -gt 1) {
    Say 'Mehrere WoT-Ordner gefunden:'
    for ($i = 0; $i -lt $found.Count; $i++) { Say ("  {0} = {1}" -f ($i + 1), $found[$i]) }
    $a = Read-Host 'Nummer waehlen'
    if ($a -match '^\d+$' -and [int]$a -ge 1 -and [int]$a -le $found.Count) { $script:WOTDIR = $found[[int]$a - 1] }
  }
  while (-not $script:WOTDIR) {
    $a = (Read-Host 'WoT-Ordner eingeben (der Ordner mit WorldOfTanks.exe, z.B. C:\Games\World_of_Tanks_EU)').Trim().Trim('"')
    if (Is-WotDir $a) { $script:WOTDIR = [IO.Path]::GetFullPath($a.TrimEnd('\')) } else { Warn 'Dort gibt es keine paths.xml / keinen mods-Ordner. Nochmal.' }
  }
}
$set['wot'] = $script:WOTDIR; Save-Settings $set

$MODS = Get-ModsDir $script:WOTDIR
if (-not $MODS) { Bad 'Kein Mod-Ordner gefunden (mods\<Version>). Ist WoT richtig installiert?'; Done 1 }
$SK = Join-Path $MODS 'skinner'
$T_FRIENDS = Join-Path $SK $N_FRIENDS
$T_T832    = Join-Path $SK $N_T832
$T_NOSTYLE = Join-Path $MODS $N_NOSTYLE
Say ("WoT-Ordner:  " + $script:WOTDIR)
Say ("Mod-Ordner:  " + (Rel $MODS) + "   (laut paths.xml, den laedt das Spiel)")
Write-Host ''

# ---------- Anpassen-Suche ----------
function Find-Anno([string]$mods) {
  return @(Get-ChildItem -LiteralPath $mods -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'anno.c11n_search_*.wotmod' -or $_.Name -like 'tobi.c11n_search_*.wotmod' })
}
function Has-Gameface([string]$mods) {
  return [bool](Get-ChildItem -LiteralPath $mods -Recurse -File -Filter 'net.openwg.gameface_*.wotmod' -ErrorAction SilentlyContinue | Select-Object -First 1)
}

# ---------- Update ueber GitHub ----------
function Local-Version {
  if (Test-Path -LiteralPath $VERF) { return ('' + (Get-Content -LiteralPath $VERF -TotalCount 1)).Trim() }
  return ''
}
function Get-LatestRelease {
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    return Invoke-RestMethod -Uri ('https://api.github.com/repos/' + $GH_REPO + '/releases/latest') -Headers @{ 'User-Agent' = 'hitzone-installer' } -TimeoutSec 10
  } catch { return $null }
}
function Is-Newer($rel) {
  if (-not $rel) { return $false }
  $cur = Local-Version
  $new = ('' + $rel.tag_name).TrimStart('v')
  return (-not $cur) -or ([string]::CompareOrdinal($new, $cur) -gt 0)
}
function Do-Update {
  $rel = Get-LatestRelease
  if (-not $rel) { Bad 'GitHub nicht erreichbar (Internet?). Spaeter nochmal versuchen.'; Done 1 }
  $cur = Local-Version
  $new = ('' + $rel.tag_name).TrimStart('v')
  Say ('Deine Version:   ' + $(if ($cur) { $cur } else { '(alt, ohne Versionsnummer)' }))
  Say ('Neueste Version: ' + $new)
  if (-not (Is-Newer $rel)) { Ok 'Du hast schon die neueste Version.'; Done 0 }
  $asset = @($rel.assets | Where-Object { $_.name -eq $GH_ASSET }) | Select-Object -First 1
  if (-not $asset) { Bad 'Im neuesten Release fehlt die Zip. Spaeter nochmal versuchen.'; Done 1 }
  Wait-WotClosed
  $tmpz = Join-Path $env:TEMP 'hitzone_update.zip'
  $tmpd = Join-Path $env:TEMP 'hitzone_update_neu'
  try {
    Say ('Lade ' + [math]::Round($asset.size / 1MB) + ' MB herunter ... (je nach Leitung ein paar Minuten, Fenster offen lassen)')
    $wc = New-Object Net.WebClient
    $wc.Headers.Add('User-Agent', 'hitzone-installer')
    $wc.DownloadFile($asset.browser_download_url, $tmpz)
    if ((Get-Item -LiteralPath $tmpz).Length -ne $asset.size) { throw 'Download unvollstaendig' }
    if (Test-Path -LiteralPath $tmpd) { Remove-Item -LiteralPath $tmpd -Recurse -Force }
    [IO.Compression.ZipFile]::ExtractToDirectory($tmpz, $tmpd)
    if (-not (Test-Path -LiteralPath (Join-Path $tmpd 'dateien\installer.ps1'))) { throw 'Zip hat nicht den erwarteten Inhalt' }
    Copy-Item -Path (Join-Path $tmpd '*') -Destination $ROOT -Recurse -Force
  } catch {
    Bad ('Update fehlgeschlagen: ' + $_.Exception.Message)
    Done 1
  } finally {
    Remove-Item -LiteralPath $tmpz -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmpd -Recurse -Force -ErrorAction SilentlyContinue
  }
  Ok ('Installer-Ordner auf Version ' + $new + ' gebracht. Jetzt wird installiert ...')
  Write-Host ''
  $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $DATA 'installer.ps1'), '-Aktion', 'installieren', '-Wot', $script:WOTDIR)
  if ($NoStyle) { $args2 += @('-NoStyle', $NoStyle) }
  if ($KeinPause) { $args2 += '-KeinPause' }
  & powershell @args2
  exit $LASTEXITCODE
}

if (-not $Aktion) {
  $relInfo = Get-LatestRelease
  if (Is-Newer $relInfo) {
    Say ('  NEU: Version ' + ('' + $relInfo.tag_name).TrimStart('v') + ' ist auf GitHub verfuegbar  ->  4 waehlen') 'Cyan'
    Write-Host ''
  }
  Write-Host '  1 = Installieren / Reparieren   (nach Aslain oder WoT-Patch einfach wieder 1)'
  Write-Host '  2 = Nur pruefen (aendert nichts)'
  Write-Host '  3 = Entfernen'
  Write-Host '  4 = Auf neue Version pruefen und aktualisieren (GitHub)'
  Write-Host '  0 = Beenden'
  $a = Read-Host 'Auswahl [1]'
  switch ($a.Trim()) { '' { $Aktion = 'installieren' } '1' { $Aktion = 'installieren' } '2' { $Aktion = 'pruefen' } '3' { $Aktion = 'entfernen' } '4' { $Aktion = 'update' } default { exit 0 } }
}
$Aktion = $Aktion.ToLower()
Say ("Aktion: " + $Aktion)
$lv = Local-Version
if ($lv) { Say ("Version:     " + $lv) }
if ($Aktion -eq 'update') { Do-Update }

# Skinner / Emets-Hitzone-Skins vorhanden?
$skinnerMod = @(Get-ChildItem -LiteralPath $MODS -Recurse -File -Filter 'tv.protanki.skinner*.wotmod' -ErrorAction SilentlyContinue)
$emets = @(Get-ChildItem -LiteralPath $SK -Filter '*_scrpts.wotmod' -File -ErrorAction SilentlyContinue)

# ================= ENTFERNEN =================
if ($Aktion -eq 'entfernen') {
  Wait-WotClosed
  $n = 0
  foreach ($f in (Find-Anno $MODS)) { Remove-Item -LiteralPath $f.FullName -Force; Ok ("entfernt: " + (Rel $f.FullName)); $n++ }
  foreach ($p in @($T_FRIENDS, $T_T832, $T_NOSTYLE)) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force; Ok ("entfernt: " + (Rel $p)); $n++ } }
  foreach ($x in (Find-Extra $MODS @())) { if ($x.Own) { Remove-Item -LiteralPath $x.Path -Force; Ok ("entfernt: " + (Rel $x.Path)); $n++ } }
  if ($n -eq 0) { Say 'Nichts zu entfernen.' }
  Say 'Die Emets-Hitzone-Skins selbst bleiben unveraendert. Die Anpassen-Suche ist ebenfalls entfernt.'
  Done 0
}

# ================= PRUEFEN =================
if ($Aktion -eq 'pruefen') {
  $prob = 0
  if (Get-Process -Name 'WorldOfTanks' -ErrorAction SilentlyContinue) { Warn 'WoT laeuft gerade (zum Installieren/Reparieren vorher schliessen).' }
  if ($skinnerMod.Count -gt 0) { Ok ("PRO Tanki Skinner: " + $skinnerMod[0].Name) } else { Bad 'PRO Tanki Skinner (tv.protanki.skinner) nicht im Mod-Ordner'; $prob++ }
  if ($emets.Count -gt 0) { Ok ("Emets-Hitzone-Skins: " + $emets.Count + " Pakete in " + (Rel $SK)) } else { Bad ("keine Emets-Hitzone-Skins (*_scrpts.wotmod) in " + (Rel $SK)); $prob++ }
  if (Same-File $SRC_FRIENDS $T_FRIENDS) { Ok ("installiert: " + (Rel $T_FRIENDS)) }
  elseif (Test-Path -LiteralPath $T_FRIENDS) { Warn ((Rel $T_FRIENDS) + " ist eine andere/alte Version"); $prob++ }
  else { Bad ("fehlt: " + (Rel $T_FRIENDS)); $prob++ }
  if (Test-Path -LiteralPath $SK) {
    $info = Get-EmetsInfo $SK
    if ($info.HasT832) { Ok 'T-832: dein Emets-Paket hat schon einen eigenen T-832-Skin' ; if (Test-Path -LiteralPath $T_T832) { Warn ((Rel $T_T832) + " ist ueberfluessig (Reparieren entfernt es)"); $prob++ } }
    elseif (Test-Path -LiteralPath $T_T832) {
      $z = Open-Zip $T_T832
      if ($z) { $c = @($z.Entries | Where-Object { $_.FullName -like '*.dds' }).Count; $z.Dispose(); if ($c -eq 2) { Ok ("installiert: " + (Rel $T_T832)) } else { Warn ((Rel $T_T832) + " unvollstaendig"); $prob++ } }
      else { Bad ((Rel $T_T832) + " kaputt"); $prob++ }
    }
    elseif ($info.T32.Count -eq $T832_MAP.Count) { Bad ("fehlt: " + (Rel $T_T832)); $prob++ }
    else { Warn 'T-832: T32-Texturen nicht in deinem Emets-Paket gefunden, T-832 nicht moeglich' }
  }
  if (Test-Path -LiteralPath $T_NOSTYLE) { Ok ("installiert (optional): " + (Rel $T_NOSTYLE)) } else { Say ("  info    nicht installiert (optional): " + $N_NOSTYLE) }
  $extra = Find-Extra $MODS @($T_FRIENDS, $T_T832, $T_NOSTYLE)
  foreach ($x in $extra) { Warn ("doppeltes Hitzone-Paket: " + (Rel $x.Path)); $prob++ }
  $cf = Find-Conflicts $MODS @($T_FRIENDS, $T_T832)
  if ($cf.Count -gt 0) {
    Warn ("" + $cf.Count + " Dateien gibt es doppelt (in einem anderen Paket und hier). Betroffene Panzer: " + (($cf.Tanks.Keys | Sort-Object | Select-Object -First 15) -join ', '))
    Say  '          Meist hat Emets inzwischen selbst Skins fuer diese Panzer - dann bitte nach einer neuen Version der Erweiterung fragen.'
  } else { Ok 'keine doppelten Dateien (keine Konflikte)' }
  $an = @(Find-Anno $MODS)
  if ($an.Count -eq 0) { Say ("  info    Anpassen-Suche nicht installiert (optional)") }
  elseif ($an.Count -gt 1) { Warn ("Anpassen-Suche mehrfach installiert: " + (($an | ForEach-Object { $_.Name }) -join ', ')); $prob++ }
  elseif ($SRC_ANNO -and $an[0].Name -ne $SRC_ANNO.Name) { Warn ("Anpassen-Suche: " + $an[0].Name + " ist eine andere Version als " + $SRC_ANNO.Name); $prob++ }
  else {
    Ok ("installiert: " + (Rel $an[0].FullName))
    if (-not (Has-Gameface $MODS)) { Warn 'Anpassen-Suche braucht net.openwg.gameface (Aslain-Modpack), das fehlt'; $prob++ }
  }
  Write-Host ''
  if ($prob -eq 0) { Say 'Alles in Ordnung.' 'Green' } else { Say ("" + $prob + " Problem(e) gefunden. Installer nochmal starten und 1 = Installieren / Reparieren waehlen.") 'Yellow' }
  Done 0
}

# ================= INSTALLIEREN / REPARIEREN =================
if ($Aktion -ne 'installieren') { Bad "Unbekannte Aktion: $Aktion"; Done 1 }
$skipHz = $false
if ($skinnerMod.Count -eq 0 -or $emets.Count -eq 0) {
  Warn ("Die Hitzone-Skins von Emets (PRO Tanki Skinner) sind in " + (Rel $MODS) + " nicht installiert.")
  Say '          Die Hitzone-Erweiterung braucht sie und wird diesmal uebersprungen. Erst im Aslain-Installer'
  Say '          "Hitzone-Skins / Skinner" fuer diese WoT-Version installieren, dann diesen Installer nochmal starten.'
  $skipHz = $true
}
Wait-WotClosed

# Anpassen-Suche ja/nein (wird gemerkt)
$ap = $Anpassen.ToLower()
if ($SRC_ANNO -and $ap -notin @('ja', 'nein', 'j', 'n')) {
  $def = if ($set['anpassen'] -eq 'nein') { 'n' } else { 'j' }
  Write-Host ''
  Write-Host 'Anpassen-Suche: Suchfeld in der Garage unter "Anpassen" (2D-Stile, Tarnungen, Embleme usw. nach Namen filtern).'
  $a = (Read-Host ("Anpassen-Suche installieren? j/n [" + $def + "]")).Trim().ToLower()
  if (-not $a) { $a = $def }
  $ap = $a
}
$useAnno = [bool]$SRC_ANNO -and $ap.StartsWith('j')
if ($SRC_ANNO) { $set['anpassen'] = if ($useAnno) { 'ja' } else { 'nein' }; Save-Settings $set }
if ($skipHz -and -not $useAnno) { Bad 'Nichts zu installieren.'; Done 1 }

# nostyle ja/nein (wird gemerkt)
$ns = $NoStyle.ToLower()
if ($skipHz) { $ns = 'nein' }
elseif ($ns -notin @('ja', 'nein', 'j', 'n')) {
  $def = if ($set['nostyle'] -eq 'nein') { 'n' } else { 'j' }
  Write-Host ''
  Write-Host 'Optional: Tarnung/Lackierung eines GEGNERS ausblenden, solange du ihn anvisierst, damit die Zonen nicht verdeckt werden.'
  Write-Host '(3D-Stile werden bei Gegnern ganz ausgeblendet. Eigene Panzer und Verbuendete bleiben immer unveraendert.)'
  $a = (Read-Host ("Ausblenden? j/n [" + $def + "]")).Trim().ToLower()
  if (-not $a) { $a = $def }
  $ns = $a
}
$useNostyle = $ns.StartsWith('j')
if (-not $skipHz) { $set['nostyle'] = if ($useNostyle) { 'ja' } else { 'nein' }; Save-Settings $set }
Write-Host ''

$fehler = 0
try {
  # 0) Anpassen-Suche
  foreach ($f in (Find-Anno $MODS)) {
    if ($useAnno -and $f.Name -eq $SRC_ANNO.Name) { continue }
    Remove-Item -LiteralPath $f.FullName -Force; Ok ("alte/abgewaehlte Anpassen-Suche entfernt: " + $f.Name)
  }
  if ($useAnno) {
    $tA = Join-Path $MODS $SRC_ANNO.Name
    if (Same-File $SRC_ANNO.FullName $tA) { Ok ("schon aktuell: " + (Rel $tA)) }
    else { Copy-Item -LiteralPath $SRC_ANNO.FullName -Destination $tA -Force; Ok ("installiert: " + (Rel $tA)) }
    if (-not (Has-Gameface $MODS)) { Warn 'Die Anpassen-Suche braucht net.openwg.gameface (im Aslain-Modpack dabei), das fehlt im Mod-Ordner.' }
  }
  if (-not $skipHz) {
  # 1) doppelte / falsch liegende Hitzone-Pakete wegraeumen (sonst Konflikte im Spiel)
  $targets = @($T_FRIENDS, $T_T832); if ($useNostyle) { $targets += $T_NOSTYLE }
  $bak = Join-Path (Join-Path $script:WOTDIR 'hitzone_backup') (Get-Date -Format 'yyyy-MM-dd_HHmmss')
  foreach ($x in (Find-Extra $MODS $targets)) {
    if ($x.Own) { Remove-Item -LiteralPath $x.Path -Force; Ok ("doppelte Kopie entfernt: " + (Rel $x.Path)) }
    else {
      $dst = Join-Path $bak (Rel $x.Path)
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
      Move-Item -LiteralPath $x.Path -Destination $dst -Force
      Ok ("anderes Hitzone-Paket verschoben: " + (Rel $x.Path) + " -> " + (Rel $dst))
    }
  }
  if (-not $useNostyle -and (Test-Path -LiteralPath $T_NOSTYLE)) { Remove-Item -LiteralPath $T_NOSTYLE -Force; Ok ("entfernt (abgewaehlt): " + $N_NOSTYLE) }

  # 2) Hauptpaket
  if (Same-File $SRC_FRIENDS $T_FRIENDS) { Ok ("schon aktuell: " + (Rel $T_FRIENDS)) }
  else {
    Say ("  kopiere " + $N_FRIENDS + " (ca. 300 MB) ...")
    Copy-Item -LiteralPath $SRC_FRIENDS -Destination ($T_FRIENDS + '.neu') -Force
    Move-Item -LiteralPath ($T_FRIENDS + '.neu') -Destination $T_FRIENDS -Force
    Ok ("installiert: " + (Rel $T_FRIENDS))
  }

  # 3) T-832 aus dem eigenen Emets-Paket
  $info = Get-EmetsInfo $SK
  if ($info.HasT832) {
    if (Test-Path -LiteralPath $T_T832) { Remove-Item -LiteralPath $T_T832 -Force }
    Ok 'T-832: dein Emets-Paket hat schon einen eigenen T-832-Skin, nichts zu tun'
  } elseif ($info.T32.Count -ne $T832_MAP.Count) {
    Warn 'T-832 uebersprungen: T32-Texturen in deinem Emets-Paket nicht gefunden (american_dds.wotmod)'
  } else {
    $o = Build-T832 $SK $info
    Ok ("T-832-Skin aus deinem T32-Skin gebaut: " + (Rel $o))
  }

  # 4) optional nostyle
  if ($useNostyle) {
    if (Same-File $SRC_NOSTYLE $T_NOSTYLE) { Ok ("schon aktuell: " + (Rel $T_NOSTYLE)) }
    else { Copy-Item -LiteralPath $SRC_NOSTYLE -Destination $T_NOSTYLE -Force; Ok ("installiert: " + (Rel $T_NOSTYLE)) }
  }

  # 5) Kontrolle auf doppelte Dateien
  $cf = Find-Conflicts $MODS @($T_FRIENDS, $T_T832)
  if ($cf.Count -gt 0) { Warn ("" + $cf.Count + " Dateien gibt es auch in einem anderen Paket (Panzer: " + (($cf.Tanks.Keys | Sort-Object | Select-Object -First 15) -join ', ') + ")") }
  else { Ok 'keine doppelten Dateien' }
  }
} catch {
  $fehler = 1
  Bad $_.Exception.Message
  if ($_.Exception -is [System.IO.IOException] -or $_.Exception -is [System.UnauthorizedAccessException]) {
    Say '          Datei gesperrt? WoT / Game Center schliessen und nochmal versuchen.'
  }
}

# Verknuepfung auf dem Desktop (einmal fragen)
if ($fehler -eq 0 -and -not $KeinPause -and -not $set['verknuepfung']) {
  $a = (Read-Host 'Verknuepfung "Anno Mods installieren" auf dem Desktop anlegen (fuer nach Aslain/Patch)? j/n [j]').Trim().ToLower()
  if (-not $a -or $a.StartsWith('j')) {
    try {
      $ws = New-Object -ComObject WScript.Shell
      $lnk = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Anno Mods installieren.lnk'))
      $lnk.TargetPath = Join-Path $ROOT 'Anno_Mods_installieren.bat'
      $lnk.WorkingDirectory = $ROOT
      $lnk.Save()
      Ok 'Verknuepfung angelegt'
      $set['verknuepfung'] = 'ja'
    } catch { Warn ('Verknuepfung ging nicht: ' + $_.Exception.Message) }
  } else { $set['verknuepfung'] = 'nein' }
  Save-Settings $set
}

Write-Host ''
if ($fehler -eq 0) {
  Say 'Fertig! WoT starten. Wenn Aslain oder ein WoT-Patch den Mod-Ordner leert: einfach nochmal starten.' 'Green'
  Say 'Diesen Ordner bitte behalten (der Installer holt die Dateien von hier).'
} else {
  Say ('Nicht fertig geworden. Details stehen in ' + $LOGF) 'Yellow'
}
Done $fehler
