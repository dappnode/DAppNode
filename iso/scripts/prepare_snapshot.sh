#!/bin/bash

DAPPNODE_INSTALL_SCRIPT_URL=$1
if [ -z "$DAPPNODE_INSTALL_SCRIPT_URL" ]; then
  echo "Must supply one argument, DAPPNODE_INSTALL_SCRIPT_URL"
  echo "Example: https://raw.githubusercontent.com/dappnode/DAppNode_Installer/monolithic/build/utils/scripts/dappnode_install.sh"
  exit 1
fi

wget -qO - https://prerequisites.dappnode.io  | sudo bash

mkdir -p /usr/src/dappnode/scripts/

wget $DAPPNODE_INSTALL_SCRIPT_URL -O /usr/src/dappnode/scripts/dappnode_install.sh

chmod +x /usr/src/dappnode/scripts/dappnode_install.sh

touch /usr/src/dappnode/.firstboot

cat <<EOF >/etc/rc.local
#!/bin/sh -e
/usr/src/dappnode/scripts/dappnode_install.sh
exit 0
EOF

chmod +x /etc/rc.local

cat <<EOF >/etc/systemd/system/rc-local.service
[Unit]
 Description=/etc/rc.local Compatibility
 ConditionPathExists=/etc/rc.local
[Service]
 Type=forking
 ExecStart=/etc/rc.local start
 TimeoutSec=0
 StandardOutput=tty
 RemainAfterExit=yes
 SysVStartPriority=99
[Install]
 WantedBy=multi-user.target
EOF

systemctl enable rc-local

UPDATE=true /usr/src/dappnode/scripts/dappnode_install.sh

rm /usr/src/dappnode/.firstboot