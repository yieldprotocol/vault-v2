# How to Hack the Variable Yield Protocol

This document lists ways in which the Yield Protocol Variable rate could be hacked, if an error is made. This information will be relevant in hardening the platform and our processes.

When stating the effect from misusing a governance function, only the worst possible outcome is detailed.

## Yield-Utils

### Non-revoking of ROOT

All of our permissioned contracts inherit from [AccessControl.sol](https://github.com/yieldprotocol/yield-utils-v2/blob/main/contracts/access/AccessControl.sol). In the constructor, ROOT permission is given to `msg.sender`, which has then to be removed manually. Failing to do so gives ROOT access to the deployer on the deployed contract.

### Accidental granting of ROOT

The ROOT signature is `0x00000000`, or `bytes4(0)`. A call to `grantRole` where the parameter is accidentally set to zero will grant ROOT to `account`.

### Cast malfunction

All of our casting operations are in the [cast library](https://github.com/yieldprotocol/yield-utils-v2/blob/main/src/utils/Cast.sol). An error there would not be clearly visible, and the contracts themselves are not tested. A malfunction would lead to an over/underflow elsewhere.

### WMath malfunction

Fixed math operations are included in our [math libraries](https://github.com/yieldprotocol/yield-utils-v2/blob/main/src/utils/Math.sol), which are untested to the exception of `WPow`. An error would lead to unpredictable results anywhere where math happens.

### ERC20 burn on user

The standard `_burn` function on ERC20 doesn't check for ownership or allowance. A careless implementation could lead to scenarios where users' tokens can burn without permission.

### EmergencyBrake DoS via Governance

A governance attack on EmergencyBrake would allow the attacker to remove contract orchestration in the Yield Protocol, leading to an extended Denial of Service

### Timelock attack

Any attack that successfully takes control of the Timelock as a developer would be harmless, but on the other hand taking control of the governor role would be fatal.

## Vault

### Join with Rebasing Tokens

With a rebasing token, the result of `token.balanceOf(user)` changes depending on the block, without any transfers needed. If such a token would be onboarded to the Yield Protocol there might be a constantly increasing `token.balanceOf(address(this))`, and its difference to `storedBalance` could be drained through a contract with access to `exit`, such as the Ladle.

### Join with Double Contract Tokens

It is possible to implement a token contract that is permissioned to forward all calls to a second token contract. The result would be that a token contract would have two addresses. If such a contract would be onboarded to Yield Protocol, all assets could be drained calling `retrieve` with the second token address.

### Join Governance Capture

If `exit` access is obtained on a Join, all funds can be immediately drained.

### Oracle Fat-Fingering

There is no verification of inputs on `setSource`. Entering the wrong data could potentially cause wildly inaccurate oracle readings, leading to taking undercollateralized loans and draining of the protocol.

### Interest Rate Oracle Fat-Fingering

Setting the wrong rate in the Interest Rate Oracle would lead to incorrect lending or borrowing rates.

### Oracle Wrapper Manipulation

A number of our oracles (Yield Vault, Euler, Lido) feed on exchange rates poorly understood by us. Manipulation of the rates in one of these third-party contracts could potentially cause wildly inaccurate oracle readings, leading to taking undercollateralized loans and draining of the pools.

### VYToken Redemption Freeze on Faulty Oracle

If the chi oracle returns zero in the `_convertToUnderlying` call. Calls to `_convertToPrincipal`, including `redeem`, will revert due a division by zero error.

### Cauldron Fat-Fingering

`addAsset`: AssetId lost forever.
`setDebtLimits`: Impossible to borrow, dust vaults allowed, no ceiling.
`setSpotOracle`: Incorrect price feeds, could lead to uncollateralized borrowing.
`addIlks`: Allowing unsafe collateral for a given underlying, innocuous unless done in conjunction with `setDebtLimits`.

### Cauldron Governance Capture

Depending on the specific function captured, but probably leading to drainage of the whole protocol.

### Ladle Fat-Fingering

`addIntegration`: Features disabled.
`addToken`: Features disabled.
`addJoin`: Difficult to break, even using a malicious Join.
`setFee`: Borrowing disabled due to excessive fees

### Ladle Misuse

Improperly configured batches can lead to the loss of any assets the calling user might hold in the protocol, as well as any assets in his wallet that he would approve the Ladle or Joins for.

### Witch Fat-Fingering

`point`: Would disable liquidations as all payments fail.
`setLineAndLimit`: Proportion being set to zero or at a very small number would disable liquidations. Setting a `line` for a non-existing pair might mean that the real pair is not set to be liquidable. Setting a `limit` for a non-existing pair might mean that the real pair is not set to be liquidable. Setting `max` to zero would only allow one concurrent auction. Setting `max` to 2^128-1 would allow any amount of colalteral to be auctioned concurrently.
`setAuctioneerReward`: It can be misused to direct all profit for auctioneers, effectively disincentivizing liquidators to liquidate.

### Witch Governance Capture

Disable auctions, leading to protocol insolvency in a downturn. There might be some potential for an attack in which non-liquidable pairs are made liquidable.

### Giver Governance Capture

Draining of all users overcollateralization, with subsequent liquidation.
