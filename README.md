# Claude Squad

A Windows multi-terminal launcher for Claude Code instances. Launch multiple Claude Code windows in a perfectly arranged grid with one click.

```
   ╔═══════════════════════════════════════════════════════════════╗
   ║     ██████╗██╗      █████╗ ██╗   ██╗██████╗ ███████╗          ║
   ║    ██╔════╝██║     ██╔══██╗██║   ██║██╔══██╗██╔════╝          ║
   ║    ██║     ██║     ███████║██║   ██║██║  ██║█████╗            ║
   ║    ██║     ██║     ██╔══██║██║   ██║██║  ██║██╔══╝            ║
   ║    ╚██████╗███████╗██║  ██║╚██████╔╝██████╔╝███████╗          ║
   ║     ╚═════╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝          ║
   ║              ███████╗ ██████╗ ██╗   ██╗ █████╗ ██████╗        ║
   ║              ██╔════╝██╔═══██╗██║   ██║██╔══██╗██╔══██╗       ║
   ║              ███████╗██║   ██║██║   ██║███████║██║  ██║       ║
   ║              ╚════██║██║▄▄ ██║██║   ██║██╔══██║██║  ██║       ║
   ║              ███████║╚██████╔╝╚██████╔╝██║  ██║██████╔╝       ║
   ║              ╚══════╝ ╚══▀▀═╝  ╚═════╝ ╚═╝  ╚═╝╚═════╝        ║
   ╚═══════════════════════════════════════════════════════════════╝
```

## Features

- **One-Click Launch**: Double-click `Launch.bat` to spawn multiple Claude Code instances
- **Auto-Arrangement**: Windows automatically tile in a grid, horizontal, or vertical layout
- **Multi-Monitor Support**: Target specific monitors or span across all displays
- **Per-Instance Config**: Different colors, working directories, and arguments per window
- **Layout Presets**: Save and load window arrangements for different workflows
- **Color-Coded Tabs**: Each instance gets a unique tab color for easy identification
- **DPI-Aware**: Properly handles high-DPI displays
- **Persistent Logging**: All operations logged to timestamped files with auto-cleanup

## Requirements

- **Windows 10/11**
- **PowerShell 7+** (pwsh.exe) - [Install here](https://aka.ms/powershell)
- **Windows Terminal** - [Install from Microsoft Store](https://aka.ms/terminal)
- **Claude CLI** - [Install from Anthropic](https://claude.ai/code)

## Quick Start

1. Copy the `claude-squad` folder to your project directory
2. Edit `config.json` to customize settings (optional)
3. Double-click `Launch.bat`
4. Watch your Claude Code army deploy!

## CLI Usage

Launch with command-line options for quick preset switching:

```batch
Launch.bat --preset <name>
```

### Examples

```batch
# Launch with fullstack preset (4 instances for frontend/backend/api/tests)
Launch.bat --preset fullstack

# Launch with focused preset (2 horizontal instances)
Launch.bat --preset focused

# Launch single instance
Launch.bat --preset solo

# Launch with research preset
Launch.bat --preset research
```

### Available Presets

| Preset | Instances | Layout | Description |
|--------|-----------|--------|-------------|
| `default` | 6 | grid | Standard 6-instance grid layout |
| `fullstack` | 4 | grid | Frontend, Backend, API, and Tests workspaces |
| `research` | 3 | horizontal | Research tasks with Sonnet model |
| `focused` | 2 | horizontal | Main workspace with reference window |
| `solo` | 1 | grid | Single maximized instance |

CLI arguments override `config.json` settings for that session.

## Configuration Reference

Edit `config.json` to customize behavior:

### Basic Settings

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `instanceCount` | number | 6 | Number of windows to launch (1-12) |
| `dangerouslySkipPermissions` | boolean | true | Skip Claude's permission prompts |
| `arrangement` | string | "grid" | Layout: `grid`, `horizontal`, or `vertical` |
| `targetMonitor` | string/number | "primary" | Monitor: `primary`, `all`, or number (1, 2, 3...) |

### Layout Settings

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `padding` | number | 20 | Pixels from screen edges |
| `windowGap` | number | 10 | Pixels between windows |
| `launchDelay` | number | 800 | Milliseconds between launches |

### Appearance

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `titlePrefix` | string | "Claude Code" | Window title prefix |
| `colors` | array | (12 colors) | Hex colors for tab indicators |
| `additionalArgs` | string | "" | Extra CLI arguments (e.g., `--model sonnet`) |

### Advanced Settings

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `preset` | string | null | Load settings from `presets/<name>.json` |
| `keepLauncherOpen` | boolean | false | Keep launcher open to monitor status |
| `instances` | array | null | Per-instance configuration (see below) |

### Per-Instance Configuration

Override settings for individual instances:

```json
{
    "instanceCount": 3,
    "instances": [
        {
            "title": "Frontend",
            "workingDir": "C:/projects/frontend",
            "additionalArgs": "--model sonnet",
            "color": "#3498DB"
        },
        {
            "title": "Backend",
            "workingDir": "C:/projects/backend",
            "additionalArgs": "--model opus",
            "color": "#2ECC71"
        },
        {
            "title": "Tests",
            "workingDir": "C:/projects/tests",
            "color": "#E74C3C"
        }
    ]
}
```

## Layout Presets

Save common configurations as presets in the `presets/` folder:

**presets/research.json**
```json
{
    "name": "Research Squad",
    "description": "3 instances for research tasks",
    "instanceCount": 3,
    "arrangement": "horizontal",
    "additionalArgs": "--model sonnet"
}
```

Load a preset in your config:
```json
{
    "preset": "research"
}
```

## Troubleshooting

### "pwsh.exe not found"
Install PowerShell 7: `winget install Microsoft.PowerShell`

### "claude is not recognized"
Ensure Claude CLI is installed and in your PATH:
```powershell
where.exe claude
```

### "wt is not recognized"
Install Windows Terminal from the Microsoft Store or via winget:
```powershell
winget install Microsoft.WindowsTerminal
```

### Windows don't position correctly
- Increase `launchDelay` to 1500+ for slower systems
- Check `logs/` folder for detailed error information
- Try `arrangement: "horizontal"` to simplify layout

### Some windows fail to launch
- Check the logs in `logs/claude-squad-*.log`
- Verify your `instanceCount` isn't too high (max 12)
- Ensure enough system memory is available

### Multi-monitor issues
- Use `targetMonitor: 1` or `targetMonitor: 2` to specify exact monitor
- Check monitor numbering in Windows Display Settings
- `targetMonitor: "all"` spans windows across all monitors

## File Structure

```
claude-squad/
├── Launch.bat           # Double-click to start (supports --preset arg)
├── claude-squad.ps1     # Main PowerShell script
├── config.json          # Your configuration
├── README.md            # This file
├── logs/                # Auto-created log files
│   └── claude-squad-YYYY-MM-DD_HH-mm-ss.log
└── presets/             # Layout presets
    ├── default.json     # Standard 6-instance grid
    ├── fullstack.json   # 4-instance fullstack dev setup
    ├── research.json    # 3-instance horizontal research
    ├── focused.json     # 2-instance main + reference
    └── solo.json        # Single instance
```

## Logs

Logs are automatically written to the `logs/` directory with timestamps. Files older than 7 days are automatically cleaned up on each launch.

View recent log:
```powershell
Get-Content .\logs\*.log | Select-Object -Last 50
```

## Examples

### Development Setup (6 instances, grid)
```json
{
    "instanceCount": 6,
    "arrangement": "grid",
    "dangerouslySkipPermissions": true
}
```

### Research Setup (3 horizontal)
```json
{
    "instanceCount": 3,
    "arrangement": "horizontal",
    "additionalArgs": "--model sonnet"
}
```

### Multi-Project Setup
```json
{
    "instanceCount": 3,
    "instances": [
        { "title": "API", "workingDir": "C:/dev/api" },
        { "title": "Web", "workingDir": "C:/dev/web" },
        { "title": "Docs", "workingDir": "C:/dev/docs" }
    ]
}
```

### Second Monitor Only
```json
{
    "instanceCount": 4,
    "targetMonitor": 2,
    "arrangement": "grid"
}
```

## License

MIT License - Use freely in your projects.

---

**Happy Coding with your Claude Squad!**
