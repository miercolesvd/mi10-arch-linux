# Hardware status

The kernel is the [Nura port](https://github.com/miercolesvd/mi10-port)'s
6.12.94 kernel with two more patches (USB-C host mode, brightness). The
**Tested** column says where each line was confirmed.

| Component | State | Tested | Notes |
|---|---|---|---|
| Boot from the `boot` partition | <span class="ok">works</span> | Arch, Nura | kernel updates rewrite `boot` by themselves |
| Screen (CSOT AMOLED, 60/90 Hz) | <span class="ok">works</span> | Arch, Nura | 90 Hz measured in the Nura port |
| Brightness | <span class="part">fixed, to confirm</span> | — | up to build-6 the slider only gave full or almost black; kernel patch 0016 fixes it |
| Touch (ST FTS) | <span class="ok">works</span> | Arch, Nura | |
| GPU (Adreno 650) | <span class="ok">works</span> | Nura | Mesa freedreno (OpenGL) and turnip (Vulkan) |
| KDE Plasma (Wayland) | <span class="ok">works</span> | Arch | |
| USB-C host: hubs, docks, keyboard, mouse | <span class="ok">works</span> | Arch | kernel patch 0015; tried with a Thunderbolt 4 dock |
| Ethernet through a dock | <span class="ok">works</span> | Arch | |
| USB-C to a PC (network link, SSH) | <span class="part">untested</span> | — | new in the Arch build |
| External monitor | <span class="no">not possible</span> | — | the USB-C port only has USB 2.0 wired, no DisplayPort |
| Charging | <span class="ok">works</span> | Arch | from a charger or a powered dock |
| Battery status | <span class="part">wrong</span> | Arch | can show *Discharging* while charging |
| Wi-Fi (QCA6390) | <span class="ok">works</span> | Nura | |
| Bluetooth | <span class="ok">works</span> | Nura | |
| Loudspeakers, stereo | <span class="ok">works</span> | Nura | top receiver left, bottom speaker right |
| Internal microphones | <span class="ok">works</span> | Nura | |
| Modem (SDX55M), mobile data | <span class="ok">works</span> | Nura | 4G; starts by itself, outside NetworkManager |
| Calls, SMS | <span class="no">not set up</span> | — | |
| Wired headset (USB-C adapter), earpiece | <span class="no">not working</span> | — | |
| Cameras | <span class="no">not working</span> | — | |
| Sensors (rotation, light, proximity) | <span class="no">not working</span> | — | |
| Fingerprint, NFC | <span class="no">not working</span> | — | |
| Suspend | <span class="part">switched off</span> | — | never tried; see [Using it](using.md#suspend) |

## Supported variant

Mi 10 units shipped with different screens and touch controllers. This
kernel supports the **CSOT panel** (`42 02 0b`) with **ST FTS touch**.
The Samsung panel needs different panel data, and Goodix touch has no driver
here.
