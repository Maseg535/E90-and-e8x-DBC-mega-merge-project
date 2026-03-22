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

$messages = New-Object 'System.Collections.Generic.Dictionary[int,object]'
$currentMessage = $null

$messageRegex = [regex]'^BO_\s+(\d+)\s+([^:]+):\s+(\d+)\s+(\S+)'
$signalRegex = [regex]'^SG_\s+(\S+)(?:\s+(M|m\d+))?\s*:\s*(\d+)\|(\d+)@([01])([+-])\s+\(([^,]+),([^)]+)\)\s+\[([^|]+)\|([^\]]+)\]\s+"([^"]*)"\s+(.+)$'
$messageCommentRegex = [regex]'^CM_\s+BO_\s+(\d+)\s+"(.*)";$'
$signalCommentRegex = [regex]'^CM_\s+SG_\s+(\d+)\s+(\S+)\s+"(.*)";$'
$valRegex = [regex]'(-?\d+)\s+"([^"]*)"'

foreach ($rawLine in [System.IO.File]::ReadLines((Resolve-Path $DbcPath))) {
    $line = $rawLine.Trim()
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    $messageMatch = $messageRegex.Match($line)
    if ($messageMatch.Success) {
        $id = [int]$messageMatch.Groups[1].Value
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
        $id = [int]$signalCommentMatch.Groups[1].Value
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
        $trimmed = $line.Substring(5).TrimEnd(';')
        $firstSpace = $trimmed.IndexOf(' ')
        if ($firstSpace -lt 0) { continue }
        $id = [int]$trimmed.Substring(0, $firstSpace)
        $rest = $trimmed.Substring($firstSpace + 1)
        $secondSpace = $rest.IndexOf(' ')
        if ($secondSpace -lt 0) { continue }
        $signalName = $rest.Substring(0, $secondSpace)
        $pairs = $rest.Substring($secondSpace + 1)
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
$signalCount = ($orderedMessages | ForEach-Object { $_.Signals.Count } | Measure-Object -Sum).Sum
$generatedAt = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$sourceName = Split-Path -Path $DbcPath -Leaf

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<!DOCTYPE html>')
[void]$sb.AppendLine('<html lang="en">')
[void]$sb.AppendLine('<head>')
[void]$sb.AppendLine('<meta charset="utf-8">')
[void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
[void]$sb.AppendLine('<title>BMW CAN IDs Reference</title>')
[void]$sb.AppendLine('<style>')
[void]$sb.AppendLine('body{margin:0;font-family:Segoe UI,Arial,sans-serif;background:#f3f5f7;color:#1d2731;line-height:1.45;}')
[void]$sb.AppendLine('.page{max-width:1400px;margin:0 auto;padding:32px 20px 64px;}')
[void]$sb.AppendLine('.hero{background:#111827;color:#f9fafb;border-radius:18px;padding:28px 24px;box-shadow:0 18px 40px rgba(17,24,39,.18);}')
[void]$sb.AppendLine('.hero h1{margin:0 0 8px;font-size:34px;}')
[void]$sb.AppendLine('.hero p{margin:0;color:#cbd5e1;}')
[void]$sb.AppendLine('.meta{display:flex;flex-wrap:wrap;gap:12px;margin-top:18px;}')
[void]$sb.AppendLine('.meta span{display:inline-block;background:#1f2937;color:#e5e7eb;padding:10px 12px;border-radius:999px;font-size:14px;}')
[void]$sb.AppendLine('.toc{margin:24px 0 30px;padding:18px 20px;background:#ffffff;border-radius:16px;box-shadow:0 10px 24px rgba(15,23,42,.08);}')
[void]$sb.AppendLine('.toc h2{margin:0 0 12px;font-size:20px;}')
[void]$sb.AppendLine('.toc-list{display:flex;flex-wrap:wrap;gap:10px 12px;}')
[void]$sb.AppendLine('.toc a{display:inline-block;padding:8px 10px;border-radius:10px;background:#e5eef7;color:#1f3b5b;text-decoration:none;font-size:14px;}')
[void]$sb.AppendLine('.message{margin-top:22px;background:#ffffff;border-radius:18px;padding:22px 22px 24px;box-shadow:0 12px 28px rgba(15,23,42,.08);}')
[void]$sb.AppendLine('.message-header{display:flex;flex-wrap:wrap;justify-content:space-between;gap:12px 18px;align-items:flex-start;}')
[void]$sb.AppendLine('.message h2{margin:0;font-size:26px;color:#0f172a;}')
[void]$sb.AppendLine('.message-sub{margin-top:6px;color:#475569;font-size:15px;}')
[void]$sb.AppendLine('.badge-row{display:flex;flex-wrap:wrap;gap:10px;}')
[void]$sb.AppendLine('.badge{background:#eff6ff;border:1px solid #bfdbfe;color:#1d4ed8;padding:8px 10px;border-radius:999px;font-size:13px;font-weight:600;}')
[void]$sb.AppendLine('.comment{margin-top:14px;padding:12px 14px;border-left:4px solid #60a5fa;background:#f8fbff;color:#334155;border-radius:8px;}')
[void]$sb.AppendLine('table{width:100%;border-collapse:collapse;margin-top:18px;font-size:14px;}')
[void]$sb.AppendLine('th,td{padding:10px 8px;border-bottom:1px solid #e5e7eb;vertical-align:top;text-align:left;}')
[void]$sb.AppendLine('th{font-size:12px;text-transform:uppercase;letter-spacing:.04em;color:#64748b;background:#f8fafc;}')
[void]$sb.AppendLine('td code{font-family:Consolas,Monaco,monospace;background:#f8fafc;padding:2px 4px;border-radius:6px;}')
[void]$sb.AppendLine('.signal-comment{margin-top:6px;color:#475569;font-size:13px;}')
[void]$sb.AppendLine('.enum-list{margin:8px 0 0;padding-left:18px;color:#334155;font-size:13px;}')
[void]$sb.AppendLine('.enum-list li{margin:2px 0;}')
[void]$sb.AppendLine('.muted{color:#64748b;}')
[void]$sb.AppendLine('@media (max-width:900px){.message-header{flex-direction:column;}table{display:block;overflow-x:auto;}}')
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
[void]$sb.AppendLine('</section>')
[void]$sb.AppendLine('<section class="toc">')
[void]$sb.AppendLine('<h2>Message Index</h2>')
[void]$sb.AppendLine('<div class="toc-list">')
foreach ($msg in $orderedMessages) {
    $anchor = "msg-$($msg.Id)"
    [void]$sb.AppendLine("<a href='#$anchor'>$($msg.IdHex) &middot; $(Escape-Html $msg.Name)</a>")
}
[void]$sb.AppendLine('</div>')
[void]$sb.AppendLine('</section>')

foreach ($msg in $orderedMessages) {
    $anchor = "msg-$($msg.Id)"
    [void]$sb.AppendLine("<section class='message' id='$anchor'>")
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
    [void]$sb.AppendLine('<table>')
    [void]$sb.AppendLine('<thead><tr><th>Signal</th><th>Bits</th><th>Format</th><th>Scale</th><th>Range</th><th>Receivers</th></tr></thead>')
    [void]$sb.AppendLine('<tbody>')
    foreach ($sig in $msg.Signals) {
        [void]$sb.AppendLine('<tr>')
        [void]$sb.AppendLine('<td>')
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
                [void]$sb.AppendLine("<li><code>$(Escape-Html $key)</code> = $(Escape-Html $sig.EnumMap[$key])</li>")
            }
            [void]$sb.AppendLine('</ul>')
        }
        [void]$sb.AppendLine('</td>')
        [void]$sb.AppendLine("<td><code>$($sig.StartBit)|$($sig.Length)</code></td>")
        [void]$sb.AppendLine("<td>$(Escape-Html $sig.Endian)<br>$(Escape-Html $sig.ValueType)$(if ($sig.Unit) { '<br>Unit: ' + (Escape-Html $sig.Unit) } else { '' })</td>")
        [void]$sb.AppendLine("<td>Factor <code>$(Escape-Html $sig.Factor)</code><br>Offset <code>$(Escape-Html $sig.Offset)</code></td>")
        [void]$sb.AppendLine("<td><code>[$(Escape-Html $sig.Minimum) .. $(Escape-Html $sig.Maximum)]</code></td>")
        [void]$sb.AppendLine("<td>$(Escape-Html $sig.Receivers)</td>")
        [void]$sb.AppendLine('</tr>')
    }
    [void]$sb.AppendLine('</tbody>')
    [void]$sb.AppendLine('</table>')
    [void]$sb.AppendLine('</section>')
}

[void]$sb.AppendLine('</div>')
[void]$sb.AppendLine('</body>')
[void]$sb.AppendLine('</html>')

$outputDir = Split-Path -Path $OutputPath -Parent
if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

[System.IO.File]::WriteAllText((Resolve-Path -Path (Split-Path -Path $OutputPath -Parent)).Path + '\\' + (Split-Path -Path $OutputPath -Leaf), $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Host "Generated $OutputPath"
