# Yield Protocol Vault v2

The Yield Protocol Vault v2 is a Collateralized Debt Engine for zero-coupon bonds, loosely integrated with [YieldSpace Automated Market Makers](https://yield.is/Yield.pdf), as described by Dan Robinson and Allan Niemerg.

## Smart Contracts

A longer description of the smart contracts can be found in the [Yield v2 reference](https://docs.google.com/document/d/1WBrJx_5wxK1a4N_9b6IQV70d2TyyyFxpiTfjA6PuZaQ/edit).

### Oracles
Oracles return spot prices, borrowing rates and lending rates for the assets in the protocol.

### Join
Joins store assets, such as ERC20 or ERC721 tokens.

### FYToken
FYTokens are ERC20 tokens that are redeemable at maturity for their underlying asset, at an amount that starts at 1 and increases with the lending rate (`chi`).

### Cauldron
The Cauldron is responsible for the accounting in the Yield Protocol. Vaults are created to contain borrowing positions of one collateral asset type against one fyToken series. The debt in a given vault increases with the borrowing rate (`rate`) after maturity of the associated fyToken series.

When the value of the collateral in a vault falls below the value of the borrowed fyToken, the vault can be liquidated.

### Ladle
The Ladle is the gateway for all Cauldron integrations, and all asset movements in and out of the Joins (except fyToken redemptions). To implement certain features the Ladle integrates with YieldSpace Pools.

[Ladle recipe cookbook](https://docs.google.com/document/d/1-r9g99aZfGLd1Aa3FRxBXLybgfGzAZIuHWwufF-I8Js).

### Wand
The Wand bundles function calls into governance actions.

### Witch
The Witch is the liquidation engine for the Yield Protocol Vault v2.

## Warning
This code is provided as-is, with no guarantees of any kind.

### Pre Requisites
Before running any command, make sure to install dependencies:

```
$ yarn
```

### Lint Solidity
Lint the Solidity code:

```
$ yarn lint:sol
```

### Lint TypeScript
Lint the TypeScript code:

```
$ yarn lint:ts
```

### Coverage
Generate the code coverage report:

```
$ yarn coverage
```

### Test
Be sure to have an `.env` file located at `packages/foundry` with the value `MAINNET_RPC=<your rpc url>` to be used for forked tests.

Compile and test the smart contracts with [Foundry](https://getfoundry.sh/):

```
$ cd packages/foundry
$ forge test
```

Additional tests can be run with Hardhat using npm or yarn:

```
$ cd packages/hardhat
$ npm run hardhat:test
```

## Bug Bounty
Yield is offering bounties for bugs disclosed to us at [security@yield.is](mailto:security@yield.is). The bounty reward is up to $25,000, depending on severity. Please include full details of the vulnerability and steps/code to reproduce. We ask that you permit us time to review and remediate any findings before public disclosure.

## License
All files in this repository are released under the [GPLv3](https://github.com/yieldprotocol/fyDai/blob/master/LICENSE.md) license.
