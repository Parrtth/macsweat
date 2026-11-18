# Mac Pulse

A small menu bar app for when the Mac feels hot or slow. Click the pulse icon and see:

- **The verdict.** One line on what's going on, plus the app using the most CPU and the app using the most memory.
- **CPU, memory, memory pressure, swap and heat.** Heat is macOS's thermal state; when it says *Hot*, macOS is slowing down to cool off.
- **Background tasks.** Dev servers and scripts (Node.js, Next.js, Python, PostgreSQL…) grouped by project. Each shows how long it's been running and which app started it, or "running on its own" if nothing did.
- **Apps & processes.** Sorted by CPU or memory. Helpers and XPC services are grouped with their app, the way Activity Monitor attributes them. macOS services get plain-English names, such as "Spotlight indexing" or "iCloud sync".

Hover a row for a **Quit** button (apps) or **Stop** button (dev tasks). Both ask first and quit normally: apps get a regular Quit, tasks get the same signal as Control-C. Right-click a row for more options. Browsers show as one entry; *Find Heavy Tabs…* explains how to see individual tabs.

CPU per row uses Activity Monitor's scale: 100% = one full core.

## Build and install

```sh
./build.sh            # builds build/Mac Pulse.app
./build.sh --install  # also copies it to /Applications and opens it
```

Turn on **Open at Login** from the ⋯ menu in the popover. Opening the app again from Spotlight or Finder while it's running shows the popover.

`build/Mac Pulse.app/Contents/MacOS/MacPulse --check` prints a text reading you can compare against `top` or Activity Monitor.

## Cost

While the popover is closed, Mac Pulse reads the whole-Mac counters every 5 s and the process list every 30 s. While it's open, it refreshes everything every 3 s. Nothing leaves the Mac.

## Limits

- Memory for other users' processes (WindowServer and other system services) is their resident size, marked with ≈. macOS only gives Activity Monitor the exact figure.
- `kernel_task` isn't listed because macOS doesn't expose it to regular apps. The Heat tile is the better signal for thermal slowdowns.
