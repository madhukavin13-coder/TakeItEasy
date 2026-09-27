$ErrorActionPreference = "Stop"

$DefaultPort = 5000
$ChunkSize = 1024 * 1024
$ConnectionTimeoutSeconds = 30
$ProtocolVersion = 1

function Show-Title {
    Clear-Host
    Write-Host ""
    Write-Host "TakeItEasy - WireDrop"
    Write-Host ""
}

function New-SessionId {
    $bytes = New-Object byte[] 8
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return ([Convert]::ToBase64String($bytes) -replace "[^A-Za-z0-9]", "").Substring(0, 8).ToUpper()
}

function New-Password {
    $bytes = New-Object byte[] 12
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return ([Convert]::ToBase64String($bytes) -replace "[^A-Za-z0-9]", "").Substring(0, 12)
}

function Get-LocalIPv4 {
    try {
        $udp = [System.Net.Sockets.UdpClient]::new()
        $udp.Connect("1.1.1.1", 80)
        $localEndPoint = $udp.Client.LocalEndPoint
        $udp.Dispose()

        if ($localEndPoint -and $localEndPoint.Address) {
            $ip = $localEndPoint.Address.IPAddressToString

            if (
                $ip -notlike "127.*" -and
                $ip -notlike "169.254.*" -and
                $ip -notlike "172.17.*" -and
                $ip -notlike "172.18.*" -and
                $ip -notlike "172.19.*" -and
                $ip -notlike "172.20.*" -and
                $ip -notlike "172.21.*" -and
                $ip -notlike "172.22.*" -and
                $ip -notlike "172.23.*" -and
                $ip -notlike "172.24.*" -and
                $ip -notlike "172.25.*" -and
                $ip -notlike "172.26.*" -and
                $ip -notlike "172.27.*" -and
                $ip -notlike "172.28.*" -and
                $ip -notlike "172.29.*" -and
                $ip -notlike "172.30.*" -and
                $ip -notlike "172.31.*"
            ) {
                return $ip
            }
        }
    }
    catch {
    }

    try {
        $addresses = [System.Net.Dns]::GetHostAddresses(
            [System.Net.Dns]::GetHostName()
        )

        foreach ($address in $addresses) {
            if ($address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
                $ip = $address.IPAddressToString

                if (
                    $ip -notlike "127.*" -and
                    $ip -notlike "169.254.*" -and
                    $ip -notlike "172.17.*" -and
                    $ip -notlike "172.18.*" -and
                    $ip -notlike "172.19.*" -and
                    $ip -notlike "172.20.*" -and
                    $ip -notlike "172.21.*" -and
                    $ip -notlike "172.22.*" -and
                    $ip -notlike "172.23.*" -and
                    $ip -notlike "172.24.*" -and
                    $ip -notlike "172.25.*" -and
                    $ip -notlike "172.26.*" -and
                    $ip -notlike "172.27.*" -and
                    $ip -notlike "172.28.*" -and
                    $ip -notlike "172.29.*" -and
                    $ip -notlike "172.30.*" -and
                    $ip -notlike "172.31.*"
                ) {
                    return $ip
                }
            }
        }
    }
    catch {
    }

    return "Unknown"
}

function Write-Exact {
    param(
        [System.IO.Stream]$Stream,
        [byte[]]$Buffer,
        [int]$Offset = 0,
        [int]$Count = $Buffer.Length
    )

    $written = 0

    while ($written -lt $Count) {
        $Stream.Write(
            $Buffer,
            $Offset + $written,
            $Count - $written
        )

        $written = $Count
    }
}

function Read-Exact {
    param(
        [System.IO.Stream]$Stream,
        [int]$Count
    )

    $buffer = New-Object byte[] $Count
    $read = 0

    while ($read -lt $Count) {
        $n = $Stream.Read(
            $buffer,
            $read,
            $Count - $read
        )

        if ($n -le 0) {
            throw "Connection closed while receiving data."
        }

        $read += $n
    }

    return $buffer
}

function Send-Int32 {
    param(
        [System.IO.Stream]$Stream,
        [int]$Value
    )

    $bytes = [BitConverter]::GetBytes($Value)

    if (-not [BitConverter]::IsLittleEndian) {
        [Array]::Reverse($bytes)
    }

    Write-Exact -Stream $Stream -Buffer $bytes
}

function Receive-Int32 {
    param(
        [System.IO.Stream]$Stream
    )

    $bytes = Read-Exact -Stream $Stream -Count 4

    if (-not [BitConverter]::IsLittleEndian) {
        [Array]::Reverse($bytes)
    }

    return [BitConverter]::ToInt32($bytes, 0)
}

function Send-Int64 {
    param(
        [System.IO.Stream]$Stream,
        [long]$Value
    )

    $bytes = [BitConverter]::GetBytes($Value)

    if (-not [BitConverter]::IsLittleEndian) {
        [Array]::Reverse($bytes)
    }

    Write-Exact -Stream $Stream -Buffer $bytes
}

function Receive-Int64 {
    param(
        [System.IO.Stream]$Stream
    )

    $bytes = Read-Exact -Stream $Stream -Count 8

    if (-not [BitConverter]::IsLittleEndian) {
        [Array]::Reverse($bytes)
    }

    return [BitConverter]::ToInt64($bytes, 0)
}

function Send-String {
    param(
        [System.IO.Stream]$Stream,
        [string]$Value
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)

    Send-Int64 -Stream $Stream -Value $bytes.Length
    Write-Exact -Stream $Stream -Buffer $bytes
}

function Receive-String {
    param(
        [System.IO.Stream]$Stream
    )

    $length = Receive-Int64 -Stream $Stream

    if ($length -lt 0 -or $length -gt 16MB) {
        throw "Invalid string length."
    }

    $bytes = Read-Exact -Stream $Stream -Count ([int]$length)

    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Send-Manifest {
    param(
        [System.IO.Stream]$Stream,
        [object[]]$Items
    )

    Send-Int64 -Stream $Stream -Value $Items.Count

    foreach ($item in $Items) {
        Send-String -Stream $Stream -Value $item.Type
        Send-String -Stream $Stream -Value $item.RelativePath
        Send-Int64 -Stream $Stream -Value ([int64]$item.Size)
    }
}

function Receive-Manifest {
    param(
        [System.IO.Stream]$Stream
    )

    $count = Receive-Int64 -Stream $Stream

    if ($count -lt 0 -or $count -gt 10000000) {
        throw "Invalid manifest count."
    }

    $items = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $count; $i++) {
        $type = Receive-String -Stream $Stream
        $relativePath = Receive-String -Stream $Stream
        $size = Receive-Int64 -Stream $Stream

        if ($type -ne "File" -and $type -ne "Directory") {
            throw "Invalid transfer item type."
        }

        $items.Add([PSCustomObject]@{
            Type = $type
            RelativePath = $relativePath
            Size = $size
        })
    }

    return $items
}

function Get-FilePicker {
    if ($IsWindows) {
        Add-Type -AssemblyName System.Windows.Forms

        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Multiselect = $true
        $dialog.Title = "Select files to send"
        $dialog.CheckFileExists = $true

        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return @($dialog.FileNames)
        }

        return @()
    }

    if (Get-Command zenity -ErrorAction SilentlyContinue) {
        $result = & zenity `
            --file-selection `
            --multiple `
            --separator="|" `
            --title="Select files to send" 2>$null

        if ($LASTEXITCODE -eq 0 -and $result) {
            return @(
                $result -split "\|" |
                Where-Object {
                    -not [string]::IsNullOrWhiteSpace($_)
                }
            )
        }

        return @()
    }

    Write-Host ""
    Write-Host "No graphical file picker is available."
    Write-Host "Install zenity with:"
    Write-Host "  sudo pacman -S zenity"
    Write-Host ""

    $path = Read-Host "Enter file path"

    if ([string]::IsNullOrWhiteSpace($path)) {
        return @()
    }

    return @(
        $path.Trim().Trim('"', "'")
    )
}

function Get-FolderPicker {
    if ($IsWindows) {
        Add-Type -AssemblyName System.Windows.Forms

        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "Select folder to send"
        $dialog.ShowNewFolderButton = $false

        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return @($dialog.SelectedPath)
        }

        return @()
    }

    if (Get-Command zenity -ErrorAction SilentlyContinue) {
        $result = & zenity `
            --file-selection `
            --directory `
            --title="Select folder to send" 2>$null

        if ($LASTEXITCODE -eq 0 -and $result) {
            return @($result)
        }

        return @()
    }

    Write-Host ""
    Write-Host "No graphical folder picker is available."
    Write-Host "Install zenity with:"
    Write-Host "  sudo pacman -S zenity"
    Write-Host ""

    $path = Read-Host "Enter folder path"

    if ([string]::IsNullOrWhiteSpace($path)) {
        return @()
    }

    return @(
        $path.Trim().Trim('"', "'")
    )
}

function Add-PathsToQueue {
    param(
        [System.Collections.Generic.List[string]]$Queue,
        [string[]]$Paths
    )

    foreach ($path in $Paths) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        $expanded = [System.Environment]::ExpandEnvironmentVariables($path)
        $fullPath = [System.IO.Path]::GetFullPath($expanded)

        if (
            [System.IO.File]::Exists($fullPath) -or
            [System.IO.Directory]::Exists($fullPath)
        ) {
            if (-not $Queue.Contains($fullPath)) {
                $Queue.Add($fullPath)
            }
        }
    }
}

function Show-Queue {
    param(
        [System.Collections.Generic.List[string]]$Queue
    )

    Write-Host ""
    Write-Host "Transfer queue"
    Write-Host ""

    if ($Queue.Count -eq 0) {
        Write-Host "  Empty"
        return
    }

    for ($i = 0; $i -lt $Queue.Count; $i++) {
        $item = Get-Item -LiteralPath $Queue[$i]

        $type = if ($item.PSIsContainer) {
            "Folder"
        }
        else {
            "File"
        }

        Write-Host ("  [{0}] [{1}] {2}" -f ($i + 1), $type, $item.FullName)
    }

    Write-Host ""
    Write-Host ("  {0} item(s)" -f $Queue.Count)
}

function Get-TransferItems {
    param(
        [System.Collections.Generic.List[string]]$Queue
    )

    $items = New-Object System.Collections.Generic.List[object]
    $usedPaths = New-Object System.Collections.Generic.HashSet[string](
        [System.StringComparer]::OrdinalIgnoreCase
    )

    foreach ($inputPath in $Queue) {
        $fullPath = [System.IO.Path]::GetFullPath(
            [System.Environment]::ExpandEnvironmentVariables($inputPath)
        )

        if (
            -not [System.IO.File]::Exists($fullPath) -and
            -not [System.IO.Directory]::Exists($fullPath)
        ) {
            throw "Path does not exist: $inputPath"
        }

        if ([System.IO.File]::Exists($fullPath)) {
            if (-not $usedPaths.Add($fullPath)) {
                continue
            }

            $fileInfo = Get-Item -LiteralPath $fullPath

            $items.Add([PSCustomObject]@{
                Type = "File"
                RelativePath = $fileInfo.Name
                SourcePath = $fullPath
                Size = [int64]$fileInfo.Length
            })

            continue
        }

        $rootInfo = Get-Item -LiteralPath $fullPath
        $parentPath = [System.IO.Path]::GetDirectoryName($fullPath)

        if ($usedPaths.Add($fullPath)) {
            $items.Add([PSCustomObject]@{
                Type = "Directory"
                RelativePath = $rootInfo.Name
                SourcePath = $fullPath
                Size = [int64]0
            })
        }

        foreach ($directory in Get-ChildItem -LiteralPath $fullPath -Directory -Recurse -Force) {
            if ($usedPaths.Add($directory.FullName)) {
                $relative = [System.IO.Path]::GetRelativePath(
                    $parentPath,
                    $directory.FullName
                )

                $items.Add([PSCustomObject]@{
                    Type = "Directory"
                    RelativePath = $relative
                    SourcePath = $directory.FullName
                    Size = [int64]0
                })
            }
        }

        foreach ($file in Get-ChildItem -LiteralPath $fullPath -File -Recurse -Force) {
            if ($usedPaths.Add($file.FullName)) {
                $relative = [System.IO.Path]::GetRelativePath(
                    $parentPath,
                    $file.FullName
                )

                $items.Add([PSCustomObject]@{
                    Type = "File"
                    RelativePath = $relative
                    SourcePath = $file.FullName
                    Size = [int64]$file.Length
                })
            }
        }
    }

    return $items
}

function Send-File {
    param(
        [System.IO.Stream]$Stream,
        [string]$Path,
        [long]$StartOffset,
        [long]$TotalBytes,
        [ref]$Transferred,
        [System.Diagnostics.Stopwatch]$Timer
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()

    try {
        $file = [System.IO.File]::OpenRead($Path)

        try {
            $buffer = New-Object byte[] $ChunkSize

            if ($StartOffset -gt 0) {
                $hashFile = [System.IO.File]::OpenRead($Path)

                try {
                    $remaining = $StartOffset

                    while ($remaining -gt 0) {
                        $read = $hashFile.Read(
                            $buffer,
                            0,
                            [Math]::Min(
                                $buffer.Length,
                                [int]$remaining
                            )
                        )

                        if ($read -le 0) {
                            throw "Unable to prepare resume hash."
                        }

                        $sha.TransformBlock(
                            $buffer,
                            0,
                            $read,
                            $buffer,
                            0
                        ) | Out-Null

                        $remaining -= $read
                    }
                }
                finally {
                    $hashFile.Dispose()
                }

                $file.Position = $StartOffset
            }

            while (($read = $file.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $sha.TransformBlock(
                    $buffer,
                    0,
                    $read,
                    $buffer,
                    0
                ) | Out-Null

                Send-Int32 -Stream $Stream -Value $read
                Write-Exact -Stream $Stream -Buffer $buffer -Count $read

                $Transferred.Value += $read

                $elapsed = $Timer.Elapsed.TotalSeconds

                if ($elapsed -gt 0 -and $TotalBytes -gt 0) {
                    $speed = $Transferred.Value / $elapsed
                    $remaining = ($TotalBytes - $Transferred.Value) / $speed
                    $percent = [Math]::Min(
                        100,
                        ($Transferred.Value / [double]$TotalBytes) * 100
                    )

                    Write-Progress `
                        -Activity "Sending" `
                        -Status ("{0:N1}% | {1:N2} MB/s | ETA {2:N0}s" -f `
                            $percent,
                            ($speed / 1MB),
                            $remaining) `
                        -PercentComplete $percent
                }
            }

            $sha.TransformFinalBlock(
                [byte[]]::new(0),
                0,
                0
            )

            Send-Int32 -Stream $Stream -Value 0

            Send-String `
                -Stream $Stream `
                -Value ([Convert]::ToHexString($sha.Hash)).ToLower()
        }
        finally {
            $file.Dispose()
        }
    }
    finally {
        $sha.Dispose()
    }
}

function Receive-File {
    param(
        [System.IO.Stream]$Stream,
        [string]$Path,
        [long]$ExpectedSize,
        [long]$StartOffset,
        [long]$TotalBytes,
        [ref]$Transferred,
        [System.Diagnostics.Stopwatch]$Timer
    )

    $directory = [System.IO.Path]::GetDirectoryName($Path)

    if ($directory) {
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()

    try {
        if ($StartOffset -gt 0) {
            $existing = [System.IO.File]::OpenRead($Path)

            try {
                $buffer = New-Object byte[] $ChunkSize
                $remaining = $StartOffset

                while ($remaining -gt 0) {
                    $read = $existing.Read(
                        $buffer,
                        0,
                        [Math]::Min(
                            $buffer.Length,
                            [int]$remaining
                        )
                    )

                    if ($read -le 0) {
                        throw "Unable to read partial file."
                    }

                    $sha.TransformBlock(
                        $buffer,
                        0,
                        $read,
                        $buffer,
                        0
                    ) | Out-Null

                    $remaining -= $read
                }
            }
            finally {
                $existing.Dispose()
            }
        }

        $file = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Append,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )

        try {
            $received = $StartOffset

            while ($true) {
                $length = Receive-Int32 -Stream $Stream

                if ($length -eq 0) {
                    break
                }

                if ($length -lt 0 -or $length -gt $ChunkSize) {
                    throw "Invalid chunk size."
                }

                $chunk = Read-Exact -Stream $Stream -Count $length

                $sha.TransformBlock(
                    $chunk,
                    0,
                    $length,
                    $chunk,
                    0
                ) | Out-Null

                $file.Write(
                    $chunk,
                    0,
                    $length
                )

                $received += $length
                $Transferred.Value += $length

                if ($received -gt $ExpectedSize) {
                    throw "Received more data than expected."
                }

                $elapsed = $Timer.Elapsed.TotalSeconds

                if ($elapsed -gt 0 -and $TotalBytes -gt 0) {
                    $speed = $Transferred.Value / $elapsed
                    $remaining = ($TotalBytes - $Transferred.Value) / $speed
                    $percent = [Math]::Min(
                        100,
                        ($Transferred.Value / [double]$TotalBytes) * 100
                    )

                    Write-Progress `
                        -Activity "Receiving" `
                        -Status ("{0:N1}% | {1:N2} MB/s | ETA {2:N0}s" -f `
                            $percent,
                            ($speed / 1MB),
                            $remaining) `
                        -PercentComplete $percent
                }
            }

            if ($received -ne $ExpectedSize) {
                throw "File size mismatch."
            }

            $sha.TransformFinalBlock(
                [byte[]]::new(0),
                0,
                0
            )

            $expectedHash = Receive-String -Stream $Stream
            $actualHash = ([Convert]::ToHexString($sha.Hash)).ToLower()

            if ($actualHash -ne $expectedHash.ToLower()) {
                throw "SHA-256 verification failed."
            }
        }
        finally {
            $file.Dispose()
        }
    }
    finally {
        $sha.Dispose()
    }
}

function Start-Sender {
    $queue = New-Object System.Collections.Generic.List[string]

    while ($true) {
        Show-Title
        Show-Queue -Queue $queue

        Write-Host ""
        Write-Host "1  Add files"
        Write-Host "2  Add folder"
        Write-Host "3  Remove item"
        Write-Host "4  Clear queue"
        Write-Host "5  Start transfer"
        Write-Host "6  Back"
        Write-Host ""

        $choice = Read-Host ">"

        switch ($choice) {
            "1" {
                $paths = Get-FilePicker
                Add-PathsToQueue -Queue $queue -Paths $paths
            }

            "2" {
                $paths = Get-FolderPicker
                Add-PathsToQueue -Queue $queue -Paths $paths
            }

            "3" {
                if ($queue.Count -gt 0) {
                    $number = Read-Host "Item number"

                    if ($number -match "^\d+$") {
                        $index = [int]$number - 1

                        if ($index -ge 0 -and $index -lt $queue.Count) {
                            $queue.RemoveAt($index)
                        }
                    }
                }
            }

            "4" {
                $queue.Clear()
            }

            "5" {
                if ($queue.Count -eq 0) {
                    Write-Host ""
                    Write-Host "Queue is empty." -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                    continue
                }

                break
            }

            "6" {
                return
            }
        }

        if ($choice -eq "5" -and $queue.Count -gt 0) {
            break
        }
    }

    Show-Title
    Write-Host "Transfer settings"
    Write-Host ""

    do {
        $portInput = Read-Host "Port [$DefaultPort]"

        if ([string]::IsNullOrWhiteSpace($portInput)) {
            $port = $DefaultPort
        }
        elseif ($portInput -match "^\d+$") {
            $port = [int]$portInput
        }
        else {
            $port = 0
        }

        if ($port -lt 1 -or $port -gt 65535) {
            Write-Host "Invalid port." -ForegroundColor Yellow
        }
    }
    while ($port -lt 1 -or $port -gt 65535)

    do {
        $password = Read-Host "Password"

        if ([string]::IsNullOrWhiteSpace($password)) {
            Write-Host "Password cannot be empty." -ForegroundColor Yellow
        }
    }
    while ([string]::IsNullOrWhiteSpace($password))

    Write-Host ""
    Write-Host "Preparing transfer..."
    Write-Host ""

    $items = @(Get-TransferItems -Queue $queue)

    $files = @($items | Where-Object Type -eq "File")
    $folders = @($items | Where-Object Type -eq "Directory")

    $measure = $files | Measure-Object -Property Size -Sum

    if ($null -eq $measure.Sum) {
        $totalBytes = [int64]0
    }
    else {
        $totalBytes = [int64]$measure.Sum
    }

    $sessionId = New-SessionId
    $ip = Get-LocalIPv4

    $listener = [System.Net.Sockets.TcpListener]::new(
        [System.Net.IPAddress]::Any,
        $port
    )

    try {
        $listener.Start()

        Show-Title

        Write-Host "Connection info"
        Write-Host ""
        Write-Host ("IP Address : {0}" -f $ip)
        Write-Host ("Port       : {0}" -f $port)
        Write-Host ("Session ID : {0}" -f $sessionId)
        Write-Host ("Password   : {0}" -f $password)
        Write-Host ""
        Write-Host ("Items      : {0}" -f $queue.Count)
        Write-Host ("Files      : {0}" -f $files.Count)
        Write-Host ("Folders    : {0}" -f $folders.Count)
        Write-Host ("Total      : {0:N0} bytes" -f $totalBytes)
        Write-Host ""
        Write-Host "Waiting for receiver..."

        $client = $listener.AcceptTcpClient()

        try {
            $client.ReceiveTimeout = $ConnectionTimeoutSeconds * 1000
            $client.SendTimeout = $ConnectionTimeoutSeconds * 1000

            $stream = $client.GetStream()

            Send-Int32 -Stream $stream -Value $ProtocolVersion
            Send-String -Stream $stream -Value $sessionId

            $receiverSession = Receive-String -Stream $stream
            $receiverPassword = Receive-String -Stream $stream

            if ($receiverSession -ne $sessionId) {
                Send-String -Stream $stream -Value "ERROR: Invalid session ID."
                throw "Invalid session ID."
            }

            if ($receiverPassword -ne $password) {
                Send-String -Stream $stream -Value "ERROR: Invalid password."
                throw "Invalid password."
            }

            Send-String -Stream $stream -Value "OK"

            Send-Int64 -Stream $stream -Value $totalBytes
            Send-Manifest -Stream $stream -Items $items

            $transferred = [int64]0
            $timer = [System.Diagnostics.Stopwatch]::StartNew()

            foreach ($item in $items) {
                Send-String -Stream $stream -Value $item.Type
                Send-String -Stream $stream -Value $item.RelativePath
                Send-Int64 -Stream $stream -Value ([int64]$item.Size)

                if ($item.Type -eq "Directory") {
                    continue
                }

                $response = Receive-String -Stream $stream

                if ($response -eq "SKIP") {
                    continue
                }

                if ($response -notmatch "^RESUME:(\d+)$") {
                    throw "Invalid receiver response."
                }

                $offset = [int64]$Matches[1]

                Send-File `
                    -Stream $stream `
                    -Path $item.SourcePath `
                    -StartOffset $offset `
                    -TotalBytes $totalBytes `
                    -Transferred ([ref]$transferred) `
                    -Timer $timer
            }

            Send-String -Stream $stream -Value "TRANSFER_COMPLETE"

            $timer.Stop()

            Write-Progress -Activity "Sending" -Completed

            Write-Host ""
            Write-Host "Transfer complete." -ForegroundColor Green
        }
        finally {
            $client.Dispose()
        }
    }
    finally {
        $listener.Stop()
    }

    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Start-Receiver {
    Show-Title

    $ip = Read-Host "Sender IP"

    $portInput = Read-Host "Port [5000]"

    if ([string]::IsNullOrWhiteSpace($portInput)) {
        $port = $DefaultPort
    }
    else {
        if ($portInput -notmatch "^\d+$") {
            throw "Invalid port."
        }

        $port = [int]$portInput
    }

    if ($port -lt 1 -or $port -gt 65535) {
        throw "Invalid port."
    }

    $sessionId = Read-Host "Session ID"
    $password = Read-Host "Password"
    $destination = Read-Host "Destination [current folder]"

    if ([string]::IsNullOrWhiteSpace($destination)) {
        $destination = (Get-Location).Path
    }

    $destination = [System.IO.Path]::GetFullPath(
        [System.Environment]::ExpandEnvironmentVariables($destination)
    )

    [System.IO.Directory]::CreateDirectory($destination) | Out-Null

    $client = [System.Net.Sockets.TcpClient]::new()

    try {
        Write-Host ""
        Write-Host "Connecting..."

        $client.Connect($ip, $port)

        $client.ReceiveTimeout = $ConnectionTimeoutSeconds * 1000
        $client.SendTimeout = $ConnectionTimeoutSeconds * 1000

        $stream = $client.GetStream()

        $version = Receive-Int32 -Stream $stream

        if ($version -ne $ProtocolVersion) {
            throw "Unsupported WireDrop protocol version."
        }

        $serverSession = Receive-String -Stream $stream

        if ($serverSession -ne $sessionId) {
            throw "Session ID mismatch."
        }

        Send-String -Stream $stream -Value $sessionId
        Send-String -Stream $stream -Value $password

        $result = Receive-String -Stream $stream

        if ($result -ne "OK") {
            throw $result
        }

        $totalBytes = Receive-Int64 -Stream $stream
        $manifest = @(Receive-Manifest -Stream $stream)

        $transferred = [int64]0
        $timer = [System.Diagnostics.Stopwatch]::StartNew()

        $rootWithSeparator =
            $destination.TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar
            ) +
            [System.IO.Path]::DirectorySeparatorChar

        while ($true) {
            $type = Receive-String -Stream $stream

            if ($type -eq "TRANSFER_COMPLETE") {
                break
            }

            $relativePath = Receive-String -Stream $stream
            $expectedSize = Receive-Int64 -Stream $stream

            $relativePath = $relativePath.Replace(
                [System.IO.Path]::AltDirectorySeparatorChar,
                [System.IO.Path]::DirectorySeparatorChar
            )

            $fullDestination = [System.IO.Path]::GetFullPath(
                [System.IO.Path]::Combine(
                    $destination,
                    $relativePath
                )
            )

            if (
                $fullDestination -ne $destination -and
                -not $fullDestination.StartsWith(
                    $rootWithSeparator,
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            ) {
                throw "Unsafe path received."
            }

            if ($type -eq "Directory") {
                [System.IO.Directory]::CreateDirectory($fullDestination) | Out-Null
                continue
            }

            $parent = [System.IO.Path]::GetDirectoryName($fullDestination)

            if ($parent) {
                [System.IO.Directory]::CreateDirectory($parent) | Out-Null
            }

            $partPath = "$fullDestination.part"

            $offset = [int64]0

            if ([System.IO.File]::Exists($fullDestination)) {
                if ((Get-Item -LiteralPath $fullDestination).Length -eq $expectedSize) {
                    Send-String -Stream $stream -Value "SKIP"
                    continue
                }
            }

            if ([System.IO.File]::Exists($partPath)) {
                $offset = [int64](Get-Item -LiteralPath $partPath).Length

                if ($offset -gt $expectedSize) {
                    Remove-Item -LiteralPath $partPath -Force
                    $offset = 0
                }
            }

            Send-String -Stream $stream -Value ("RESUME:{0}" -f $offset)

            Write-Host ""
            Write-Host "Receiving:"
            Write-Host $relativePath

            Receive-File `
                -Stream $stream `
                -Path $partPath `
                -ExpectedSize $expectedSize `
                -StartOffset $offset `
                -TotalBytes $totalBytes `
                -Transferred ([ref]$transferred) `
                -Timer $timer

            if ([System.IO.File]::Exists($fullDestination)) {
                Remove-Item -LiteralPath $fullDestination -Force
            }

            Move-Item `
                -LiteralPath $partPath `
                -Destination $fullDestination `
                -Force
        }

        $timer.Stop()

        Write-Progress -Activity "Receiving" -Completed

        Write-Host ""
        Write-Host "Transfer complete." -ForegroundColor Green
    }
    finally {
        $client.Dispose()
    }

    Write-Host ""
    Read-Host "Press Enter to continue"
}

while ($true) {
    Show-Title

    Write-Host "1  Create session"
    Write-Host "2  Join session"
    Write-Host "3  Exit"
    Write-Host ""

    $choice = Read-Host ">"

    try {
        switch ($choice) {
            "1" {
                Start-Sender
            }

            "2" {
                Start-Receiver
            }

            "3" {
                exit
            }
        }
    }
    catch {
        Write-Progress -Activity "Transfer" -Completed

        Write-Host ""
        Write-Host "Error:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ""

        Read-Host "Press Enter to continue"
    }
}