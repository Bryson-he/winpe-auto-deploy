# WinPE Automated Windows Deployment

A lightweight, fully automated Windows imaging solution using WinPE, a custom HTA progress UI, and a CMD deployment script. No MDT, no SCCM, no server infrastructure required — just a bootable USB and a captured WIM image.

![WinPE Deployment UI](screenshot.png)

---

## Overview

This project provides everything you need to deploy a captured Windows image to bare-metal hardware automatically from a bootable USB drive. It consists of:

- **`startnet.cmd`** — the deployment engine that runs diskpart, DISM, and bcdboot sequentially
- **`deploy.hta`** — a branded HTML Application that displays real-time deployment progress
- **`winpeshl.ini`** — configures WinPE to launch the deployment automatically on boot
- **`partition.txt`** — diskpart script for UEFI/GPT partitioning

The HTA UI and the CMD script communicate via flag files written to the WinPE RAM disk (`X:\`), keeping the two completely decoupled — the CMD does all the work, the HTA just watches and displays progress.

---

## How It Works

```
Boot USB
   └── winpeshl.ini
         ├── wpeinit.exe          (loads WinPE drivers)
         └── startnet.cmd
               ├── Launches deploy.hta (progress UI)
               ├── Finds USB drive containing install.wim
               ├── Runs diskpart    → writes X:\s_step1 / X:\s_step1_done
               ├── Runs DISM        → writes X:\s_step2 / X:\s_step2_done
               ├── Runs bcdboot     → writes X:\s_step3 / X:\s_step3_done
               ├── Writes X:\s_step4_done
               └── wpeutil reboot

deploy.hta (running in parallel)
   └── Polls flag files every 2-3 seconds via JavaScript setTimeout
         └── Updates progress bars and step indicators as each flag appears
```

---

## Requirements

- **Windows ADK** with WinPE add-on installed
  - Download: https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install
- **A captured Windows image** (`install.wim`) — see [Capturing an Image](#capturing-an-image) below
- **USB drive** — minimum 64 GB recommended
- **Rufus** for writing the ISO to USB — https://rufus.ie
- Target hardware must support **UEFI boot** (GPT partition scheme)

---

## Project Structure

```
winpe-deploy/
├── deploy/
│   ├── deploy.hta          # Progress UI (HTA)
│   ├── startnet.cmd        # Deployment engine
│   ├── launch_hta.vbs      # Launches HTA without creating a console window
│   └── partition.txt       # Diskpart UEFI/GPT partition script
└── winpeshl.ini            # WinPE shell configuration
```

---

## Step 1 — Set Up WinPE Working Directory

Open an elevated command prompt with the ADK environment loaded (use the **Deployment and Imaging Tools Environment** shortcut installed with the ADK).

```cmd
copype amd64 C:\WinPE_amd64
```

Add required WinPE optional components:

```cmd
dism /Mount-Image /ImageFile:"C:\WinPE_amd64\media\sources\boot.wim" /Index:1 /MountDir:C:\WinPE_Mount

dism /Add-Package /Image:C:\WinPE_Mount /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-WMI.cab"
dism /Add-Package /Image:C:\WinPE_Mount /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\en-us\WinPE-WMI_en-us.cab"
dism /Add-Package /Image:C:\WinPE_Mount /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-Scripting.cab"
dism /Add-Package /Image:C:\WinPE_Mount /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\en-us\WinPE-Scripting_en-us.cab"
dism /Add-Package /Image:C:\WinPE_Mount /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-HTA.cab"
dism /Add-Package /Image:C:\WinPE_Mount /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\en-us\WinPE-HTA_en-us.cab"

dism /Unmount-Image /MountDir:C:\WinPE_Mount /Commit
```

---

## Step 2 — Capturing an Image

Before you can deploy, you need a captured Windows image (`install.wim`). Start from a fully configured Windows installation.

### 2a — Prepare the Reference Machine

Install and configure Windows on your reference machine exactly as you want it deployed:

- Install all drivers
- Install all required software
- Configure settings, user accounts, wallpapers, etc.
- Do **not** join a domain before capturing (join post-deployment via script if needed)

### 2b — Sysprep the Reference Machine

Sysprep generalises the image so it can be deployed to different hardware and generates unique SIDs on first boot.

Open an elevated command prompt on the reference machine and run:

```cmd
C:\Windows\System32\Sysprep\sysprep.exe /oobe /generalize /shutdown
```

- `/oobe` — boots into Out-of-Box Experience on first deployment
- `/generalize` — removes hardware-specific information and unique identifiers
- `/shutdown` — shuts down after sysprep completes (do not boot back in — this would break the generalisation)

> **Important:** After sysprep shuts the machine down, do not boot it back into Windows. Boot it from your WinPE USB instead.

### 2c — Capture the Image from WinPE

Boot the sysprepped reference machine from your WinPE USB. Once at the WinPE environment, identify your drive letters and run DISM to capture:

```cmd
:: List volumes to confirm drive letters
diskpart
list volume
exit

:: Capture the image (replace C: with your Windows volume letter if different)
dism /Capture-Image ^
  /ImageFile:"D:\sources\install.wim" ^
  /CaptureDir:C:\ ^
  /Name:"Windows 11 Custom Image" ^
  /Description:"Captured on %date%" ^
  /Compress:max ^
  /CheckIntegrity
```

Replace `D:` with the drive letter of your USB drive. The capture will take 15–45 minutes depending on image size and USB speed.

### 2d — Verify the Captured Image

```cmd
dism /Get-ImageInfo /ImageFile:"D:\sources\install.wim"
```

This confirms the image was captured correctly and shows the index number (you'll need this for deployment — usually Index 1).

---

## Step 3 — Place the Image on the USB

Copy your captured `install.wim` to the sources folder of your WinPE working directory:

```cmd
copy "D:\sources\install.wim" "C:\WinPE_amd64\media\sources\install.wim"
```

If an `install.wim` already exists there, replace it.

---

## Step 4 — Copy Deployment Files

Create the deploy folder in the WinPE mount and copy all project files:

```cmd
dism /Mount-Image /ImageFile:"C:\WinPE_amd64\media\sources\boot.wim" /Index:1 /MountDir:C:\WinPE_Mount

mkdir C:\WinPE_Mount\deploy

copy "deploy\deploy.hta"       "C:\WinPE_Mount\deploy\deploy.hta"       /y
copy "deploy\startnet.cmd"     "C:\WinPE_Mount\deploy\startnet.cmd"     /y
copy "deploy\launch_hta.vbs"   "C:\WinPE_Mount\deploy\launch_hta.vbs"   /y
copy "deploy\partition.txt"    "C:\WinPE_Mount\deploy\partition.txt"     /y
copy "winpeshl.ini"            "C:\WinPE_Mount\Windows\System32\winpeshl.ini" /y

dism /Unmount-Image /MountDir:C:\WinPE_Mount /Commit
```

---

## Step 5 — Build the ISO

```cmd
MakeWinPEMedia /ISO C:\WinPE_amd64 "C:\Output\WinPE_Deploy.iso"
```

---

## Step 6 — Write ISO to USB with Rufus

1. Open **Rufus** (https://rufus.ie)
2. Select your USB drive under **Device**
3. Click **SELECT** and choose `WinPE_Deploy.iso`
4. Click **START**
5. When the **Windows User Experience** popup appears, **untick all options** and click **OK**
6. Click **OK** to confirm — this will erase the USB drive
7. Wait for Rufus to show **READY**, then eject the USB

---

## Step 7 — Deploy to Target Hardware

1. Disable **Secure Boot** in the target machine's BIOS (required for WinPE to boot)
2. Insert the deployment USB
3. Boot from the USB (select it from the boot override menu in BIOS)
4. The deployment UI will appear and the process runs automatically
5. When complete, remove the USB — the machine reboots into the deployed Windows image

---

## Customising the Partition Layout

Edit `deploy/partition.txt` to change the partition scheme. The default creates a UEFI/GPT layout:

```
select disk 0
clean
convert gpt
create partition efi size=100
format quick fs=fat32 label=System
assign letter=S
create partition msr size=16
create partition primary
format quick fs=ntfs label=Windows
assign letter=W
exit
```

The deployment script uses drive letters `S:` (EFI) and `W:` (Windows). If you change these, update the `bcdboot` command in `startnet.cmd` accordingly:

```cmd
bcdboot W:\Windows /s S: /f UEFI
```

---

## Updating the Image

When you need to update the deployed image (new software, settings changes, etc.):

1. Boot an already-deployed machine into Windows
2. Make your changes
3. Run Sysprep again:
   ```cmd
   C:\Windows\System32\Sysprep\sysprep.exe /oobe /generalize /shutdown
   ```
4. Boot from the WinPE USB and capture a new `install.wim` (see Step 2c)
5. Replace `C:\WinPE_amd64\media\sources\install.wim` with the new image
6. Rebuild the ISO (Step 5) and rewrite the USB (Step 6)
7. Done — all deployment scripts remain unchanged

---

## How the HTA Progress UI Works

The HTA (`deploy.hta`) is a pure display layer — it makes no shell calls and runs no commands. It works by:

1. Being launched via `wscript.exe //B launch_hta.vbs` from `startnet.cmd` — this avoids creating a new console host window
2. Using a **JavaScript `setTimeout` loop** to poll flag files on `X:\` every 2–3 seconds
3. Updating DOM elements (progress bars, step indicators, status text) as each flag file appears
4. `startnet.cmd` writes flag files at each stage: `X:\s_step1`, `X:\s_step1_done`, `X:\s_step2`, etc.

> **Why JavaScript for the timer?** WinPE's `mshta.exe` uses a legacy IE engine where VBScript `setTimeout` pauses when the HTA window loses focus. JavaScript `setTimeout` continues running regardless — essential for keeping the UI alive while the console is visible.

### Flag File Reference

| File | Written when |
|------|-------------|
| `X:\s_step1` | diskpart starts |
| `X:\s_step1_done` | diskpart completes |
| `X:\s_step2` | DISM starts |
| `X:\s_step2_done` | DISM completes |
| `X:\s_step3` | bcdboot starts |
| `X:\s_step3_done` | bcdboot completes |
| `X:\s_step4_done` | all done, reboot imminent |
| `X:\s_error_usb` | install.wim not found |
| `X:\s_error_part` | diskpart failed |
| `X:\s_error_dism` | DISM failed |
| `X:\s_error_bcd` | bcdboot failed |

---

## Known WinPE Limitations

- **Console windows always visible:** In WinPE (no Explorer shell), any console application spawned from a GUI app ignores window style parameters and creates a visible window. This is why the deployment engine runs in `startnet.cmd` (its own console) rather than being called from the HTA.
- **VBScript `setTimeout` pauses on focus loss:** Use JavaScript timers for anything that must keep running when the HTA is not the focused window.
- **No flexbox/CSS Grid:** WinPE's mshta uses an IE7–IE9 engine. Use `display:table`/`table-cell` or floats for layouts. Force IE9 mode with `<meta http-equiv="x-ua-compatible" content="ie=9">` — do not use `ie=11` or `ie=edge` as these break VBScript.
- **`WshShell.Exec` pipe deadlock:** Long-running processes with lots of output (like DISM) will deadlock if called via `Exec` because internal pipe buffers fill up. Always use `Shell.Run` with flag file polling for DISM.

---

## Troubleshooting

**Deployment doesn't start / HTA appears but nothing happens**
- Ensure `wpeinit.exe` runs before `startnet.cmd` (it's listed first in `winpeshl.ini`)
- Check that all files are in `X:\deploy\` on the WinPE image

**USB drive not found / DISM can't find install.wim**
- The script scans drive letters C through L for `sources\install.wim`
- After diskpart runs, drive letters may shift — check that your USB isn't assigned S or W (reserved for the partitions)
- Expand the drive letter scan range in `startnet.cmd` if needed

**DISM fails with an error**
- Verify your `install.wim` is not corrupted: `dism /Get-ImageInfo /ImageFile:"D:\sources\install.wim"`
- Ensure the target disk is large enough for the image
- Check that diskpart completed successfully before DISM ran

**Device won't boot from USB**
- Disable Secure Boot in BIOS
- Ensure the USB was written in ISO mode by Rufus (not DD mode)
- Try a different USB port

**HTA progress bar freezes but deployment continues**
- The deployment itself runs in `startnet.cmd` independently of the HTA
- Alt+Tab to the console window to verify progress
- This was a known issue with VBScript timers — the JavaScript timer fix addresses it

---

## Licence

MIT — do whatever you want with it.

---

## Contributing

PRs welcome. If you've tested this on different hardware or WinPE versions, please open an issue with your findings.
