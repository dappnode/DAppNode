###########################
Frequently Asked Questions
###########################

This list was originally compiled by `fivedogit <mailto:fivedogit@gmail.com>`_.


***************
Basic Questions
***************

What is the transaction "payload"?
==================================

This is just the bytecode "data" sent along with the request.

******************
Advanced Questions
******************

Can you return an array or a ``string`` from a solidity function call?
======================================================================

Yes. See `array_receiver_and_returner.sol <https://github.com/fivedogit/solidity-baby-steps/blob/master/contracts/60_array_receiver_and_returner.sol>`_.

What is problematic, though, is returning any variably-sized data (e.g. a
variably-sized array like ``uint[]``) from a function **called from within Solidity**.
This is a limitation of the EVM and will be solved with the next protocol update.

Returning variably-sized data as part of an external transaction or call is fine.

More Questions?
===============

If you have more questions or your question is not answered here, please talk to us on
`gitter <https://gitter.im/ethereum/solidity>`_ or file an `issue <https://github.com/ethereum/solidity/issues>`_.