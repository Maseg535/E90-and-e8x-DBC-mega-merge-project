param(
    [string]$DbcPath = '.\dbc\bmw_e9x_e8x1_merged.dbc',
    [string]$OutputPath = '.\docs\can_ids_reference.html'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -Path $DbcPath)) {
    throw "DBC not found: $DbcPath"
}

function New-Message([int]$Id, [string]$Name, [int]$Dlc, [string]$Transmitter) {
    [pscustomobject]@{
        Id = $Id
        IdHex = ('0x{0:X3}' -f $Id)
        Name = $Name
        Dlc = $Dlc
        Transmitter = $Transmitter
        Comment = $null
        Signals = New-Object System.Collections.Generic.List[object]
    }
}

function New-Signal {
    param(
        [string]$Name,
        [string]$Mux,
        [int]$StartBit,
        [int]$Length,
        [string]$EndianFlag,
        [string]$SignFlag,
        [string]$Factor,
        [string]$Offset,
        [string]$Minimum,
        [string]$Maximum,
        [string]$Unit,
        [string]$Receivers
    )

    $endian = if ($EndianFlag -eq '1') { 'Intel (little-endian)' } else { 'Motorola (big-endian)' }
    $valueType = if ($SignFlag -eq '+') { 'Unsigned' } else { 'Signed' }

    [pscustomobject]@{
        Name = $Name
        Multiplex = $Mux
        StartBit = $StartBit
        Length = $Length
        Endian = $endian
        EndianFlag = $EndianFlag
        ValueType = $valueType
        Factor = $Factor
        Offset = $Offset
        Minimum = $Minimum
        Maximum = $Maximum
        Unit = $Unit
        Receivers = $Receivers
        Comment = $null
        EnumMap = [ordered]@{}
    }
}

function Escape-Html([string]$Value) {
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode($Value)
}

# Returns human-readable byte/bit position string for a signal
function Get-HumanBitPos($sig) {
    if ($sig.EndianFlag -eq '1') {
        # Intel little-endian
        $startByte = [math]::Floor($sig.StartBit / 8)
        $loBit     = $sig.StartBit % 8
        $endBitAbs = $sig.StartBit + $sig.Length - 1
        $endByte   = [math]::Floor($endBitAbs / 8)
        $hiBit     = $endBitAbs % 8

        if ($startByte -eq $endByte) {
            if ($sig.Length -eq 8)                          { return "B$startByte (full byte)" }
            if ($sig.Length -eq 4 -and $loBit -eq 0)       { return "B${startByte}[3:0] lo-nibble" }
            if ($sig.Length -eq 4 -and $loBit -eq 4)       { return "B${startByte}[7:4] hi-nibble" }
            if ($sig.Length -eq 1)                          { return "B${startByte} bit$loBit" }
            return "B${startByte}[$hiBit`:$loBit]"
        } else {
            $spanBytes = $endByte - $startByte + 1
            return "B${startByte}..B${endByte} ($($sig.Length)b LE, $spanBytes bytes)"
        }
    } else {
        # Motorola big-endian — DBC start bit is MSB position in Motorola notation
        $startByte = [math]::Floor($sig.StartBit / 8)
        if ($sig.Length -eq 8)  { return "B$startByte (full byte, BE)" }
        if ($sig.Length -eq 16) { return "B${startByte}..B$([int]$startByte+1) (16b BE)" }
        return "B${startByte}+ ($($sig.Length)b BE)"
    }
}

# Returns human-readable formula string
function Get-Formula($sig) {
    $fStr = $sig.Factor.Trim()
    $oStr = $sig.Offset.Trim()
    $u    = $sig.Unit.Trim()

    try { $f = [double]$fStr } catch { return '' }
    try { $o = [double]$oStr } catch { return '' }

    if ($f -eq 1 -and $o -eq 0) {
        if ($u) { return "raw ($u)" } else { return 'raw value' }
    }

    $fDisp = if ($f -eq [math]::Truncate($f)) { [int]$f } else { $fStr }
    $oDisp = if ($o -eq [math]::Truncate($o)) { [int]$o } else { $oStr }

    $expr = if ($f -eq 1) { 'raw' } else { "raw &times; $fDisp" }
    if ($o -gt 0)      { $expr += " + $oDisp" }
    elseif ($o -lt 0)  { $expr += " &minus; $([math]::Abs($oDisp))" }
    if ($u)            { $expr += " = <em>$([System.Net.WebUtility]::HtmlEncode($u))</em>" }
    return $expr
}

# Returns HTML hex value row for a message (green=known, red=unknown)
function Get-HexRow($msg, $knownValues) {
    $dlc = $msg.Dlc
    if ($dlc -le 0) { return '' }

    # Collect which bytes have signal coverage
    $coveredBytes = @{}
    for ($i = 0; $i -lt $dlc; $i++) { $coveredBytes[$i] = $false }
    foreach ($sig in $msg.Signals) {
        if ($sig.EndianFlag -eq '1') {
            $startByte = [math]::Floor($sig.StartBit / 8)
            $endByte   = [math]::Floor(($sig.StartBit + $sig.Length - 1) / 8)
            for ($b = [int]$startByte; $b -le [math]::Min([int]$endByte, $dlc - 1); $b++) {
                $coveredBytes[$b] = $true
            }
        } else {
            $b = [math]::Min([int][math]::Floor($sig.StartBit / 8), $dlc - 1)
            $coveredBytes[$b] = $true
        }
    }

    # Get example values if available
    $vals = $null
    $msgIdKey = [int]$msg.Id
    if ($knownValues.ContainsKey($msgIdKey)) {
        $rawVals = $knownValues[$msgIdKey]
        $vals = @($rawVals)  # force array even for single element
    }

    $html = '<div class="hexrow">'
    for ($i = 0; $i -lt $dlc; $i++) {
        $val = if ($null -ne $vals -and $i -lt $vals.Length) { '{0:X2}' -f [int]$vals[$i] } else { '??' }
        $cls = if ($coveredBytes[$i]) { 'hb-known' } else { 'hb-unknown' }
        $html += "<span class='hb $cls'>$val</span>"
    }
    $html += '</div>'
    return $html
}

# Returns HTML byte-map visual for a message
function Get-ByteMap($msg) {
    $dlc = $msg.Dlc
    if ($dlc -le 0) { return '' }

    # Collect signal names per byte slot
    $byteSignals = @{}
    for ($i = 0; $i -lt $dlc; $i++) { $byteSignals[$i] = [System.Collections.Generic.List[string]]::new() }

    foreach ($sig in $msg.Signals) {
        if ($sig.EndianFlag -eq '1') {
            $startByte = [math]::Floor($sig.StartBit / 8)
            $endByte   = [math]::Floor(($sig.StartBit + $sig.Length - 1) / 8)
            for ($b = [int]$startByte; $b -le [math]::Min([int]$endByte, $dlc - 1); $b++) {
                $byteSignals[$b].Add($sig.Name)
            }
        } else {
            $b = [math]::Min([int][math]::Floor($sig.StartBit / 8), $dlc - 1)
            $byteSignals[$b].Add($sig.Name)
        }
    }

    $html = '<div class="bytemap">'
    for ($i = 0; $i -lt $dlc; $i++) {
        $sigs = $byteSignals[$i]
        $isEmpty = ($sigs.Count -eq 0)
        $label = if ($isEmpty) { '&mdash;' } else { [System.Net.WebUtility]::HtmlEncode(($sigs -join ', ')) }
        $cellClass = if ($isEmpty) { 'byte-cell byte-empty' } else { 'byte-cell byte-used' }
        $html += "<div class='$cellClass'><div class='byte-idx'>B$i</div><div class='byte-sigs'>$label</div></div>"
    }
    $html += '</div>'
    return $html
}

$messages = New-Object 'System.Collections.Generic.Dictionary[int,object]'
$currentMessage = $null

$messageRegex       = [regex]'^BO_\s+(\d+)\s+([^:]+):\s+(\d+)\s+(\S+)'
$signalRegex        = [regex]'^SG_\s+(\S+)(?:\s+(M|m\d+))?\s*:\s*(\d+)\|(\d+)@([01])([+-])\s+\(([^,]+),([^)]+)\)\s+\[([^|]+)\|([^\]]+)\]\s+"([^"]*)"\s+(.+)$'
$messageCommentRegex = [regex]'^CM_\s+BO_\s+(\d+)\s+"(.*)";$'
$signalCommentRegex  = [regex]'^CM_\s+SG_\s+(\d+)\s+(\S+)\s+"(.*)";$'
$valRegex           = [regex]'(-?\d+)\s+"([^"]*)"'

foreach ($rawLine in [System.IO.File]::ReadLines((Resolve-Path $DbcPath))) {
    $line = $rawLine.Trim()
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    $messageMatch = $messageRegex.Match($line)
    if ($messageMatch.Success) {
        $id  = [int]$messageMatch.Groups[1].Value
        $msg = New-Message -Id $id -Name $messageMatch.Groups[2].Value.Trim() -Dlc ([int]$messageMatch.Groups[3].Value) -Transmitter $messageMatch.Groups[4].Value.Trim()
        $messages[$id] = $msg
        $currentMessage = $msg
        continue
    }

    $signalMatch = $signalRegex.Match($line)
    if ($signalMatch.Success -and $null -ne $currentMessage) {
        $signal = New-Signal -Name $signalMatch.Groups[1].Value `
            -Mux $signalMatch.Groups[2].Value `
            -StartBit ([int]$signalMatch.Groups[3].Value) `
            -Length ([int]$signalMatch.Groups[4].Value) `
            -EndianFlag $signalMatch.Groups[5].Value `
            -SignFlag $signalMatch.Groups[6].Value `
            -Factor $signalMatch.Groups[7].Value.Trim() `
            -Offset $signalMatch.Groups[8].Value.Trim() `
            -Minimum $signalMatch.Groups[9].Value.Trim() `
            -Maximum $signalMatch.Groups[10].Value.Trim() `
            -Unit $signalMatch.Groups[11].Value `
            -Receivers $signalMatch.Groups[12].Value.Trim()
        [void]$currentMessage.Signals.Add($signal)
        continue
    }

    $commentMatch = $messageCommentRegex.Match($line)
    if ($commentMatch.Success) {
        $id = [int]$commentMatch.Groups[1].Value
        if ($messages.ContainsKey($id)) {
            $messages[$id].Comment = $commentMatch.Groups[2].Value
        }
        continue
    }

    $signalCommentMatch = $signalCommentRegex.Match($line)
    if ($signalCommentMatch.Success) {
        $id         = [int]$signalCommentMatch.Groups[1].Value
        $signalName = $signalCommentMatch.Groups[2].Value
        if ($messages.ContainsKey($id)) {
            $signal = $messages[$id].Signals | Where-Object { $_.Name -eq $signalName } | Select-Object -First 1
            if ($null -ne $signal) {
                $signal.Comment = $signalCommentMatch.Groups[3].Value
            }
        }
        continue
    }

    if ($line.StartsWith('VAL_ ')) {
        $trimmed     = $line.Substring(5).TrimEnd(';')
        $firstSpace  = $trimmed.IndexOf(' ')
        if ($firstSpace -lt 0) { continue }
        $id          = [int]$trimmed.Substring(0, $firstSpace)
        $rest        = $trimmed.Substring($firstSpace + 1)
        $secondSpace = $rest.IndexOf(' ')
        if ($secondSpace -lt 0) { continue }
        $signalName  = $rest.Substring(0, $secondSpace)
        $pairs       = $rest.Substring($secondSpace + 1)
        if ($messages.ContainsKey($id)) {
            $signal = $messages[$id].Signals | Where-Object { $_.Name -eq $signalName } | Select-Object -First 1
            if ($null -ne $signal) {
                foreach ($match in $valRegex.Matches($pairs)) {
                    $signal.EnumMap[$match.Groups[1].Value] = $match.Groups[2].Value
                }
            }
        }
    }
}

$orderedMessages = $messages.Values | Sort-Object Id
$signalCount     = ($orderedMessages | ForEach-Object { $_.Signals.Count } | Measure-Object -Sum).Sum

# Load known example byte values from JSON library (tools/known_values.json)
# Regenerate/update with: python tools/extract_known_values.py
$knownValues = @{}
$knownValuesJsonPath = Join-Path $PSScriptRoot 'known_values.json'
if (Test-Path $knownValuesJsonPath) {
    $kvRaw = Get-Content $knownValuesJsonPath -Raw | ConvertFrom-Json
    foreach ($prop in $kvRaw.PSObject.Properties) {
        if ($prop.Name -eq '_meta') { continue }
        $canId = [int]$prop.Name
        $knownValues[$canId] = @($prop.Value.bytes | ForEach-Object {
            [System.Convert]::ToInt32(($_ -replace '^0[xX]', ''), 16)
        })
    }
} else {
    Write-Warning "known_values.json not found at $knownValuesJsonPath — hex rows will show '??'"
}
$generatedAt     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$sourceName      = Split-Path -Path $DbcPath -Leaf

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<!DOCTYPE html>')
[void]$sb.AppendLine('<html lang="en">')
[void]$sb.AppendLine('<head>')
[void]$sb.AppendLine('<meta charset="utf-8">')
[void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
[void]$sb.AppendLine('<title>BMW CAN IDs Reference</title>')
[void]$sb.AppendLine('<style>')
[void]$sb.AppendLine('body{margin:0;font-family:Segoe UI,Arial,sans-serif;background:#f3f5f7;color:#1d2731;line-height:1.45;overflow-x:hidden;}')
[void]$sb.AppendLine('.page{max-width:1400px;margin:0 auto;padding:32px 20px 64px;}')
[void]$sb.AppendLine('.hero{background:#111827;color:#f9fafb;border-radius:18px;padding:28px 24px;box-shadow:0 18px 40px rgba(17,24,39,.18);}')
[void]$sb.AppendLine('.hero h1{margin:0 0 8px;font-size:34px;}')
[void]$sb.AppendLine('.hero p{margin:0;color:#cbd5e1;}')
[void]$sb.AppendLine('.meta{display:flex;flex-wrap:wrap;gap:12px;margin-top:18px;}')
[void]$sb.AppendLine('.meta span{display:inline-block;background:#1f2937;color:#e5e7eb;padding:10px 12px;border-radius:999px;font-size:14px;}')
[void]$sb.AppendLine('.search-wrap{margin:20px 0 0;}')
[void]$sb.AppendLine('#search{width:100%;padding:12px 16px;font-size:16px;border:2px solid #334155;border-radius:12px;background:#1f2937;color:#f1f5f9;outline:none;box-sizing:border-box;}')
[void]$sb.AppendLine('#search::placeholder{color:#64748b;}')
[void]$sb.AppendLine('#search:focus{border-color:#60a5fa;}')
[void]$sb.AppendLine('.toc{margin:24px 0 30px;background:#ffffff;border-radius:16px;box-shadow:0 10px 24px rgba(15,23,42,.08);overflow:hidden;}')
[void]$sb.AppendLine('.toc summary{padding:14px 20px;font-size:16px;font-weight:600;cursor:pointer;user-select:none;list-style:none;display:flex;align-items:center;gap:8px;}')
[void]$sb.AppendLine('.toc summary::-webkit-details-marker{display:none;}')
[void]$sb.AppendLine('.toc summary::before{content:"\25B6";font-size:11px;color:#64748b;transition:transform .2s;}')
[void]$sb.AppendLine('.toc[open] summary::before{transform:rotate(90deg);}')
[void]$sb.AppendLine('.toc-body{padding:4px 16px 16px;}')
[void]$sb.AppendLine('.toc-list{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:4px 8px;}')
[void]$sb.AppendLine('.toc a{display:block;padding:5px 8px;border-radius:8px;background:#f1f5f9;color:#1f3b5b;text-decoration:none;font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}')
[void]$sb.AppendLine('.toc a:hover{background:#dbeafe;}')
[void]$sb.AppendLine('.message{margin-top:22px;background:#ffffff;border-radius:18px;padding:22px 22px 24px;box-shadow:0 12px 28px rgba(15,23,42,.08);}')
[void]$sb.AppendLine('.message.hidden{display:none;}')
[void]$sb.AppendLine('.message-header{display:flex;flex-wrap:wrap;justify-content:space-between;gap:12px 18px;align-items:flex-start;}')
[void]$sb.AppendLine('.message h2{margin:0;font-size:26px;color:#0f172a;}')
[void]$sb.AppendLine('.message-sub{margin-top:6px;color:#475569;font-size:15px;}')
[void]$sb.AppendLine('.badge-row{display:flex;flex-wrap:wrap;gap:10px;}')
[void]$sb.AppendLine('.badge{background:#eff6ff;border:1px solid #bfdbfe;color:#1d4ed8;padding:8px 10px;border-radius:999px;font-size:13px;font-weight:600;}')
[void]$sb.AppendLine('.comment{margin-top:14px;padding:12px 14px;border-left:4px solid #60a5fa;background:#f8fbff;color:#334155;border-radius:8px;font-size:14px;}')
# Byte map styles
[void]$sb.AppendLine('.bytemap{display:flex;flex-wrap:wrap;gap:6px;margin:16px 0 4px;font-size:12px;}')
[void]$sb.AppendLine('.byte-cell{border-radius:8px;padding:6px 8px;min-width:52px;max-width:160px;text-align:center;flex:1;}')
[void]$sb.AppendLine('.byte-used{background:#f0f9ff;border:1px solid #7dd3fc;}')
[void]$sb.AppendLine('.byte-empty{background:#f8fafc;border:1px dashed #cbd5e1;color:#94a3b8;}')
[void]$sb.AppendLine('.byte-idx{font-weight:700;color:#0369a1;margin-bottom:3px;font-size:11px;}')
[void]$sb.AppendLine('.byte-empty .byte-idx{color:#94a3b8;}')
[void]$sb.AppendLine('.byte-sigs{color:#334155;word-break:break-word;line-height:1.3;}')
[void]$sb.AppendLine('.bytemap-label{font-size:11px;color:#94a3b8;text-transform:uppercase;letter-spacing:.05em;margin:14px 0 2px;}')
[void]$sb.AppendLine('.hexrow{display:flex;flex-wrap:wrap;gap:4px;margin:10px 0 4px;font-family:monospace;font-size:13px;}')
[void]$sb.AppendLine('.hb{padding:3px 7px;border-radius:5px;font-weight:600;letter-spacing:.04em;}')
[void]$sb.AppendLine('.hb-known{background:#dcfce7;color:#15803d;border:1px solid #86efac;}')
[void]$sb.AppendLine('.hb-unknown{background:#fee2e2;color:#b91c1c;border:1px solid #fca5a5;}')
# Table styles
[void]$sb.AppendLine('table{width:100%;border-collapse:collapse;margin-top:18px;font-size:14px;}')
[void]$sb.AppendLine('th,td{padding:10px 8px;border-bottom:1px solid #e5e7eb;vertical-align:top;text-align:left;}')
[void]$sb.AppendLine('th{font-size:12px;text-transform:uppercase;letter-spacing:.04em;color:#64748b;background:#f8fafc;}')
[void]$sb.AppendLine('td code{font-family:Consolas,Monaco,monospace;background:#f8fafc;padding:2px 4px;border-radius:6px;font-size:13px;}')
[void]$sb.AppendLine('.human-pos{font-weight:600;color:#0f172a;font-family:Consolas,Monaco,monospace;font-size:13px;}')
[void]$sb.AppendLine('.dbc-pos{color:#94a3b8;font-size:11px;margin-top:2px;}')
[void]$sb.AppendLine('.formula{color:#065f46;font-size:13px;}')
[void]$sb.AppendLine('.dbc-scale{color:#94a3b8;font-size:11px;margin-top:2px;}')
[void]$sb.AppendLine('.signal-comment{margin-top:6px;color:#475569;font-size:13px;}')
[void]$sb.AppendLine('.enum-list{margin:8px 0 0;padding-left:0;list-style:none;color:#334155;font-size:13px;display:flex;flex-wrap:wrap;gap:4px 10px;}')
[void]$sb.AppendLine('.enum-list li{background:#f0fdf4;border:1px solid #bbf7d0;border-radius:6px;padding:2px 7px;}')
[void]$sb.AppendLine('.enum-hex{color:#065f46;font-weight:700;font-family:Consolas,Monaco,monospace;}')
[void]$sb.AppendLine('.enum-dec{color:#94a3b8;font-size:11px;}')
[void]$sb.AppendLine('.muted{color:#64748b;}')
[void]$sb.AppendLine('@media (max-width:900px){.message-header{flex-direction:column;}}')
[void]$sb.AppendLine('@media (prefers-color-scheme:dark){')
[void]$sb.AppendLine('  body{background:#0f172a;color:#e2e8f0;}')
[void]$sb.AppendLine('  .toc{background:#1e293b;box-shadow:0 10px 24px rgba(0,0,0,.4);}')
[void]$sb.AppendLine('  .toc summary{color:#e2e8f0;}')
[void]$sb.AppendLine('  .toc summary::before{color:#94a3b8;}')
[void]$sb.AppendLine('  .toc a{background:#263450;color:#93c5fd;}')
[void]$sb.AppendLine('  .toc a:hover{background:#1e3a5f;}')
[void]$sb.AppendLine('  .message{background:#1e293b;box-shadow:0 12px 28px rgba(0,0,0,.4);}')
[void]$sb.AppendLine('  .message h2{color:#f1f5f9;}')
[void]$sb.AppendLine('  .message-sub{color:#94a3b8;}')
[void]$sb.AppendLine('  .badge{background:#1e3a5f;border-color:#3b82f6;color:#93c5fd;}')
[void]$sb.AppendLine('  .comment{background:#162032;border-left-color:#3b82f6;color:#cbd5e1;}')
[void]$sb.AppendLine('  .byte-used{background:#162032;border-color:#3b82f6;}')
[void]$sb.AppendLine('  .byte-empty{background:#141e2e;border-color:#334155;color:#64748b;}')
[void]$sb.AppendLine('  .byte-idx{color:#60a5fa;}')
[void]$sb.AppendLine('  .byte-empty .byte-idx{color:#64748b;}')
[void]$sb.AppendLine('  .byte-sigs{color:#cbd5e1;}')
[void]$sb.AppendLine('  .bytemap-label{color:#64748b;}')
[void]$sb.AppendLine('  .hb-known{background:#14532d;color:#86efac;border-color:#166534;}')
[void]$sb.AppendLine('  .hb-unknown{background:#450a0a;color:#fca5a5;border-color:#7f1d1d;}')
[void]$sb.AppendLine('  th,td{border-bottom-color:#334155;}')
[void]$sb.AppendLine('  th{background:#162032;color:#94a3b8;}')
[void]$sb.AppendLine('  td code{background:#162032;color:#e2e8f0;}')
[void]$sb.AppendLine('  .human-pos{color:#f1f5f9;}')
[void]$sb.AppendLine('  .formula{color:#34d399;}')
[void]$sb.AppendLine('  .signal-comment{color:#94a3b8;}')
[void]$sb.AppendLine('  .enum-list li{background:#162e22;border-color:#15803d;}')
[void]$sb.AppendLine('  .enum-hex{color:#34d399;}')
[void]$sb.AppendLine('}')
[void]$sb.AppendLine('@media (max-width:700px){')
[void]$sb.AppendLine('  .page{padding:12px 10px 48px;max-width:100%;}')
[void]$sb.AppendLine('  .hero{border-radius:12px;padding:18px 16px;}')
[void]$sb.AppendLine('  .hero h1{font-size:22px;}')
[void]$sb.AppendLine('  .message{padding:14px 12px 18px;border-radius:12px;overflow:hidden;}')
[void]$sb.AppendLine('  .message h2{font-size:20px;}')
[void]$sb.AppendLine('  .message-sub{font-size:13px;}')
[void]$sb.AppendLine('  .toc-list{grid-template-columns:repeat(2,1fr);}')
[void]$sb.AppendLine('  /* prevent wide content from blowing layout */')
[void]$sb.AppendLine('  .comment,.signal-comment,td code{word-break:break-word;}')
[void]$sb.AppendLine('  /* signal table: 2-column card grid */')
[void]$sb.AppendLine('  table,thead,tbody,th,td,tr{display:block;}')
[void]$sb.AppendLine('  thead tr{position:absolute;top:-9999px;left:-9999px;}')
[void]$sb.AppendLine('  tbody tr{display:grid;grid-template-columns:1fr 1fr;gap:4px;margin-bottom:12px;border-bottom:2px solid #e5e7eb;padding-bottom:8px;}')
[void]$sb.AppendLine('  td{padding:6px 8px;border:1px solid #e5e7eb;border-radius:6px;background:#f8fafc;min-height:0;}')
[void]$sb.AppendLine('  td::before{display:block;content:attr(data-label);font-size:10px;font-weight:700;color:#64748b;text-transform:uppercase;letter-spacing:.04em;margin-bottom:3px;}')
[void]$sb.AppendLine('  /* Signal (col 1) and Rx (col 6) span full width */')
[void]$sb.AppendLine('  td[data-label="Signal"],td[data-label="Rx"]{grid-column:1/-1;background:#fff;border-color:#bfdbfe;}')
[void]$sb.AppendLine('  @media (prefers-color-scheme:dark){')
[void]$sb.AppendLine('    tbody tr{border-bottom-color:#334155;}')
[void]$sb.AppendLine('    td{background:#162032;border-color:#334155;}')
[void]$sb.AppendLine('    td[data-label="Signal"],td[data-label="Rx"]{background:#1e293b;border-color:#3b82f6;}')
[void]$sb.AppendLine('  }')
[void]$sb.AppendLine('  .bytemap{display:grid;grid-template-columns:1fr 1fr;gap:4px;}
  .byte-cell{min-width:0;max-width:none;flex:none;}')
[void]$sb.AppendLine('}')
[void]$sb.AppendLine('</style>')
[void]$sb.AppendLine('</head>')
[void]$sb.AppendLine('<body>')
[void]$sb.AppendLine('<div class="page">')
[void]$sb.AppendLine('<section class="hero">')
[void]$sb.AppendLine('<h1>BMW CAN IDs Reference</h1>')
[void]$sb.AppendLine('<p>Static HTML generated from the merged BMW E8x/E9x DBC. Simple offline reference for CAN IDs, messages, and signals.</p>')
[void]$sb.AppendLine('<div class="meta">')
[void]$sb.AppendLine("<span>Source: $(Escape-Html $sourceName)</span>")
[void]$sb.AppendLine("<span>Generated: $(Escape-Html $generatedAt)</span>")
[void]$sb.AppendLine("<span>Messages: $($orderedMessages.Count)</span>")
[void]$sb.AppendLine("<span>Signals: $signalCount</span>")
[void]$sb.AppendLine('</div>')
[void]$sb.AppendLine('<div class="search-wrap">')
[void]$sb.AppendLine('<input type="text" id="search" placeholder="Filter by hex ID (e.g. 0x1D2), name, or transmitter&hellip;" autocomplete="off">')
[void]$sb.AppendLine('</div>')
[void]$sb.AppendLine('</section>')

[void]$sb.AppendLine('<details class="toc">')
[void]$sb.AppendLine("<summary>Message Index <span style='color:#64748b;font-weight:400;font-size:13px;'>($($orderedMessages.Count) messages)</span></summary>")
[void]$sb.AppendLine('<div class="toc-body"><div class="toc-list">')
foreach ($msg in $orderedMessages) {
    $anchor = "msg-$($msg.Id)"
    $hasKnown    = $knownValues.ContainsKey([int]$msg.Id)
    $hasDescribed = $msg.Comment -or ($msg.Signals.Count -gt 0)
    $styleColor  = if ($hasDescribed) { 'color:#22c55e;' } else { '' }
    $styleBold   = if ($hasKnown)   { 'font-weight:700;' } else { '' }
    $style = if ($styleColor -or $styleBold) { " style='$styleColor$styleBold'" } else { '' }
    [void]$sb.AppendLine("<a href='#$anchor' title='$(Escape-Html $msg.Name)'$style>$($msg.IdHex) $([char]0xB7) $(Escape-Html $msg.Name)</a>")
}
[void]$sb.AppendLine('</div></div>')
[void]$sb.AppendLine('</details>')

foreach ($msg in $orderedMessages) {
    $anchor   = "msg-$($msg.Id)"
    $searchData = "$($msg.IdHex) $($msg.Id) $($msg.Name) $($msg.Transmitter)".ToLower()
    [void]$sb.AppendLine("<section class='message' id='$anchor' data-search='$(Escape-Html $searchData)'>")
    [void]$sb.AppendLine('<div class="message-header">')
    [void]$sb.AppendLine('<div>')
    [void]$sb.AppendLine("<h2>$($msg.IdHex) &middot; $(Escape-Html $msg.Name)</h2>")
    [void]$sb.AppendLine("<div class='message-sub'>Decimal ID: $($msg.Id) <span class='muted'>&middot;</span> Transmitter: $(Escape-Html $msg.Transmitter)</div>")
    [void]$sb.AppendLine('</div>')
    [void]$sb.AppendLine('<div class="badge-row">')
    [void]$sb.AppendLine("<span class='badge'>DLC $($msg.Dlc)</span>")
    [void]$sb.AppendLine("<span class='badge'>$($msg.Signals.Count) signals</span>")
    [void]$sb.AppendLine('</div>')
    [void]$sb.AppendLine('</div>')

    if ($msg.Comment) {
        [void]$sb.AppendLine("<div class='comment'>$(Escape-Html $msg.Comment)</div>")
    }

    # Hex value row
    if ($msg.Dlc -gt 0) {
        [void]$sb.AppendLine((Get-HexRow $msg $knownValues))
    }

    # Byte map
    if ($msg.Dlc -gt 0) {
        [void]$sb.AppendLine("<div class='bytemap-label'>Byte layout</div>")
        [void]$sb.AppendLine((Get-ByteMap $msg))
    }

    # Signal table
    [void]$sb.AppendLine('<table>')
    [void]$sb.AppendLine('<thead><tr><th>Signal</th><th>Position</th><th>Format</th><th>Scale / Formula</th><th>Range</th><th>Receivers</th></tr></thead>')
    [void]$sb.AppendLine('<tbody>')
    foreach ($sig in $msg.Signals) {
        $humanPos = Get-HumanBitPos $sig
        $formula  = Get-Formula $sig

        [void]$sb.AppendLine('<tr>')

        # Signal name + comment + enum
        [void]$sb.AppendLine('<td data-label="Signal">')
        [void]$sb.AppendLine("<strong>$(Escape-Html $sig.Name)</strong>")
        if ($sig.Multiplex) {
            [void]$sb.AppendLine("<div class='signal-comment'><code>$(Escape-Html $sig.Multiplex)</code></div>")
        }
        if ($sig.Comment) {
            [void]$sb.AppendLine("<div class='signal-comment'>$(Escape-Html $sig.Comment)</div>")
        }
        if ($sig.EnumMap.Count -gt 0) {
            [void]$sb.AppendLine('<ul class="enum-list">')
            foreach ($key in $sig.EnumMap.Keys) {
                $decVal = [int]$key
                $hexVal = '0x{0:X2}' -f $decVal
                [void]$sb.AppendLine("<li><span class='enum-hex'>$hexVal</span> <span class='enum-dec'>($decVal)</span> = $(Escape-Html $sig.EnumMap[$key])</li>")
            }
            [void]$sb.AppendLine('</ul>')
        }
        [void]$sb.AppendLine('</td>')

        # Position — human-readable primary, DBC secondary
        [void]$sb.AppendLine('<td data-label="Position">')
        [void]$sb.AppendLine("<div class='human-pos'>$(Escape-Html $humanPos)</div>")
        [void]$sb.AppendLine("<div class='dbc-pos'>DBC: $($sig.StartBit)|$($sig.Length)</div>")
        [void]$sb.AppendLine('</td>')

        # Format
        [void]$sb.AppendLine("<td data-label=`"Format`">$(Escape-Html $sig.Endian)<br>$(Escape-Html $sig.ValueType)$(if ($sig.Unit) { '<br>Unit: ' + (Escape-Html $sig.Unit) } else { '' })</td>")

        # Scale / formula — human-readable primary, DBC secondary
        [void]$sb.AppendLine('<td data-label="Scale">')
        if ($formula) {
            [void]$sb.AppendLine("<div class='formula'>$formula</div>")
        }
        [void]$sb.AppendLine("<div class='dbc-scale'>Factor <code>$(Escape-Html $sig.Factor)</code> Offset <code>$(Escape-Html $sig.Offset)</code></div>")
        [void]$sb.AppendLine('</td>')

        # Range
        [void]$sb.AppendLine("<td data-label=`"Range`"><code>[$(Escape-Html $sig.Minimum) .. $(Escape-Html $sig.Maximum)]</code></td>")

        # Receivers
        [void]$sb.AppendLine("<td data-label=`"Rx`">$(Escape-Html $sig.Receivers)</td>")

        [void]$sb.AppendLine('</tr>')
    }
    [void]$sb.AppendLine('</tbody>')
    [void]$sb.AppendLine('</table>')
    [void]$sb.AppendLine('</section>')
}

[void]$sb.AppendLine('</div>')
[void]$sb.AppendLine('<button id="totop" onclick="window.scrollTo({top:0,behavior:''smooth''})" title="Back to top">&#8679;</button>')
[void]$sb.AppendLine('<style>')
[void]$sb.AppendLine('#totop{position:fixed;bottom:24px;right:24px;width:44px;height:44px;border-radius:50%;border:none;background:#1d4ed8;color:#fff;font-size:24px;line-height:1;cursor:pointer;box-shadow:0 4px 14px rgba(0,0,0,.25);opacity:0;transition:opacity .25s;z-index:999;}')
[void]$sb.AppendLine('#totop.vis{opacity:1;}')
[void]$sb.AppendLine('#totop:hover{background:#2563eb;}')
[void]$sb.AppendLine('@media (prefers-color-scheme:dark){#totop{background:#3b82f6;}#totop:hover{background:#60a5fa;}}')
[void]$sb.AppendLine('</style>')
[void]$sb.AppendLine('<script>')
[void]$sb.AppendLine('var s=document.getElementById("search");')
[void]$sb.AppendLine('var msgs=document.querySelectorAll(".message");')
[void]$sb.AppendLine('s.addEventListener("input",function(){')
[void]$sb.AppendLine('  var q=s.value.toLowerCase().trim();')
[void]$sb.AppendLine('  msgs.forEach(function(m){')
[void]$sb.AppendLine('    m.classList.toggle("hidden", q.length>0 && m.dataset.search.indexOf(q)===-1);')
[void]$sb.AppendLine('  });')
[void]$sb.AppendLine('});')
[void]$sb.AppendLine('var btn=document.getElementById("totop");')
[void]$sb.AppendLine('window.addEventListener("scroll",function(){btn.classList.toggle("vis",window.scrollY>300);});')
[void]$sb.AppendLine('</script>')
[void]$sb.AppendLine('</body>')
[void]$sb.AppendLine('</html>')

$outputDir = Split-Path -Path $OutputPath -Parent
if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

$resolvedDir  = if ([string]::IsNullOrWhiteSpace($outputDir)) { (Get-Location).Path } else { (Resolve-Path -Path $outputDir).Path }
$resolvedPath = [IO.Path]::Combine($resolvedDir, (Split-Path -Path $OutputPath -Leaf))
[System.IO.File]::WriteAllText($resolvedPath, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Host "Generated $OutputPath"
