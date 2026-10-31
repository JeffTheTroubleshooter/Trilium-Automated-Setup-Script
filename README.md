# Trilium Notes Automated Setup Script

Installs the [Trilium Notes](https://github.com/TriliumNext/Trilium) server from its latest official Linux server release and sets it up as a systemd service.

## Automatic Install

```bash
bash trilium-install.sh
```

The script asks for an install directory (default `/opt/trilium`), a data directory (default `/opt/trilium/data`) and a port (default `8083`). When it finishes, open `http://<server-ip>:8083`. The first time you visit, you create your account and password.

The script supports x86_64 (amd64) and ARM64 (aarch64).

## Service

```bash
sudo systemctl status trilium
sudo systemctl restart trilium
sudo systemctl stop trilium
```

Your notes are in the data directory. Back it up.

## Uninstall

```bash
bash trilium-install.sh uninstall
```

## Supported Distros

| Distro | Status |
|---|---|
| Fedora | Tested, works |
| Debian / Ubuntu (and Mint, Pop!_OS, Zorin, elementary) | Not tested, need feedback |
| RHEL / Rocky / AlmaLinux / CentOS | Not tested, need feedback |
| Arch / Manjaro / EndeavourOS / Garuda | Not tested, need feedback |
| openSUSE / SLES | Not tested, need feedback |
| Alpine | Not tested, need feedback |

If you try it on a distro that isn't tested, please open an issue and say how it went.
