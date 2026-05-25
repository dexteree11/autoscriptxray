# Imagitech XRAY Suite 🔒

> A companion to [autoscriptssh](https://github.com/dexteree11/autoscriptssh) — a terminal-based XRAY VPN control panel supporting all major modern protocols.

---

## Supported Protocols

| # | Protocol | Transport | TLS | Domain Required |
|---|---|---|---|---|
| 01 | VLESS + REALITY + xHTTP | xhttp | REALITY | ❌ No |
| 02 | VLESS + REALITY + TCP | tcp | REALITY | ❌ No |
| 03 | VLESS + WS + TLS | WebSocket | TLS (acme.sh) | ✅ Yes |
| 04 | Trojan + WS + TLS | WebSocket | TLS (acme.sh) | ✅ Yes |
| 05 | Trojan + TCP + TLS | TCP | TLS (acme.sh) | ✅ Yes |
| 06 | VMess + WS + TLS | WebSocket | TLS (acme.sh) | ✅ Yes |

---

## One-Line Install

```bash
bash -c "$(curl -sL https://raw.githubusercontent.com/dexteree11/autoscriptxray/main/install.sh)"
```

> Must be run as **root** on Ubuntu 20.04 / 22.04 / Debian 11+

---

## Usage

After installation, launch the panel with:

```bash
xray-panel
```

---

## Features

- ✅ **Port conflict manager** — checks ports before any install; option to kill conflicting process
- ✅ **User management** — add/delete/list users per protocol; credentials stored in flat files
- ✅ **Share links & QR codes** — inline terminal QR codes for every user
- ✅ **REALITY key generation** — auto-generates X25519 keypairs and short IDs; always prompts for SNI
- ✅ **TLS via acme.sh + Cloudflare DNS** — no need to open port 80; wildcard cert support
- ✅ **Nginx WS proxy** — routes `/vless`, `/trojan-ws`, `/vmess` paths to local Xray listeners
- ✅ **Service manager** — start/stop/restart Xray and Nginx; config validation; logs viewer
- ✅ **Self-updater** — pull latest scripts from GitHub without reinstalling

---

## Directory Structure

```
/opt/imagitech-xray/
├── core/
│   ├── imagitech-xray.conf     # Domain, CF keys, settings
│   ├── keys/                   # TLS certs (fullchain.pem, privkey.pem)
│   │   └── reality_*.env       # REALITY keypairs per transport
│   ├── users/                  # User files per protocol (*.users)
│   └── logs/                   # Xray access/error logs
├── lib/
│   ├── colors.sh               # ANSI palette
│   ├── ui.sh                   # Box drawing, spinners, kv printer
│   ├── xray_utils.sh           # UUID/key gen, config R/W, service control
│   ├── qr.sh                   # QR + share link builders
│   └── port_check.sh           # Port conflict manager
├── installers/
│   ├── install_xray.sh
│   ├── install_nginx.sh
│   └── install_acme.sh
├── configs/
│   ├── xray_base.json
│   └── nginx_ws.conf.template
├── menus/
│   ├── main_menu.sh
│   ├── vless_reality_menu.sh
│   ├── vless_ws_menu.sh
│   ├── trojan_ws_menu.sh
│   ├── trojan_tcp_menu.sh
│   ├── vmess_ws_menu.sh
│   ├── service_menu.sh
│   ├── cert_menu.sh
│   ├── nginx_menu.sh
│   └── settings_menu.sh
└── bin/
    └── xray-panel              # Symlinked to /usr/local/bin/xray-panel
```

---

## Compatible Clients

| Platform | Recommended Client |
|---|---|
| Android | v2rayNG, Hiddify |
| iOS | Shadowrocket, Streisand |
| Windows | v2rayN, Nekoray |
| macOS | Hiddify, V2Box |
| Linux | Nekoray, Xray CLI |

---

## License

MIT — free to use, modify, and distribute.
