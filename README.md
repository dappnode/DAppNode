# Dappnode

[![Website dappnode.io](https://img.shields.io/badge/Website-dappnode.io-brightgreen.svg)](https://dappnode.io/)
[![Documentation Wiki](https://img.shields.io/badge/Documentation-Wiki-brightgreen.svg)](https://docs.dappnode.io)
[![GIVETH Campaign](https://img.shields.io/badge/GIVETH-Campaign-1e083c.svg)](https://beta.giveth.io/campaigns/5b44b198647f33526e67c262)
![GitHub All Releases](https://img.shields.io/github/downloads/dappnode/DAppNode/total.svg)
[![GitPOAP Badge](https://public-api.gitpoap.io/v1/repo/dappnode/DAppNode/badge)](https://www.gitpoap.io/gh/dappnode/DAppNode)
[![Twitter Follow](https://img.shields.io/twitter/follow/espadrine.svg?style=social&label=Follow)](https://twitter.com/DAppNODE?lang=es)
[![Discord](https://img.shields.io/discord/747647430450741309?logo=discord&style=plastic)](https://discord.gg/dappnode)



<br/>
<p align="center">
  <a href="https://dappnode.com/">
    <img width="800" src="doc/DappnodeLogoWide-outlined.png">
  </a>
</p>
<br/>
<p align="center">
  <a href="https://docs.dappnode.io/user/quick-start/Core/installation">
    <img width="200" src="doc/DappnodeInstall.png">
  </a>
</p>
<br/>

## Infrastructure for the decentralized world

Dappnode is empowering people by creating a simple, transparent system for hosting P2P clients for DApps, Cryptocurrencies, VPNs, IPFS and more

- Read about our purpose and mission on [Our Website](https://dappnode.com/)
- Join our community and find support on [Our Discord](https://discord.gg/dappnode)
- Check out what we are up to on [Our Medium](https://medium.com/dappnode)
- Share your ideas and find how to guides on [Our Forum](https://discourse.dappnode.io/)

## Discover Dappnode

Dappnode lowers the barrier of entry for non tech-savvy participants. It allows you to deploy, update, and manage P2P clients and nodes without leaving your browser. No terminal or command line interface.

<p align="center">
  <a href="https://docs.dappnode.io/user/quick-start/Core/installation">
    <img width="800" src="doc/DAppNodeAdminUI-demo.png">
  </a>
</p>

## Develop with Dappnode

Dappnode modular architecture allows any team to or project to publish a dockerized application to the Dappnode packages eco-system. Benefit from an enthusiastic crypto savvy user based and offer a user interface-only experience to lower onboarding friction.

Check out the [DappnodeSDK](https://github.com/dappnode/DAppNodeSDK) to learn how to get started.

_Note: packages are published to Ethereum mainnet and incur costs. Given the current high gas prices the Dappnode team is willing to subsidize gas costs for packages of great interest to users._

## Packages eco-system

The community and core team members have created many useful packages for users. Checkout the [**package explorer**](https://explorer.dappnode.io) to browse an up-to-date list of all packages and their versions.

<p align="center">
  <a href="https://explorer.dappnode.io">
    <img width="600" src="doc/DAppNodeExplorer.png">
  </a>
</p>

## Core packages

- [DNP_DAPPMANAGER](https://github.com/dappnode/DNP_DAPPMANAGER)
- [DNP_VPN](https://github.com/dappnode/DNP_VPN)
- [DNP_IPFS](https://github.com/dappnode/DNP_IPFS)
- [DNP_BIND](https://github.com/dappnode/DNP_BIND)
- [DNP_WIREGUARD](https://github.com/dappnode/DNP_WIREGUARD)
- [DNP_HTTPS](https://github.com/dappnode/DNP_HTTPS)

## Get Dappnode

Get your Dappnode and start contributing to decentralization by running your own nodes.

[Install Dappnode on your host machine](https://docs.dappnode.io/user/quick-start/Core/installation) or buy your Dappnode with all the stuff configured and prepared to be used in [Dappnode shop](https://dappnode.com/en-us/collections/frontpage)

### Install Dappnode with ISO

Dappnode ISO available is in: [latest Dappnode release](https://github.com/dappnode/DAppNode/releases).

Install Dappnode on your host machine by burning Dappnode ISO to a DVD or creating a bootable USB. Follow the tutorial of your operating system below and come back when you are finished:

- [MacOS](https://tutorials.ubuntu.com/tutorial/tutorial-create-a-usb-stick-on-macos)
- [Windows](https://tutorials.ubuntu.com/tutorial/tutorial-create-a-usb-stick-on-windows)
- [Ubuntu](https://tutorials.ubuntu.com/tutorial/tutorial-create-a-usb-stick-on-ubuntu)

**Developers**: Dappnode ISO could be generated following these steps:

```bash
git clone https://github.com/dappnode/DAppNode.git
cd DAppNode
docker compose build
docker compose up
```

Dappnode iso will be generated inside images folder, to verify it:

```bash
ls -lrt images/DAppNode-*
```

_Note_: ISO could be generated as unattended/attended by editing the env var available in the docker-compose.yml file

### Install Dappnode with scripts

Scripts are available in: [latest Dappnode release](https://github.com/dappnode/DAppNode/releases).

Dappnode could be also installed on a host machine with an OS already running on it. Dappnode has been developed and configured to be run on Debian host machines. Therefore, it should work on Debian or Debian based (like Ubuntu) host machines. Minimum recommended Debian version is 11.

**1. Prerequisites**

Before installing Dappnode with the script option, make sure you fulfill the requirements by running the following script:

```bash
sudo wget -O - https://prerequisites.dappnode.io | sudo bash
```

**2. Script installation**

Once you make sure you have the requirements, install Dappnode with the installation script:

```bash
sudo wget -O - https://installer.dappnode.io | sudo bash
```

**3. Uninstall Dappnode**

Uninstall Dappnode from your host machine by running the following command:

```bash
wget -qO - https://uninstaller.dappnode.io | sudo bash
```

**4. Update Dappnode from scripts**

To update Dappnode to the latest version using script:

```bash
sudo wget -O - https://installer.dappnode.io | sudo UPDATE=true bash
```

## Releases

Create releases manually with Github actions, the Github action to run is: **Pre-release**. The requirements are:

- Introduce the core packages versions
- There must exist the corresponding core package release for the specified version

The release will contain:

- Assets:
  - Scripts: `dappnode_access_credentials.sh`, `dappnode_install.sh`, `dappnode_uninstall.sh`, `dappnode_install_pre.sh`, `dappnode_profile.sh`
  - ISOs: `DAppNode-vX-debian-bullseye-amd64-unattended.iso`, `DAppNode-vX-debian-bullseye-amd64-unattended.iso`
- Release body:
  - Table with core packages versions
  - Changes section
  - SHASUMs for unattended and attended ISOs
  - Default credentials

## Testing with artifacts

Generate ISOs and test them by running the Github action: **Artifacts**. This action will generate an artifacts with the same assets as the release, useful for testing purposes.

## Versioning

We use [SemVer](http://semver.org/) for versioning. For the versions available, see the [tags on this repository](https://github.com/dappnode/DAppNode/tags).

## Team members

Members of the [White Hat Group (WHG)](https://motherboard.vice.com/en_us/article/qvp5b3/how-ethereum-coders-hacked-back-to-rescue-dollar208-million-in-ethereum) have spent countless hours bootstrapping and developing Dappnode in 2017. Currently, the project is maintained by a growing multi-disciplinary team:

- **Adviser & Instigator:** Jordi Baylina
- **Project Lead:** Eduadiez
- **Developer Lead:** dapplion
- **Ecosystem Development** Pol Lanski
- **Developer:** Pablo
- **Developer:** Carlos
- **Adviser:** Griff Green

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details

## Copyright

Copyright © (2018-2023) [The DAppNode Association](https://dappnode.com)
