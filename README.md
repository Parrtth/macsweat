<p align="center"><img src="site/assets/icon.png" width="112" height="112" alt="MacSweat icon: a nervous face with a bead of sweat"></p>

<h1 align="center">MacSweat</h1>

<p align="center">
  <b>Why is your Mac sweating?</b><br>
  A free Mac menu bar app that names what's heating up or slowing down your Mac, so you can close it yourself.
</p>

<p align="center">
  <a href="https://macsweat.parthh.dev">Website</a> ·
  <a href="https://github.com/Parrtth/macsweat/releases/latest">Latest release</a> ·
  Mac only · macOS 13 or later ·
  <a href="LICENSE">MIT</a>
</p>

<p align="center">
  <img src="site/assets/screenshot-dark.png#gh-dark-mode-only" width="380" alt="The MacSweat panel: a verdict line, tiles for CPU, memory and heat, background tasks, and apps sorted by CPU">
  <img src="site/assets/screenshot-light.png#gh-light-mode-only" width="380" alt="The MacSweat panel: a verdict line, tiles for CPU, memory and heat, background tasks, and apps sorted by CPU">
</p>

## Install

Paste this into Terminal:

```sh
curl -fsSL https://macsweat.parthh.dev/install | sh
```

It downloads the latest release from GitHub, checks its SHA-256, installs MacSweat to Applications and opens it. Then look for the small sweating face in your menu bar. You can [read the script](site/install) first.

**Update:** run the install command again.

**Uninstall:**

```sh
curl -fsSL https://macsweat.parthh.dev/uninstall | sh
```

MacSweat is for Macs only, running macOS 13 Ventura or later on Apple silicon or Intel. It doesn't run on Windows or Linux.

## What it does

Click the icon and MacSweat shows you four things.

1. **The culprit.** One sentence names what's using the most CPU and memory, such as "Next.js dev server is using the most CPU (386%)". A dot beside it turns green, orange or red, and three tiles show CPU, memory and heat.
2. **Apps without the helper soup.** Chrome's 25 helpers count as Chrome. macOS services get plain names like "Spotlight indexing" and "iCloud sync". Sort the list by CPU or by memory.
3. **What you forgot.** Dev servers and scripts left running (Node.js, Next.js, Vite, Python, PostgreSQL and others), grouped by project, with how long each has been up.
4. **A way to close it.** Hover a row for **Quit** (apps) or **Stop** (dev tasks). MacSweat asks first, and it never closes anything by itself.

## Private and light

- Everything is read on your Mac. There's no account, no analytics and no tracking.
- The only network request is the optional **Check for Updates…** menu item, which asks GitHub for the latest version number.
- It refreshes every 3 seconds while its panel is open. While closed, it checks overall CPU and memory every 5 seconds and the full process list every 30.

## Questions

<details>
<summary><b>Can I download it instead of using Terminal?</b></summary>
<br>

Yes. Download [MacSweat.zip](https://github.com/Parrtth/macsweat/releases/latest/download/MacSweat.zip), then move MacSweat to Applications. MacSweat is free and isn't notarized by Apple, which needs a $99-a-year developer account, so macOS blocks it the first time you open it. Go to System Settings › Privacy & Security and click **Open Anyway**.

The install command skips that step, and it's short enough to read before you run it.

</details>

<details>
<summary><b>I don't see the icon in my menu bar.</b></summary>
<br>

On macOS 26 and later, allow MacSweat in System Settings ▸ Menu Bar. On a MacBook with a crowded menu bar, the notch can also hide icons; quit another menu bar app to make room.

</details>

<details>
<summary><b>Which browser tab is the heavy one?</b></summary>
<br>

A browser shows as one row, because the browser decides which tab runs in which process. Right-click the row and choose **Find Heavy Tabs…** for the steps: in Chrome, Edge and Brave it's Window ▸ Task Manager.

</details>

<details>
<summary><b>Why don't the numbers match Activity Monitor exactly?</b></summary>
<br>

- CPU uses Activity Monitor's scale, where 100% is one full core. An app's row adds up its helpers, so it can be higher than any single line in Activity Monitor.
- The Memory tile is Activity Monitor's "Memory Used".
- Memory for system services such as WindowServer is an estimate. macOS gives the exact figure only to Activity Monitor.
- `kernel_task` isn't listed, because macOS doesn't expose it to regular apps. The Heat tile is the better signal for thermal slowdowns.

</details>

## Build it yourself

```sh
./build.sh --install
```

That builds a universal app, copies it to Applications and opens it. Flags, the release steps and notes for contributors are in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## License

[MIT](LICENSE) © 2026 Parth
