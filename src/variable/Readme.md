# Variable Rate Lending/Borrowing

With this update we are bringing variable rate borrowing & lending to the Yield Protocol. This is a major update to the protocol and we are excited to bring this to the community.

Unlike fixed rate borrowing there is no intermediary token involved while borrowing. When user borrows an asset they directly get the asset in their choosen address. However, for lending there is an intermediate token called the `VYToken`. The `VYToken` represents the amount lent based on the interest rate at time of lending. The `VYToken` can be burnt at any time to get the lent asset back.

Here are the main components of the system:

1. [VRLadle](./VRLadle.sol) - The main contract that handles the lending/borrowing of the variable rate loan.
2. [VRCauldron](./VRCauldron.sol) - The contract that handles the accounting.
3. [VRWitch](./VRWitch.sol) - The contract that handles the liquidation.
4. [VYToken](./VYToken.sol) - The contract that handles the tokenization of the loan.
5. [Join](../Join.sol)(not in scope) - The contract that holds the collateral & lent assets.
6. Oracles (not in scope) - The contract that determines the interest rate & spot price of the collateral in terms of the base.

---

# Contracts

## VRLadle (177 SLOC)

Ladle is the contract which does the lending/borrowing of the variable rate loan. It is the main orchestrating contract of the system. Here are the broad operations the contract performs:

- Build Vaults for the loan
- Move assets in and out of the joins
- Updates accounting in the VRCauldron
- Collects approvals from users for transfers
- Perform operations to manage the vaults when needed like moving debt from one vault to another.
- Keep track of the joins

## VRCauldron (286 SLOC)

Cauldron is the contract which handles the accounting of the variable rate loan. It is the contract that keeps track of the balances of the lenders and borrowers.
The contract enforces checks to ensure that the loans are not under-collateralized.

- It keeps track of protocol level data. (debt, configuration(bases, ilks, oracles, asset addresses), etc)
- It keeps track of user level data (vault, balances, etc)

## VRWitch (46 SLOC)

It is the liquidation engine built on top of the existing battle tested `Witch` for the fixed rate lending. It has been modified to work in absence of `fyToken`. Also, the way the `debtFromBase` & `debtToBase` is calculated has been modified to work with the variable rate.
You can refer to [this](https://github.com/code-423n4/2022-07-yield) for more details on the Witch.

## VYToken (151 SLOC)

`VYToken` is a mechanism that allows user to lend their assets as we. The `VYToken` is a ERC20 token that represents the amount of asset lent. The `VYToken` can be burnt at any time to get the lent asset back.

---

# Terminology

- `base` - The asset that is borrowed. Eg. DAI, USDC, USDT, etc.
- `ilk` - The asset that is used as collateral. Eg. ETH, WBTC, etc.
- `spotOracle` - The oracle that determines the spot price of the collateral in terms of the base. Eg. ETH/DAI, WBTC/DAI, etc.
- `rateOracle` - The oracle that determines the interest rate of the base.

# Working

## How does borrowing work?

To borrow a base you need to first deposit the collateral in the protocol. The collateral could be either deposited directly to the relevant `Join` by the user or the user could give permission to either the `Join` or `Ladle` to move the token on their behalf. The protocol will check if the collateral is sufficient to cover the debt. The check happens taking into account the collateralization ratio and the spot rate of the collateral in terms of the base. If the collateral is sufficient then the protocol will transfer the base to the user's determined address.
The user could repay the debt at any time by depositing the base back into the protocol. The protocol will determine the amount owed based on the interest rate at the time of repayment.

### Under the hood

The borrowing is executed through a batch call made to the `VRLadle` contract. The batch consists of the following operations:

1. `VRLadle.build` - This operation creates a new vault for the user. `Please note this is optional as the user could already have a vault.`
2. `VRLadle.transfer`/`VRLadle.forwardPermit`/`VRLadle.forwardDaiPermit` - This operation transfers the collateral from the user to the protocol. `Please note that this is optional operation as the user could have already deposited the collateral in the protocol or they could have approved the join to transfer the collateral on their behalf in a separate transaction`
3. `VRLadle.pour` - This operation posts the collateral and transfers the borrowed base to the user supplied address.

## How does lending work?

To lend an asset you deposit the asset into the protocol and mint the `VYTokens`. The deposit could happen the same way as described in borrowing. The amount of `VYTokens` minted is determined by the interest rate at the time of lending. The interest is received from the `rateOracle`. The `VYTokens` can be burnt at any time to get the lent back.

### Under the hood

The lending is executed through a batch call made to the `VRLadle` contract. The batch consists of the following operations:

1. `VRLadle.transfer`/`VRLadle.forwardPermit`/`VRLadle.forwardDaiPermit` - This operation transfers the collateral from the user to the protocol. `Please note that this is optional operation as the user could have already deposited the collateral in the protocol or they could have approved the join to transfer the collateral on their behalf in a separate transaction`
2. `VRLadle.moduleCall` - This operation calls the `VYToken` contract to mint the `VYTokens` for the user.

# Orchestration

The protocol modifications are handled through a three step process. The first step is to propose a proposal. The second step is to vote on the proposal. The third step is to execute the proposal. The three steps are managed through the `TimeLock` contract.

The `VRLadle` contract can be configured by the `TimeLock` contract. And the rest of the protocol can be configured by the `VRLadle` contract.

Here are the permissions allocated to different contracts:

`Timelock` will have the following permissions over `VRLadle`:

- `addJoin` - Allows to add a new join to the ladle.
- `addModule` - Allows to add a new module to the ladle.
- `setFee` - Allows to set the borrowing fee for the protocol.
- `addToken` - Allows to add a new token to the ladle.
- `addIntegration` - Allows to add a new integration to the ladle.

`VRLadle` has the following permissions over `VRCauldron`:

- `addAsset` - Allows to add an asset to the protocol
- `addIlks` - Allows to make the supplied asset(s) an ilk to an existing base.
- `setDebtLimits` - Allows to set the maximum and minimum debt for a base and ilk pair.
- `setRateOracle` - Allows to set the rate oracle for a base.
- `setSpotOracle` - Allows to set a spot oracle and its collateralization ratio.
- `addBase` - Allows to add a new base.
- `destroy` - Allows to destroy an empty vault.
- `build` - Allows to create a new vault.
- `pour` - Allows to deposit collateral and borrow a base.
- `give` - Allows to transfer ownership of a vault.
- `tweak` - Allows to change a vault base and/or collateral types.
- `stir` - Allows to move collateral and debt between vaults.

`VRLadle` will have following permissions over `Joins`:

- `join` - Allows to deposit an asset into the protocol.
- `exit` - Allows to withdraw an asset from the protocol.

---

# Audit Scope

Here are the contracts that are in scope for the audit:

| Type | File                                    | Logic Contracts | Interfaces | Lines    | nLines   | nSLOC   | Comment Lines | Complex. Score |
| ---- | --------------------------------------- | --------------- | ---------- | -------- | -------- | ------- | ------------- | -------------- |
| 📝   | src/variable/VRCauldron.sol             | 1               | \*\*\*\*   | 459      | 383      | 286     | 61            | 193            |
| 📝   | src/variable/VRLadle.sol                | 1               | \*\*\*\*   | 352      | 284      | 177     | 65            | 250            |
| 📝   | src/variable/VRLadleStorage.sol         | 1               | \*\*\*\*   | 34       | 34       | 27      | 6             | 21             |
| 📝   | src/variable/VRWitch.sol                | 1               | \*\*\*\*   | 102      | 82       | 46      | 23            | 25             |
| 📝   | src/variable/VYToken.sol                | 1               | \*\*\*\*   | 245      | 240      | 151     | 62            | 151            |
| 🔍   | src/variable/interfaces/IVRCauldron.sol | \*\*\*\*        | 1          | 109      | 9        | 6       | 22            | 37             |
| 🔍   | src/variable/interfaces/IVRWitch.sol    | \*\*\*\*        | 1          | 140      | 46       | 33      | 78            | 19             |
| 📝🔍 | **Totals**                              | **5**           | **2**      | **1441** | **1078** | **726** | **317**       | **696**        |

---
# Building & Testing
This project uses foundry to build and test the contracts. 
- To build the contracts run the following command:
```forge build```
- To run the tests run the following command:
```forge test --match-path src/test/variable/<contract_name>.sol```

---

# Note
- The protocol follows the [Forward Trust Pattern](https://hackernoon.com/using-the-forward-trust-design-pattern-to-make-scaling-easier). This means there are caveats to using the protocol. Things could go wrong if the protocol is not used from the protocol provided frontend.
- Gas optimization is not a priority for the audit unless there is a huge improvement.
- This is a MVP. So, we are focussed towards delivering a usable & safe protocol.
- We prefer clarity of code to enable faster iteration of the product even by non-core developers.
- [Here](https://github.com/yieldprotocol/addendum-docs/blob/e1b8c294e5a8db7560c215d58fc3011a5f96c38d/COOKBOOK_VARIABLE.md) is the recepie book which specifies how the protocol can be used from the frontend.