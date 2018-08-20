.. index:: ! core

.. _dappnode-core:

#############
DAppNode Core
#############

****
BIND
****

Local DAppNode DNS. Links each package docker IP to a name in the format of my.[package-name].dnp.dappnode.eth. I also redirects .eth domains to the ethforward.

***
VPN
***

Provides a l2tpd VPN for users to consume dappnode's services.

********
ETHCHAIN
********

Local full mainnet ethereum node.

**********
ETHFORWARD
**********

Resolves .eth domains by intercepting outgoing requests, calling ENS, and redirecting to the local IPFS node. 

****
IPFS
****

Local IFPS node.

****
WAMP
****

Handles inter-package communications. Restricts certain operations to only admin users.

***********
DAPPMANAGER
***********

Nodejs app that handles the instalation and managent of DAppNode packages.

*****
ADMIN
*****

Web App which handles admin <-> DAppNode interactions, such as managing packages or VPN users.

