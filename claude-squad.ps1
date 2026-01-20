#═══════════════════════════════════════════════════════════════════════════════
#  CLAUDE SQUAD - Multi-Terminal Launcher for Claude Code
#═══════════════════════════════════════════════════════════════════════════════
#  Just place the folder in your project directory and double-click Launch.bat
#  Configure settings in config.json (or edit the defaults below)
#═══════════════════════════════════════════════════════════════════════════════

#region Script Variables
$script:ScriptDir = $PSScriptRoot
if (-not $script:ScriptDir) {
    $script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$script:LogFile = $null
$script:LaunchedProcesses = @()
#endregion

#region Default Configuration
$DefaultConfig = @{
    InstanceCount = 6
    DangerouslySkipPermissions = $true
    Arrangement = "grid"
    TargetMonitor = "primary"
    LaunchDelay = 800
    Padding = 20
    WindowGap = 10
    TitlePrefix = "Claude Code"
    AdditionalArgs = ""
    Preset = $null
    KeepLauncherOpen = $false
    Instances = $null
    Colors = @(
        "#E74C3C", "#E67E22", "#F1C40F", "#2ECC71", "#00CED1", "#3498DB",
        "#9B59B6", "#E91E63", "#00BCD4", "#8BC34A", "#FF5722", "#607D8B"
    )
}
#endregion

#region Windows API
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Diagnostics;

public class WindowManager {
    // DPI Awareness
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    // Window manipulation
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    public static List<IntPtr> FindWindowTerminalWindows() {
        List<IntPtr> windows = new List<IntPtr>();

        EnumWindows((hWnd, lParam) => {
            if (!IsWindowVisible(hWnd)) return true;

            StringBuilder className = new StringBuilder(256);
            GetClassName(hWnd, className, 256);

            // Windows Terminal uses CASCADIA_HOSTING_WINDOW_CLASS
            if (className.ToString().Contains("CASCADIA_HOSTING_WINDOW_CLASS")) {
                windows.Add(hWnd);
            }
            return true;
        }, IntPtr.Zero);

        return windows;
    }

    public static string GetWindowTitle(IntPtr hWnd) {
        StringBuilder sb = new StringBuilder(512);
        GetWindowText(hWnd, sb, 512);
        return sb.ToString();
    }

    public static uint GetWindowProcessId(IntPtr hWnd) {
        uint processId;
        GetWindowThreadProcessId(hWnd, out processId);
        return processId;
    }
}
"@

# Make this process DPI-aware so we get real pixel coordinates
[WindowManager]::SetProcessDPIAware() | Out-Null

Add-Type -AssemblyName System.Windows.Forms
#endregion

#region Logging Functions
<#
.SYNOPSIS
    Initializes the logging system with auto-cleanup of old logs.
.DESCRIPTION
    Creates the logs directory if needed, sets up the log file path,
    and removes log files older than 7 days.
#>
function Initialize-Logging {
    $logsDir = Join-Path $script:ScriptDir "logs"

    # Create logs directory if it doesn't exist
    if (-not (Test-Path $logsDir)) {
        New-Item -Path $logsDir -ItemType Directory -Force | Out-Null
    }

    # Set log file path with timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $script:LogFile = Join-Path $logsDir "claude-squad-$timestamp.log"

    # Auto-cleanup: Delete logs older than 7 days
    $cutoffDate = (Get-Date).AddDays(-7)
    Get-ChildItem -Path $logsDir -Filter "claude-squad-*.log" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoffDate } |
        ForEach-Object {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }

    Write-Log "Claude Squad starting..." "INFO"
    Write-Log "Log file: $script:LogFile" "DEBUG"
}

<#
.SYNOPSIS
    Writes a message to both console and log file.
.PARAMETER Message
    The message to log.
.PARAMETER Level
    The log level: INFO, WARN, ERROR, DEBUG, SUCCESS
#>
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"

    # Write to log file if initialized
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $logLine -ErrorAction SilentlyContinue
    }

    # Write to console with color based on level
    $color = switch ($Level) {
        "INFO"    { "White" }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red" }
        "DEBUG"   { "DarkGray" }
        "SUCCESS" { "Green" }
        default   { "White" }
    }

    # Only show DEBUG messages if verbose
    if ($Level -ne "DEBUG") {
        Write-Host "  $Message" -ForegroundColor $color
    }
}
#endregion

#region Validation Functions
<#
.SYNOPSIS
    Checks all prerequisites are met before launching.
.DESCRIPTION
    Verifies Claude CLI, Windows Terminal, and PowerShell version.
.OUTPUTS
    Returns $true if all prerequisites pass, $false otherwise.
#>
function Test-Prerequisites {
    $allPassed = $true

    Write-Log "Checking prerequisites..." "INFO"

    # Check PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -lt 7) {
        Write-Log "PowerShell 7+ required (current: $psVersion). Install: winget install Microsoft.PowerShell" "ERROR"
        $allPassed = $false
    } else {
        Write-Log "PowerShell version: $psVersion" "DEBUG"
    }

    # Check Claude CLI
    $claudePath = (Get-Command "claude" -ErrorAction SilentlyContinue).Source
    if (-not $claudePath) {
        Write-Log "Claude CLI not found. Install from: https://claude.ai/code" "ERROR"
        $allPassed = $false
    } else {
        Write-Log "Claude CLI found: $claudePath" "DEBUG"
    }

    # Check Windows Terminal
    $wtPath = (Get-Command "wt" -ErrorAction SilentlyContinue).Source
    if (-not $wtPath) {
        Write-Log "Windows Terminal not found. Install: winget install Microsoft.WindowsTerminal" "ERROR"
        $allPassed = $false
    } else {
        Write-Log "Windows Terminal found: $wtPath" "DEBUG"
    }

    return $allPassed
}

<#
.SYNOPSIS
    Validates configuration values.
.PARAMETER Config
    The configuration hashtable to validate.
.OUTPUTS
    Returns an array of error messages (empty if valid).
#>
function Test-Configuration {
    param($Config)

    $errors = @()

    # Validate instanceCount (1-12)
    if ($Config.InstanceCount -lt 1 -or $Config.InstanceCount -gt 12) {
        $errors += "instanceCount must be between 1 and 12 (got: $($Config.InstanceCount))"
    }

    # Validate arrangement
    $validArrangements = @("grid", "horizontal", "vertical")
    if ($Config.Arrangement -notin $validArrangements) {
        $errors += "arrangement must be one of: $($validArrangements -join ', ') (got: $($Config.Arrangement))"
    }

    # Validate targetMonitor
    $target = $Config.TargetMonitor
    if ($target -ne "primary" -and $target -ne "all") {
        if ($target -is [int] -or $target -match '^\d+$') {
            $monitorNum = [int]$target
            $screenCount = [System.Windows.Forms.Screen]::AllScreens.Count
            if ($monitorNum -lt 1 -or $monitorNum -gt $screenCount) {
                $errors += "targetMonitor $monitorNum is invalid. Available monitors: 1-$screenCount"
            }
        } else {
            $errors += "targetMonitor must be 'primary', 'all', or a positive integer (got: $target)"
        }
    }

    # Validate launchDelay (>= 0)
    if ($Config.LaunchDelay -lt 0) {
        $errors += "launchDelay must be >= 0 (got: $($Config.LaunchDelay))"
    }

    # Validate padding (>= 0)
    if ($Config.Padding -lt 0) {
        $errors += "padding must be >= 0 (got: $($Config.Padding))"
    }

    # Validate windowGap (>= 0)
    if ($Config.WindowGap -lt 0) {
        $errors += "windowGap must be >= 0 (got: $($Config.WindowGap))"
    }

    # Validate colors (array of hex colors)
    if ($Config.Colors) {
        foreach ($color in $Config.Colors) {
            if ($color -notmatch '^#[0-9A-Fa-f]{6}$') {
                $errors += "Invalid color format: $color (expected #RRGGBB)"
            }
        }
    }

    # Validate instances array if provided
    if ($Config.Instances) {
        for ($i = 0; $i -lt $Config.Instances.Count; $i++) {
            $inst = $Config.Instances[$i]
            if ($inst.workingDir -and -not (Test-Path $inst.workingDir)) {
                $errors += "Instance $($i + 1) workingDir does not exist: $($inst.workingDir)"
            }
            if ($inst.color -and $inst.color -notmatch '^#[0-9A-Fa-f]{6}$') {
                $errors += "Instance $($i + 1) has invalid color: $($inst.color)"
            }
        }
    }

    return $errors
}
#endregion

#region Configuration Functions
<#
.SYNOPSIS
    Loads a preset configuration from the presets folder.
.PARAMETER PresetName
    The name of the preset (without .json extension).
.OUTPUTS
    Returns the preset configuration hashtable or $null if not found.
#>
function Get-Preset {
    param([string]$PresetName)

    $presetPath = Join-Path $script:ScriptDir "presets\$PresetName.json"

    if (-not (Test-Path $presetPath)) {
        Write-Log "Preset not found: $presetPath" "WARN"
        return $null
    }

    try {
        $preset = Get-Content $presetPath -Raw | ConvertFrom-Json
        Write-Log "Loaded preset: $($preset.name) - $($preset.description)" "INFO"
        return $preset
    }
    catch {
        Write-Log "Failed to parse preset $PresetName`: $_" "ERROR"
        return $null
    }
}

<#
.SYNOPSIS
    Loads and merges configuration from config.json, presets, and defaults.
.OUTPUTS
    Returns the merged configuration hashtable.
#>
function Get-Configuration {
    $Config = $DefaultConfig.Clone()
    $ConfigPath = Join-Path $script:ScriptDir "config.json"

    if (Test-Path $ConfigPath) {
        try {
            $jsonConfig = Get-Content $ConfigPath -Raw | ConvertFrom-Json

            # Check for preset first
            if ($jsonConfig.preset) {
                $preset = Get-Preset $jsonConfig.preset
                if ($preset) {
                    # Apply preset values
                    if ($null -ne $preset.instanceCount) { $Config.InstanceCount = $preset.instanceCount }
                    if ($null -ne $preset.dangerouslySkipPermissions) { $Config.DangerouslySkipPermissions = $preset.dangerouslySkipPermissions }
                    if ($null -ne $preset.arrangement) { $Config.Arrangement = $preset.arrangement }
                    if ($null -ne $preset.targetMonitor) { $Config.TargetMonitor = $preset.targetMonitor }
                    if ($null -ne $preset.launchDelay) { $Config.LaunchDelay = $preset.launchDelay }
                    if ($null -ne $preset.padding) { $Config.Padding = $preset.padding }
                    if ($null -ne $preset.windowGap) { $Config.WindowGap = $preset.windowGap }
                    if ($null -ne $preset.titlePrefix) { $Config.TitlePrefix = $preset.titlePrefix }
                    if ($null -ne $preset.additionalArgs) { $Config.AdditionalArgs = $preset.additionalArgs }
                    if ($null -ne $preset.colors) { $Config.Colors = @($preset.colors) }
                }
            }

            # Apply config.json values (override preset)
            if ($null -ne $jsonConfig.instanceCount) { $Config.InstanceCount = $jsonConfig.instanceCount }
            if ($null -ne $jsonConfig.dangerouslySkipPermissions) { $Config.DangerouslySkipPermissions = $jsonConfig.dangerouslySkipPermissions }
            if ($null -ne $jsonConfig.arrangement) { $Config.Arrangement = $jsonConfig.arrangement }
            if ($null -ne $jsonConfig.targetMonitor) { $Config.TargetMonitor = $jsonConfig.targetMonitor }
            if ($null -ne $jsonConfig.launchDelay) { $Config.LaunchDelay = $jsonConfig.launchDelay }
            if ($null -ne $jsonConfig.padding) { $Config.Padding = $jsonConfig.padding }
            if ($null -ne $jsonConfig.windowGap) { $Config.WindowGap = $jsonConfig.windowGap }
            if ($null -ne $jsonConfig.titlePrefix) { $Config.TitlePrefix = $jsonConfig.titlePrefix }
            if ($null -ne $jsonConfig.additionalArgs) { $Config.AdditionalArgs = $jsonConfig.additionalArgs }
            if ($null -ne $jsonConfig.colors) { $Config.Colors = @($jsonConfig.colors) }
            if ($null -ne $jsonConfig.keepLauncherOpen) { $Config.KeepLauncherOpen = $jsonConfig.keepLauncherOpen }
            if ($null -ne $jsonConfig.instances) { $Config.Instances = @($jsonConfig.instances) }

            Write-Log "Loaded config from: config.json" "DEBUG"
        }
        catch {
            Write-Log "Could not parse config.json, using defaults: $_" "WARN"
        }
    }

    return $Config
}

<#
.SYNOPSIS
    Gets configuration for a specific instance.
.PARAMETER Config
    The main configuration hashtable.
.PARAMETER Index
    Zero-based instance index.
.PARAMETER ProjectDir
    Default project directory.
.OUTPUTS
    Returns hashtable with title, workingDir, additionalArgs, and color.
#>
function Get-InstanceConfig {
    param($Config, [int]$Index, [string]$ProjectDir)

    $num = $Index + 1
    $instanceConfig = @{
        Title = "$($Config.TitlePrefix) $num"
        WorkingDir = $ProjectDir
        AdditionalArgs = $Config.AdditionalArgs
        Color = $Config.Colors[$Index % $Config.Colors.Count]
    }

    # Override with per-instance settings if available
    if ($Config.Instances -and $Index -lt $Config.Instances.Count) {
        $inst = $Config.Instances[$Index]
        if ($inst.title) { $instanceConfig.Title = $inst.title }
        if ($inst.workingDir) { $instanceConfig.WorkingDir = $inst.workingDir }
        if ($inst.additionalArgs) { $instanceConfig.AdditionalArgs = $inst.additionalArgs }
        if ($inst.color) { $instanceConfig.Color = $inst.color }
    }

    return $instanceConfig
}
#endregion

#region Monitor Functions
<#
.SYNOPSIS
    Gets the bounds of the primary monitor's working area.
.OUTPUTS
    Returns hashtable with X, Y, Width, Height.
#>
function Get-PrimaryMonitorBounds {
    $primary = [System.Windows.Forms.Screen]::PrimaryScreen
    return @{
        X = $primary.WorkingArea.X
        Y = $primary.WorkingArea.Y
        Width = $primary.WorkingArea.Width
        Height = $primary.WorkingArea.Height
        Name = "Primary"
    }
}

<#
.SYNOPSIS
    Gets the bounds for the target monitor based on configuration.
.PARAMETER Target
    The target: "primary", "all", or monitor number (1, 2, 3...).
.OUTPUTS
    Returns hashtable with X, Y, Width, Height.
#>
function Get-TargetMonitorBounds {
    param($Target)

    $screens = [System.Windows.Forms.Screen]::AllScreens

    switch ($Target) {
        "primary" {
            return Get-PrimaryMonitorBounds
        }
        "all" {
            # Calculate bounding box of all monitors
            $minX = [int]::MaxValue
            $minY = [int]::MaxValue
            $maxX = [int]::MinValue
            $maxY = [int]::MinValue

            foreach ($screen in $screens) {
                $wa = $screen.WorkingArea
                if ($wa.X -lt $minX) { $minX = $wa.X }
                if ($wa.Y -lt $minY) { $minY = $wa.Y }
                if (($wa.X + $wa.Width) -gt $maxX) { $maxX = $wa.X + $wa.Width }
                if (($wa.Y + $wa.Height) -gt $maxY) { $maxY = $wa.Y + $wa.Height }
            }

            return @{
                X = $minX
                Y = $minY
                Width = $maxX - $minX
                Height = $maxY - $minY
                Name = "All Monitors"
            }
        }
        default {
            # Numeric index - return specific monitor
            $index = [int]$Target - 1
            if ($index -ge 0 -and $index -lt $screens.Count) {
                $screen = $screens[$index]
                return @{
                    X = $screen.WorkingArea.X
                    Y = $screen.WorkingArea.Y
                    Width = $screen.WorkingArea.Width
                    Height = $screen.WorkingArea.Height
                    Name = "Monitor $Target"
                }
            }

            # Fallback to primary
            Write-Log "Invalid monitor index $Target, using primary" "WARN"
            return Get-PrimaryMonitorBounds
        }
    }
}
#endregion

#region Window Management Functions
<#
.SYNOPSIS
    Calculates window positions based on count, bounds, and arrangement.
.PARAMETER Count
    Number of windows.
.PARAMETER Bounds
    Monitor bounds hashtable.
.PARAMETER Arrangement
    Layout type: grid, horizontal, vertical.
.PARAMETER Padding
    Edge padding in pixels.
.PARAMETER Gap
    Gap between windows in pixels.
.OUTPUTS
    Returns array of position hashtables with X, Y, Width, Height.
#>
function Get-WindowPositions {
    param($Count, $Bounds, $Arrangement, $Padding, $Gap)

    # Calculate available space with padding
    $availWidth = $Bounds.Width - (2 * $Padding)
    $availHeight = $Bounds.Height - (2 * $Padding)
    $startX = $Bounds.X + $Padding
    $startY = $Bounds.Y + $Padding

    # Determine grid layout
    if ($Arrangement -eq "horizontal") {
        $cols = $Count
        $rows = 1
    }
    elseif ($Arrangement -eq "vertical") {
        $cols = 1
        $rows = $Count
    }
    else {
        # Grid layout - find best fit
        $sqrt = [Math]::Sqrt($Count)
        $cols = [Math]::Ceiling($sqrt)
        $rows = [Math]::Ceiling($Count / $cols)

        # Prefer wider layouts for widescreen monitors
        if ($availWidth -gt $availHeight) {
            if ($rows -gt $cols) {
                $temp = $cols
                $cols = $rows
                $rows = $temp
            }
        }
    }

    # Calculate window size accounting for gaps
    $totalGapWidth = ($cols - 1) * $Gap
    $totalGapHeight = ($rows - 1) * $Gap
    $windowWidth = [Math]::Floor(($availWidth - $totalGapWidth) / $cols)
    $windowHeight = [Math]::Floor(($availHeight - $totalGapHeight) / $rows)

    Write-Log "Grid: ${cols}x${rows}, Window size: ${windowWidth}x${windowHeight}" "DEBUG"

    $positions = @()
    for ($i = 0; $i -lt $Count; $i++) {
        $col = $i % $cols
        $row = [Math]::Floor($i / $cols)

        $x = $startX + ($col * ($windowWidth + $Gap))
        $y = $startY + ($row * ($windowHeight + $Gap))

        $positions += @{
            X = [int]$x
            Y = [int]$y
            Width = [int]$windowWidth
            Height = [int]$windowHeight
        }
    }
    return $positions
}

<#
.SYNOPSIS
    Moves a window with retry logic.
.PARAMETER Hwnd
    Window handle.
.PARAMETER Position
    Position hashtable with X, Y, Width, Height.
.PARAMETER MaxRetries
    Maximum retry attempts.
.OUTPUTS
    Returns $true if successful, $false otherwise.
#>
function Move-WindowWithRetry {
    param(
        [IntPtr]$Hwnd,
        $Position,
        [int]$MaxRetries = 3
    )

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        $result = [WindowManager]::MoveWindow(
            $Hwnd,
            $Position.X,
            $Position.Y,
            $Position.Width,
            $Position.Height,
            $true
        )

        if ($result) {
            return $true
        }

        Write-Log "Move attempt $attempt failed, retrying..." "DEBUG"
        Start-Sleep -Milliseconds 500
    }

    return $false
}
#endregion

#region Display Functions
<#
.SYNOPSIS
    Displays the Claude Squad banner.
#>
function Show-Banner {
    $banner = @"

   `e[96m+===============================================================+
   |                                                               |
   |     `e[97m######  ##       ###    ##   ## #####   ######`e[96m            |
   |    `e[97m##      ##      ## ##   ##   ## ##   ## ##`e[96m                 |
   |    `e[97m##      ##     ##   ##  ##   ## ##   ## #####`e[96m              |
   |    `e[97m##      ##     #######  ##   ## ##   ## ##`e[96m                 |
   |    `e[97m######  ###### ##   ##  ######  #####   ######`e[96m            |
   |                                                               |
   |              `e[93m###### ######  ##   ##  ###    #####`e[96m              |
   |              `e[93m##     ##  ##  ##   ## ## ##   ##   ##`e[96m            |
   |              `e[93m###### ##  ##  ##   ## #####   ##   ##`e[96m            |
   |              `e[93m    ## ## ##   ##   ## ##  ##  ##   ##`e[96m            |
   |              `e[93m###### #####   ######  ##   ## #####`e[96m             |
   |                                                               |
   +===============================================================+`e[0m

"@
    Write-Host $banner
}

<#
.SYNOPSIS
    Displays the current configuration summary.
.PARAMETER Config
    Configuration hashtable.
.PARAMETER Bounds
    Monitor bounds hashtable.
.PARAMETER ProjectDir
    Project directory path.
#>
function Show-Configuration {
    param($Config, $Bounds, $ProjectDir)

    Write-Host "  `e[93mConfiguration:`e[0m"
    Write-Host "  `e[90m-----------------------------------------------------`e[0m"
    Write-Host "    Instances:        `e[97m$($Config.InstanceCount)`e[0m"
    Write-Host -NoNewline "    Skip Permissions: "
    if ($Config.DangerouslySkipPermissions) {
        Write-Host "`e[91mYes (DANGEROUS MODE)`e[0m"
    } else {
        Write-Host "`e[92mNo (Safe Mode)`e[0m"
    }
    Write-Host "    Arrangement:      `e[97m$($Config.Arrangement)`e[0m"
    Write-Host "    Target Monitor:   `e[97m$($Bounds.Name)`e[0m"
    Write-Host "    Project:          `e[96m$ProjectDir`e[0m"
    if ($Config.Instances) {
        Write-Host "    Per-Instance:     `e[97m$($Config.Instances.Count) custom configs`e[0m"
    }
    Write-Host ""
    Write-Host "  `e[93mMonitor Bounds:`e[0m"
    Write-Host "    Working Area:     `e[97m$($Bounds.Width) x $($Bounds.Height)`e[0m"
    Write-Host "    Position:         `e[97m($($Bounds.X), $($Bounds.Y))`e[0m"
    Write-Host ""
}

<#
.SYNOPSIS
    Displays the launch summary with success/failure counts.
.PARAMETER Positioned
    Number of successfully positioned windows.
.PARAMETER Total
    Total number of windows attempted.
.PARAMETER ProcessStatus
    Array of process status objects.
#>
function Show-Summary {
    param([int]$Positioned, [int]$Total, $ProcessStatus)

    Write-Host ""
    Write-Host "  `e[96m======================================================`e[0m"

    if ($Positioned -eq $Total) {
        Write-Host "  `e[92mAll $Positioned instances positioned! Happy coding!`e[0m"
    } else {
        Write-Host "  `e[93mPositioned $Positioned of $Total instances`e[0m"
        $failed = $Total - $Positioned
        Write-Host "  `e[91m$failed instance(s) could not be positioned`e[0m"
    }

    # Show process health status
    if ($ProcessStatus -and $ProcessStatus.Count -gt 0) {
        Write-Host ""
        Write-Host "  `e[93mProcess Status:`e[0m"
        foreach ($status in $ProcessStatus) {
            $icon = if ($status.Running) { "`e[92m*`e[0m" } else { "`e[91mX`e[0m" }
            Write-Host "    $icon $($status.Title)"
        }
    }

    Write-Host "  `e[96m======================================================`e[0m"
    Write-Host ""
}
#endregion

#region Process Health Functions
<#
.SYNOPSIS
    Verifies a process is still running.
.PARAMETER ProcessId
    The process ID to check.
.OUTPUTS
    Returns $true if running, $false otherwise.
#>
function Test-ProcessRunning {
    param([int]$ProcessId)

    try {
        $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        return ($null -ne $process)
    }
    catch {
        return $false
    }
}

<#
.SYNOPSIS
    Gets the health status of all launched processes.
.OUTPUTS
    Returns array of status objects with Title, PID, and Running.
#>
function Get-ProcessHealthStatus {
    $status = @()

    foreach ($proc in $script:LaunchedProcesses) {
        $running = Test-ProcessRunning $proc.PID
        $status += @{
            Title = $proc.Title
            PID = $proc.PID
            Running = $running
        }
    }

    return $status
}
#endregion

#region Main Entry Point
<#
.SYNOPSIS
    Main entry point for Claude Squad.
.DESCRIPTION
    Orchestrates the entire launch process: validation, configuration,
    launching instances, and positioning windows.
#>
function Start-ClaudeSquad {
    param([string]$ProjectDirArg)

    # Clear screen and show banner
    Clear-Host
    Show-Banner

    # Initialize logging
    Initialize-Logging

    # Run pre-flight checks
    Write-Host "  `e[93mPre-flight checks...`e[0m"
    Write-Host ""

    if (-not (Test-Prerequisites)) {
        Write-Host ""
        Write-Log "Pre-flight checks failed. Please resolve the issues above." "ERROR"
        Write-Host ""
        Write-Host "  `e[90mPress any key to exit...`e[0m"
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }

    Write-Log "Pre-flight checks passed" "SUCCESS"
    Write-Host ""

    # Load configuration
    $Config = Get-Configuration

    # Validate configuration
    $configErrors = Test-Configuration $Config
    if ($configErrors.Count -gt 0) {
        Write-Host ""
        Write-Log "Configuration errors:" "ERROR"
        foreach ($err in $configErrors) {
            Write-Log "  - $err" "ERROR"
        }
        Write-Host ""
        Write-Host "  `e[90mPress any key to exit...`e[0m"
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }

    Write-Log "Configuration validated" "DEBUG"

    # Determine project directory
    $ProjectDir = $script:ScriptDir
    if ($ProjectDirArg -and (Test-Path $ProjectDirArg)) {
        $ProjectDir = Resolve-Path $ProjectDirArg
    }

    # Get target monitor bounds
    $bounds = Get-TargetMonitorBounds $Config.TargetMonitor

    # Display configuration
    Show-Configuration $Config $bounds $ProjectDir

    # Get existing Windows Terminal windows BEFORE launching
    $existingWindows = [WindowManager]::FindWindowTerminalWindows()
    Write-Log "Existing terminal windows: $($existingWindows.Count)" "DEBUG"

    # Calculate window positions
    $positions = Get-WindowPositions -Count $Config.InstanceCount -Bounds $bounds `
        -Arrangement $Config.Arrangement -Padding $Config.Padding -Gap $Config.WindowGap

    Write-Host "  `e[93mLaunching $($Config.InstanceCount) Claude Code instances...`e[0m"
    Write-Host ""

    # Color display mapping
    $colorNames = @{
        "#E74C3C" = "`e[91m"; "#E67E22" = "`e[33m"; "#F1C40F" = "`e[93m"; "#2ECC71" = "`e[92m"
        "#00CED1" = "`e[96m"; "#3498DB" = "`e[94m"; "#9B59B6" = "`e[95m"; "#E91E63" = "`e[91m"
        "#00BCD4" = "`e[96m"; "#8BC34A" = "`e[92m"; "#FF5722" = "`e[33m"; "#607D8B" = "`e[90m"
    }

    # Launch each instance
    $launchedTitles = @()
    for ($i = 0; $i -lt $Config.InstanceCount; $i++) {
        $num = $i + 1
        $instanceConfig = Get-InstanceConfig $Config $i $ProjectDir

        $title = $instanceConfig.Title
        $workDir = $instanceConfig.WorkingDir
        $color = $instanceConfig.Color

        $consoleColor = $colorNames[$color]
        if (-not $consoleColor) { $consoleColor = "`e[97m" }

        Write-Host "    `e[90m[$num]`e[0m ${consoleColor}#`e[0m `e[97m$title`e[0m `e[90m- Launching...`e[0m"
        Write-Log "Launching: $title in $workDir" "DEBUG"

        # Build the claude command
        $claudeCmd = "claude"
        if ($Config.DangerouslySkipPermissions) {
            $claudeCmd += " --dangerously-skip-permissions"
        }
        if ($instanceConfig.AdditionalArgs -and $instanceConfig.AdditionalArgs.Trim()) {
            $claudeCmd += " $($instanceConfig.AdditionalArgs)"
        }

        # Launch Windows Terminal with specific title and color
        $wtArgs = "--title `"$title`" --tabColor `"$color`" -d `"$workDir`" cmd /k `"$claudeCmd`""

        try {
            $process = Start-Process -FilePath "wt" -ArgumentList $wtArgs -PassThru

            if ($process) {
                $script:LaunchedProcesses += @{
                    Title = $title
                    PID = $process.Id
                }
                Write-Log "Process started with PID: $($process.Id)" "DEBUG"
            }
        }
        catch {
            Write-Log "Failed to launch $title`: $_" "ERROR"
        }

        $launchedTitles += $title
        Start-Sleep -Milliseconds $Config.LaunchDelay
    }

    Write-Host ""
    Write-Host "  `e[93mWaiting for windows to initialize...`e[0m"
    Write-Log "Waiting 5 seconds for windows to initialize..." "DEBUG"
    Start-Sleep -Milliseconds 5000

    Write-Host "  `e[93mPositioning windows on $($bounds.Name)...`e[0m"
    Write-Log "Positioning windows..." "INFO"

    # Find all NEW Windows Terminal windows
    $allWindows = [WindowManager]::FindWindowTerminalWindows()
    $newWindows = $allWindows | Where-Object { $_ -notin $existingWindows }

    Write-Log "Found $($newWindows.Count) new terminal windows" "DEBUG"
    Write-Host ""

    # Position windows - try matching by title first
    $positioned = 0
    $usedWindows = @()

    foreach ($title in $launchedTitles) {
        if ($positioned -ge $positions.Count) { break }
        $pos = $positions[$positioned]

        # Find window with this title (with retry)
        $found = $false
        $retryCount = 0
        $maxRetries = 3

        while (-not $found -and $retryCount -lt $maxRetries) {
            foreach ($hwnd in $newWindows) {
                if ($hwnd -in $usedWindows) { continue }

                $windowTitle = [WindowManager]::GetWindowTitle($hwnd)
                if ($windowTitle -like "*$title*") {
                    $moveResult = Move-WindowWithRetry $hwnd $pos

                    if ($moveResult) {
                        Write-Host "    `e[92m*`e[0m Positioned: $title at ($($pos.X), $($pos.Y)) size $($pos.Width)x$($pos.Height)"
                        Write-Log "Positioned: $title at ($($pos.X), $($pos.Y))" "SUCCESS"
                        $usedWindows += $hwnd
                        $found = $true
                        $positioned++
                        break
                    } else {
                        Write-Log "Failed to move window: $title" "WARN"
                    }
                }
            }

            if (-not $found) {
                $retryCount++
                if ($retryCount -lt $maxRetries) {
                    Write-Log "Window not found for '$title', retry $retryCount of $maxRetries..." "DEBUG"
                    Start-Sleep -Milliseconds 1000
                    # Refresh window list
                    $allWindows = [WindowManager]::FindWindowTerminalWindows()
                    $newWindows = $allWindows | Where-Object { $_ -notin $existingWindows }
                }
            }
        }

        if (-not $found) {
            Write-Host "    `e[91mX`e[0m Could not find: $title"
            Write-Log "Could not find window: $title" "WARN"
        }
    }

    # Fallback: position any remaining new windows in order
    if ($positioned -lt $newWindows.Count -and $positioned -lt $positions.Count) {
        Write-Host ""
        Write-Host "  `e[93mPositioning remaining windows...`e[0m"
        Write-Log "Positioning remaining unmatched windows..." "DEBUG"

        foreach ($hwnd in $newWindows) {
            if ($hwnd -in $usedWindows) { continue }
            if ($positioned -ge $positions.Count) { break }

            $pos = $positions[$positioned]
            $moveResult = Move-WindowWithRetry $hwnd $pos

            if ($moveResult) {
                $windowTitle = [WindowManager]::GetWindowTitle($hwnd)
                Write-Host "    `e[92m*`e[0m Positioned: $windowTitle"
                Write-Log "Positioned fallback: $windowTitle" "DEBUG"
                $usedWindows += $hwnd
                $positioned++
            }
        }
    }

    # Get process health status
    $processStatus = Get-ProcessHealthStatus

    # Show summary
    Show-Summary $positioned $Config.InstanceCount $processStatus

    Write-Log "Claude Squad finished. Positioned $positioned of $($Config.InstanceCount) windows." "INFO"

    # Handle keep open option
    if ($Config.KeepLauncherOpen) {
        Write-Host "  `e[93mMonitoring mode enabled. Press Ctrl+C to exit.`e[0m"
        Write-Host ""

        while ($true) {
            Start-Sleep -Seconds 10
            $status = Get-ProcessHealthStatus
            $running = ($status | Where-Object { $_.Running }).Count
            $total = $status.Count

            if ($running -lt $total) {
                Write-Log "Process health check: $running of $total still running" "WARN"
            }
        }
    } else {
        Write-Host "  `e[90mPress any key to close this launcher...`e[0m"
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}
#endregion

#region Script Execution
# Determine project directory from arguments
$ProjectDirArg = $null
if ($args.Count -gt 0 -and (Test-Path $args[0])) {
    $ProjectDirArg = $args[0]
}

# Start Claude Squad
Start-ClaudeSquad $ProjectDirArg
#endregion
