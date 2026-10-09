# Vivado in Docker, in your browser

Run AMD Vivado (default **2026.1**) on macOS (Apple Silicon and Intel), Windows and Linux. Vivado
runs in an Ubuntu 22.04 container with a small desktop that you open in your web browser. No VM
to set up and no remote machine: everything runs on your own computer.

```bash
./install.sh   # one-time setup (checks your computer, installs Vivado)
vivado start   # then open http://localhost:6080
```

| Your computer                      | How Vivado (x86_64) runs  | Status                       |
|------------------------------------|---------------------------|------------------------------|
| Mac with Apple Silicon (M1–M5)     | Rosetta, via Docker       | Tested                       |
| Mac with Intel                     | Natively                  | Supported                    |
| Windows 10/11 (x64)                | WSL2 + Docker Desktop     | Supported                    |
| Linux x86_64 (Ubuntu, Fedora, …)   | Natively (fastest)        | Supported                    |
| Linux on ARM, Windows on ARM       | QEMU emulation            | Not supported (slow/crashes) |

> This repo contains no AMD software. You download Vivado yourself with your own AMD account, and
> you accept AMD's license terms. Programming a board over USB/JTAG does **not** work from the
> container (see [Notes](#notes)).

**Contents:** [What you need](#what-you-need) · [1. Install Docker](#1-install-docker) ·
[2. Give Docker enough memory and CPUs](#2-give-docker-enough-memory-and-cpus) ·
[3. Run the setup](#3-run-the-setup) · [4. AMD account and download](#4-amd-account-and-download) ·
[5. Install Vivado](#5-install-vivado) · [6. License](#6-license) · [Daily use](#daily-use) ·
[Configuration](#configuration-env) · [Troubleshooting](#troubleshooting) · [Notes](#notes) ·
[License](#license)

---

## What you need

|                  | Minimum           | Recommended                                          |
|------------------|-------------------|------------------------------------------------------|
| Memory (RAM)     | 8 GB for Docker   | 16 GB for Docker (so a computer with 24 GB or more)  |
| CPU cores        | 4                 | All of them                                          |
| Free disk space  | 70 GB             | 100 GB (Vivado for 3 device families is ~60 GB)      |
| Internet         | Downloads ~15–25 GB while installing                     |
| AMD account      | Free: [create one here](https://www.amd.com/en/registration/create-account.html)       |

Computers with 8 GB of RAM work for tiny designs at best. Run `./doctor.sh` any time: it checks all
of this and tells you exactly what to change.

## 1. Install Docker

<details>
<summary><b>macOS (Apple Silicon or Intel)</b></summary>

1. Install **Docker Desktop**: <https://docs.docker.com/desktop/setup/install/mac-install/> (choose
   *Apple Silicon* or *Intel chip*). Open it once and finish its setup.
2. **Apple Silicon only:** Docker Desktop → Settings (gear icon) → **General** → turn on
   **Use Rosetta for x86_64/amd64 emulation on Apple Silicon** → *Apply & restart*.
   Without Rosetta, Docker falls back to QEMU and Vivado crashes. `install.sh` checks this.

Alternatives that also work: [OrbStack](https://orbstack.dev) and
[Colima](https://github.com/abiosoft/colima) (Apple Silicon: `colima start --vm-type vz --vz-rosetta`).
</details>

<details>
<summary><b>Windows 10/11</b></summary>

The scripts run inside **WSL2** (Linux inside Windows). They don't run in PowerShell, CMD or Git Bash.

1. Open **PowerShell as administrator**, run `wsl --install`, restart. This installs Ubuntu. Open
   *Ubuntu* from the Start menu once and create a Linux user.
2. Install **Docker Desktop for Windows**: <https://docs.docker.com/desktop/setup/install/windows-install/>
   (keep *Use WSL 2* selected).
3. Docker Desktop → Settings → **Resources → WSL integration** → turn on **Ubuntu** → *Apply & restart*.
4. Do everything below in the **Ubuntu** terminal, and clone the repo in your Linux home folder
   (`cd ~`), **not** under `/mnt/c/...`: Windows folders are much slower for Vivado.

Your files are then in Windows Explorer at `\\wsl$\Ubuntu\home\<linux-user>\...`.
</details>

<details>
<summary><b>Linux (x86_64)</b></summary>

1. Install **Docker Engine** and the **Compose plugin**: <https://docs.docker.com/engine/install/>
   (pick your distribution; the `docker-compose-plugin` package gives `docker compose`).
2. Let your user use Docker, then log out and back in:
   `sudo usermod -aG docker $USER`
3. Check: `docker run --rm hello-world`

On SELinux distributions (Fedora, RHEL, …), `install.sh` detects SELinux and sets
`SELINUX_RELABEL=1` automatically.
</details>

## 2. Give Docker enough memory and CPUs

Docker only gets part of your computer, and on macOS and Windows the default is often too little for
Vivado. Implementation of a design can easily use 6–10 GB. With too little memory Vivado gets
killed halfway through a run.

**What to set:** memory **16 GB** (at most your RAM minus ~6 GB; 8 GB is the minimum),
**all CPU cores**, and **swap 4 GB or more**. `./doctor.sh` calculates this for your computer.

<details>
<summary><b>Docker Desktop (macOS)</b></summary>

Docker Desktop → Settings (gear icon) → **Resources** → **Advanced**:
*CPU limit* = all, *Memory limit* = 16 GB, *Swap* = 4 GB or more → **Apply & restart**.
</details>

<details>
<summary><b>Windows (WSL2)</b></summary>

With WSL2, Docker Desktop has no memory slider: WSL2 decides, and by default gives Linux half your
RAM. Create or edit the file `C:\Users\<you>\.wslconfig` (e.g. `notepad $env:USERPROFILE\.wslconfig`
in PowerShell):

```ini
[wsl2]
memory=16GB
processors=8
swap=8GB
```

Use your own core count for `processors` (Task Manager → Performance → CPU → *Logical processors*).
Then run `wsl --shutdown` in PowerShell and restart Docker Desktop.
</details>

<details>
<summary><b>OrbStack / Colima (macOS)</b></summary>

- OrbStack → Settings → **System**: memory and CPU limit.
- Colima: `colima stop`, then `colima start --cpu 8 --memory 16` (Apple Silicon: add
  `--vm-type vz --vz-rosetta`).
</details>

<details>
<summary><b>Linux</b></summary>

Nothing to set: Docker Engine can use the whole machine. With little RAM, add swap
([Ubuntu guide](https://help.ubuntu.com/community/SwapFaq)).
</details>

You can also cap how much the **container** may use with `CONTAINER_MEMORY` and `CONTAINER_CPUS`
in `.env` (e.g. to keep your laptop responsive), and how many threads Vivado uses with
`VIVADO_MAX_THREADS`. See [Configuration](#configuration-env).

## 3. Run the setup

```bash
git clone https://github.com/BlommeJan/vivado-docker-for-mac.git vivado-docker
cd vivado-docker
./install.sh
```

`install.sh` is safe to run again at any time; it skips what's already done. The first time it:

1. checks Docker, Rosetta, memory, CPUs, swap and disk (the same report as `./doctor.sh`);
2. creates `.env` (your personal settings, never committed):
   - asks you to **choose a VNC password** (6–8 characters). This is the password for the desktop
     in your browser. It's unrelated to your AMD account.
   - generates a fixed container **MAC address**. Your Vivado license is tied to it (step 6).
   - on Linux, sets your user/group ID so files you create are owned by you;
3. builds the container image (~1.3 GB, a few minutes);
4. offers to install the **`vivado` command** (a link in `~/.local/bin`), so `vivado start`,
   `vivado stop`, … work from any folder and in any shell. Say no if you prefer `./start.sh` etc.;
   you can add it later with `./install.sh --command`;
5. stops and tells you to download the installer (next step).

**Tip, keeping your projects next to it:** clone this repo into the folder where you keep your
FPGA projects and set `WORK_DIR=..` in `.env`. All your projects then show up in Vivado, and this
repo stays separate from them:

```
fpga-projects/
├── vivado-docker/   ← this repo
├── project-x/
├── project-y/
└── project-z/
```

## 4. AMD account and download

1. Create a free AMD account if you don't have one:
   <https://www.amd.com/en/registration/create-account.html>. Confirm your e-mail address.
2. Open the [Vivado download page](https://www.xilinx.com/support/download.html), select version
   **2026.1**, and download:
   **AMD Unified Installer for FPGAs & Adaptive SoCs 2026.1: Linux Self Extracting Web Installer**
   (`FPGAs_AdaptiveSoCs_Unified_SDI_2026.1_…_Lin64.bin`, ~300 MB).
   - Take the **Linux** one, also on a Mac or Windows PC: it runs inside the Linux container.
   - Take **2026.1**, not 2026.1.1. The free license doesn't cover update releases.
   - AMD asks you to sign in and, the first time, to fill in a name/address form (US export rules).
     Fill it in truthfully; students can enter their university.
3. Put the `.bin` in the `installer/` folder of this repo.
   Windows: from Ubuntu, `cp /mnt/c/Users/<you>/Downloads/FPGAs_AdaptiveSoCs_*_Lin64.bin installer/`

## 5. Install Vivado

Run `./install.sh` again, in a normal terminal window (it needs your input):

1. It shows the **install plan**: Vivado with only the device families from `VIVADO_DEVICES`
   (default Artix-7, Zynq-7000, Spartan-7; covers Basys 3, Nexys A7, Arty, PYNQ-Z2, Zybo, …).
   Answer `y`.
2. **AMD login**, in the terminal:
   - `User ID:` type your AMD account **e-mail address**
   - `Password:` type your AMD password. Nothing appears while you type; that's normal. It goes
     straight to AMD's installer and is never saved by these scripts.
   - Wrong login? You can try again. Check that you can log in on amd.com and that you filled in the
     address form from step 4.
3. It asks you to accept AMD's EULA and third-party EULA. Answer `y` to install.
4. It downloads and installs **~60 GB** into `xilinx/`. This takes 30–90+ minutes. Keep the terminal
   open; if it gets interrupted, just run `./install.sh` again.

## 6. License

From 2026.1, **Vivado doesn't start without a license file**, even for the free tier. The free
**Vivado Basic** license covers the 7-series devices (Artix-7, Spartan-7, Zynq-7000, Kintex-7) and
more. It is *node-locked*: tied to one "host ID". Here that is the container's fixed MAC address from
`.env`, not your computer's real one. `install.sh` and `./doctor.sh` print it, without colons,
e.g. `02a1b2c3d4e5`.

1. Go to <https://www.xilinx.com/getlicense> and sign in with your AMD account.
2. On the *Create New Licenses* tab, select the free **Vivado Basic** license and click
   **Generate Node-Locked License**.
3. Add a host:
   - Operating system: **Linux 64-bit**
   - Host ID type: **Ethernet MAC**
   - Host ID value: your host ID from `./doctor.sh` (12 characters, no colons)
4. Finish the steps. You get `Xilinx.lic` by e-mail; you can also download it later from the
   *Manage Licenses* tab.
5. Put `Xilinx.lic` in the `license/` folder. `./doctor.sh` should show
   *License matches host ID*.

Keep `CONTAINER_MAC` in `.env` unchanged from now on. With a new MAC, you'd need a new license.
Back up `.env` and `license/` somewhere safe.

## Daily use

```bash
vivado start     # start the desktop; prints the URL
vivado stop      # stop it (your files, Vivado and the license stay)
vivado restart   # stop, then start
vivado shell     # terminal inside the container; or one command: vivado shell vivado -version
vivado doctor    # check everything; changes nothing
vivado install   # run the setup again (e.g. after updating this repo)
vivado help
```

The `vivado` command works from any folder. Without it (you answered no in `install.sh`, or
another `vivado` is already on your PATH), run the scripts from this folder instead: `./start.sh`,
`./stop.sh`, `./shell.sh`, `./doctor.sh`, `./install.sh`. Wherever this README says `./doctor.sh`
you can type `vivado doctor`, and so on.

1. `vivado start`, then open <http://localhost:6080/vnc.html?autoconnect=1&resize=remote>
2. Enter your VNC password.
3. Double-click **Vivado** on the desktop. It opens in your work folder (`/home/user/lab`).

Copy/paste between your computer and the desktop: use the clipboard panel in noVNC's left sidebar.

**Where your files are.** These are normal folders on your computer, readable while the container
is stopped:

| On your computer    | In the container   | Contents                                         |
|---------------------|--------------------|--------------------------------------------------|
| `WORK_DIR` (`work/`)| `/home/user/lab`   | **Your projects.** Save everything here.         |
| `xilinx/`           | `/tools/Xilinx`    | Vivado itself (~60 GB)                           |
| `installer/`        | `/opt/installer`   | The `.bin` installer + generated install config  |
| `license/`          | `/opt/license`     | `Xilinx.lic`                                     |

Anything saved *elsewhere* in the container (e.g. the desktop or `/tmp`) is lost on `./stop.sh`.

## Configuration (`.env`)

`install.sh` creates `.env` from [`.env.example`](.env.example); `compose.yaml` and every script read
it. After an update of this repo, run `./install.sh` again: it adds new settings to your `.env` and
keeps your values. A variable set in your shell wins over `.env`, e.g. `NOVNC_PORT=6090 ./start.sh`.

| Variable                    | Default                        | Meaning                                                  |
|-----------------------------|--------------------------------|----------------------------------------------------------|
| `VNC_PASSWORD`              | asked by `install.sh`          | Browser desktop password (6–8 characters)                |
| `CONTAINER_MAC`             | generated                      | Fixed MAC = license host ID. Don't change after step 6   |
| `HOST_UID` / `HOST_GID`     | 1000 / your IDs on Linux       | Owner of files written to your folders                   |
| `SELINUX_RELABEL`           | auto (`1` on SELinux)          | Relabel mounted folders for SELinux                      |
| `CONTAINER_MEMORY`          | empty = no limit               | Max memory for the container, e.g. `12g`                 |
| `CONTAINER_CPUS`            | empty = no limit               | Max CPU cores for the container, e.g. `6`                |
| `SHM_SIZE`                  | `2g`                           | Shared memory for the desktop/GUI                        |
| `VIVADO_MAX_THREADS`        | empty = Vivado default (8)     | Threads per Vivado job (1–32)                            |
| `VIVADO_VERSION`            | `2026.1`                       | Version to install and launch; image tag                 |
| `VIVADO_DEVICES`            | `Artix-7,Zynq-7000,Spartan-7`  | Device families to install                               |
| `VIVADO_ROSETTA_WORKAROUND` | `auto`                         | Crash fix for Rosetta: `auto`, `1` (always), `0` (never) |
| `WORK_DIR`                  | `./work`                       | Your projects (use `..` for the tip in step 3)           |
| `XILINX_DIR`                | `./xilinx`                     | Where Vivado is installed (can be another disk)          |
| `INSTALLER_DIR`             | `./installer`                  | `.bin` installer + `install_config.txt`                  |
| `LICENSE_DIR`               | `./license`                    | License files (`*.lic`)                                  |
| `NOVNC_PORT`                | `6080`                         | Browser port                                             |
| `BIND_ADDRESS`              | `127.0.0.1`                    | Only this computer can connect. Keep it.                 |
| `VNC_GEOMETRY`              | `1920x1080`                    | Start resolution (follows your browser window)           |
| `TZ`                        | `Europe/Brussels`              | Time zone in the container                               |
| `VIVADO_COMMAND`            | empty                          | `no` = `install.sh` stops offering the `vivado` command  |
| `COMPOSE_PROJECT_NAME`      | `vivado`                       | Docker Compose project name                              |

- **Change the VNC password:** edit `VNC_PASSWORD` in `.env` (6–8 characters), then `./stop.sh && ./start.sh`.
- **Other device families:** change `VIVADO_DEVICES`, run `./install.sh --reconfig` and check
  `installer/install_config.txt`. This affects new installs only; for an existing one, delete
  `xilinx/` and run `./install.sh` again.
- **After changing** `HOST_UID`, `HOST_GID` or the `Dockerfile`: run `./install.sh` (it rebuilds the image).
- **Memory/CPU/thread settings** take effect after `./stop.sh && ./start.sh`.

## Troubleshooting

Start with `./doctor.sh`: it catches most problems and says what to do.

| Problem | Cause and fix |
|---|---|
| `install.sh` says QEMU instead of Rosetta | Apple Silicon: turn on Rosetta (step 1), *Apply & restart*. |
| Vivado icon shows *No license* / Vivado closes right away | No license, or it's for another host ID. `./doctor.sh` checks this. See step 6. |
| Vivado disappears during synthesis/implementation, or the log says *Killed* / exit code 137 | Out of memory. Give Docker more memory and swap (step 2); close other apps. |
| *Abnormal program termination* / exit code 134 on a Mac with M chip | Rosetta crash. Keep `VIVADO_ROSETTA_WORKAROUND=auto` and Rosetta turned on. |
| Browser: *can't connect* | Is it running (`./start.sh`)? Right port (`NOVNC_PORT`)? |
| *Port 6080 is already used* | Another program uses it: set `NOVNC_PORT=6081` in `.env`. |
| Forgot the VNC password | Set a new one in `.env`, then `./stop.sh && ./start.sh`. |
| AMD login fails in the installer | Check the login on amd.com, confirm your e-mail, fill in the address form from step 4, then `./install.sh` again. |
| Very slow on Windows | The repo is under `/mnt/c/...`. Clone it inside WSL (`~/`). Raise WSL memory (step 2). |
| Linux: *permission denied* on files | Run `./install.sh` again (sets `HOST_UID`/`HOST_GID`), or check SELinux (`SELINUX_RELABEL=1`). |
| Linux: *permission denied* on Docker | `sudo usermod -aG docker $USER`, then log out and in. |
| Windows: *run inside WSL2* | You started a script from Git Bash/PowerShell. Use the Ubuntu (WSL) terminal. |

Logs: `docker compose logs` (container), `~/.cache/vivado/vivado.log` inside the container (GUI
session). Vivado also writes small `vivado_pid*.str` files in the work folder; they're harmless and
in `.gitignore`.

## Notes

- **No USB/JTAG.** Docker can't pass USB devices through on macOS/Windows, so you can't program a
  board from the container. Generate the bitstream here (`.bit`) and program the board from a
  computer with Vivado Lab Edition or Hardware Manager, e.g. a lab PC. On Linux you could add the
  USB device to `compose.yaml`, but that isn't tested.
- **Security.** The desktop only listens on `127.0.0.1`; keep `BIND_ADDRESS` as is. VNC passwords
  are weak by design, so don't expose the port to a network. Never commit `.env` or `license/`
  (both are in `.gitignore`).
- **Rosetta workaround.** Under Rosetta, Vivado 2026.1 crashes without
  `LD_PRELOAD=libudev libselinux libz libgdk-x11-2.0` (from
  [vivado-on-silicon-mac](https://github.com/ichi4096/vivado-on-silicon-mac)). It's applied only to
  Vivado, and only under Rosetta (`VIVADO_ROSETTA_WORKAROUND=auto`).
- **Speed.** Native Linux is fastest. On Apple Silicon, emulation makes Vivado slower but fine
  for small and medium designs (a small Artix-7 design goes from synthesis to bitstream in ~1–2 min).
- **Uninstall:** `./stop.sh`, `docker image rm vivado-desktop:2026.1`, then delete `xilinx/`
  (and the repo folder). Remove the command with `rm ~/.local/bin/vivado`.

## License

The scripts and files in this repository are free software, licensed under the
**GNU General Public License v3.0 or later** (GPL-3.0-or-later); see [`COPYING`](COPYING).
You may use, change and share them. If you share a modified version, it must also be released under
the GPL with its source code, so this project and everything built on it stays open source.

This license covers only this repository. AMD Vivado is proprietary software under AMD's own
license terms, which you accept when you install it. The container downloads Ubuntu and
[noVNC](https://github.com/novnc/noVNC) (MPL-2.0), which keep their own licenses.
