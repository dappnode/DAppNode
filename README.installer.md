# DAppNode_Installer

[![Website dappnode.io](https://img.shields.io/badge/Website-dappnode.io-brightgreen.svg)](https://dappnode.io/)
[![Documentation Wiki](https://img.shields.io/badge/Documentation-Wiki-brightgreen.svg)](https://github.com/dappnode/DAppNode/wiki)
[![GIVETH Campaign](https://img.shields.io/badge/GIVETH-Campaign-1e083c.svg)](https://beta.giveth.io/campaigns/5b44b198647f33526e67c262)
[![ELEMENT DAppNode](https://img.shields.io/badge/ELEMENT-DAppNode-blue.svg)](https://app.element.io/#/room/#DAppNode:matrix.org)
[![Twitter Follow](https://img.shields.io/twitter/follow/espadrine.svg?style=social&label=Follow)](https://twitter.com/DAppNODE?lang=es)

This repository generates the .iso file for installing DappNode to a server. Below are the instructions that you will need to make your own DappNode ISO.

## Get DAppNode

Get your DAppNode and start contributing to decentralization by running your own nodes.

### Buy DAppNode

Buy your DAppNode with all the stuff configured and prepared to be used in [DAppNode shop](https://shop.dappnode.io/)

### Install DAppNode

[Install DAppNode on your host machine](https://docs.dappnode.io/install/)

#### Install DAppNode from ISO

DAppNode ISO available in: [latest DAppNode release](https://github.com/dappnode/DAppNode/releases)

Install DAppNode on your host machine by burning DAppNode ISO to a DVD or creating a bootable USB. Follow the tutorial of your operating system below and come back when you are finished:

- [MacOS](https://tutorials.ubuntu.com/tutorial/tutorial-create-a-usb-stick-on-macos)
- [Windows](https://tutorials.ubuntu.com/tutorial/tutorial-create-a-usb-stick-on-windows)
- [Ubuntu](https://tutorials.ubuntu.com/tutorial/tutorial-create-a-usb-stick-on-ubuntu)

**Developers**: DAppNode ISO could be generated following these steps:

```bash
git clone https://github.com/dappnode/DAppNode_Installer.git
cd DAppNode_Installer
docker-compose build
docker-compose up
```

DAppNode iso will be generated inside images folder, to verify it:

```bash
ls -lrt images/DappNode-ubuntu-*
```

_Note_: ISO could be generated as unhattended/attended by editing the env var available in the docker-compose.yml file

#### Install DAppNode from scripts

Scripts available in: [latest DAppNode release](https://github.com/dappnode/DAppNode/releases)

DAppNode could be also installed on a host machine with an OS already running on it. DAppNode has been developed and configured to be run on debian host machines so is preferably to install DAppNode on Debian or debian based (like Ubuntu) host machines.

##### Prerrequisites

Before install DAppNode with the script option, make sure you fullfill the requirements by running the following script:

```bash
sudo wget -O - https://prerequisites.dappnode.io | sudo bash
```

##### Script installation

Once you make sure you have the requirements, install DAPpNode with the installation script:

```bash
sudo wget -O - https://installer.dappnode.io | sudo bash
```

#### Uninstall DAppNode

Uinstall DAppNode on your host machine by running the following command:

```bash
wget -qO - https://uninstaller.dappnode.io | sudo bash
```

#### Update DAppNode from scripts

To update DAppNode to the latest version using script:

```bash
sudo wget -O - https://installer.dappnode.io | sudo UPDATE=true bash
```

## Contributing

Please read [CONTRIBUTING.md](https://github.com/dappnode) for details on our code of conduct, and the process for submitting pull requests to us.

## Versioning

We use [SemVer](http://semver.org/) for versioning. For the versions available, see the [tags on this repository](https://github.com/dappnode/DAppNode_Installer/tags).

## Authors

- **Eduardo Antuña Díez** - _Initial work_ - [eduadiez](https://github.com/eduadiez)

See also the list of [contributors](https://github.com/dappnode/DAppNode_Installer/contributors) who participated in this project.

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details
