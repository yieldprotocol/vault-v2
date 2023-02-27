# Yield Utils

This repo contains minimal or updated versions of popular smart contracts used as utilities.

## Access
 - AccessControl: Hierarchical access control with function signatures as roles
 - Ownable: Contract access control to one address

## Cast
Safely cast between types.
 - Cast+Origin+Destination

## Math
Fixed point math with 18 decimals. Multiplication and division, rounded down as default, also rounded up as option.

# Token
 - ERC20: Minimal ERC20 token inspired on DSToken
 - ERC20Permit: ERC20 with ERC25612 off-chain signature support
 - ERC20Rewards: ERC20Permit embedding rewards of another ERC20 using the Unipool pattern
 - SafeERC20Namer: Derive ERC20 names safely regardless of underlying ERC20 implementation
 - MinimalTransferHelper: transfer ERC20 tokens safely regardless of underlying ERC20 implementation
 - TransferHelper: Same, but also transfer Ether and trasferFrom ERC20

# Utils
 - AddressStringUtil: Convert addresses to strings
 - IsContract: Return if an address contains bytecode
 - RevertMsgExtractor: Retrieve a revert message from a generic call return value
 - Timelock: Schedule batched transactions to be executed after approval
 - EmergencyBrake: Register AccessControl permissioning patterns to isolate contracts on emergencies
 - Relay: Group transactions to be executed on a single external call

## Audits
C4 audit - commit: 78693c5

Audit of Timelock.sol at 8ff8841 by Mudit Gupta: https://twitter.com/Mudit__Gupta/status/1429463910298525701?s=20

Audit of EmergencyBrake.sol [6e37565](https://github.com/yieldprotocol/yield-utils-v2/pull/54/commits/6e375651bee1c08fdac74999aa99874a56d1b396) by devtooligan: https://hackmd.io/@devtooligan/YieldEmergencyBrakeSecurityReview2022-10-11

## License
All files in this repository are released under the MIT license.
