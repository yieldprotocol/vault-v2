# YieldToken

![ :seedling: Builder](https://github.com/yieldprotocol/ytoken-mvp/workflows/Builder/badge.svg)

YieldToken is an implementation of zero-coupon Dai bonds. It is inspired by the paper ["The Yield Protocol: On-Chain Lending With
Interest Rate Discovery"](http://research.paradigm.xyz/Yield.pdf) by Dan Robinson.

## Background

The included solidity contracts permit the creation of tokens that act like zero-coupon bonds. A zero-coupon bond pays no interest but entitles the bearer to the face value at maturity. The goal of YieldTokens, or yTokens for short, is to create a token that upon maturity pays 1 Dai worth of Ether to the bearer. Each yToken belongs to a "series", a set of fungible yTokens having a common maturity date. Any user can create a yToken of a particular series by depositing an appropriate amount of collateral. Creating yTokens may be an efficient way for creators to borrow at a competitive fixed-rate by creating yTokens and selling them for any other desired token.

## Details of this implementation

A single "Treasurer" contract controls the yToken system. When the Treasurer is deployed, the deployer can specify an "owner" that has the power to set an oracle and to create new series of yTokens. Each individual series of yToken has its own ERC-20 contract, however, all functionality other than ERC-20 transfers is controlled by the Treasurer contract. For example, the Treasurer contract receives collateral, controls the creation of new yTokens, receives the signal to settle a yToken after maturity, and permits the creator and bearer to remove their funds after settlement.

Each creator of new yTokens for a series has an associated "Repo" that records the amount of collateral locked for the creation of her tokens, and the associated yToken debt that she will owe at maturity. The minimum collateral required for a repo is set by a Collateralization Ratio that is specified during the creation of the Treasurer. For example, this ratio might be set at 150% requiring 1.5 Dai worth of ETH for every Dai of yToken face value created. A Minimum Collateralization Ratio sets a floor after which anyone may liquidate some or all of a creator's repo by providing an amount of the appropriate yToken.

## Usage

### Creating a yToken

Any user may create yTokens of a particular series provided she deposits the appropriate amount of collateral.

1. Deposit ETH into the Treasurer
    The user may deposit ETH by paying a desired amount of ETH when calling the `join()` function.
2. Make the desired yToken amount
    The user may make the desired yToken by calling `make(uint series, uint made, uint paid)` and specifying the series (`series`) desired, the amount of yToken to make (`made`), and the amount of collateral to lock up (`paid`). The amount paid must be greater than the minimum collateral which equals the amount of yTokens made multiplied by the Collateralization Ratio.


### Redeeming a yToken

The holder of a Repo may wipe yToken debt in her repo by sending yToken back to the Treasurer. This is accomplished by calling `wipe(uint series, uint credit, uint released)` and specifying the series of the yToken, the amount of yToken debt to wipe (`credit`), and the amount of Ether collateral to be released (`released`). The caller must have sufficient yTokens to satisfy the credit or else the call will fail. Also, the call will fail if the user attempts to release more Ether collateral than the minimum collateral required for the remaining yToken debt.


### Settlement

After the maturity date for a series is reached, the yTokens for that series may be settled.  Settlement is achieved by fixing a Dai price in Ether that will be used to determine how much Ether collateral each yToken holder is permitted to withdraw as payment for her matured yToken. To initiate settlement after the maturity date, any user may call `settlement(uint series)` and specify the series (`series`) to be settled. After the settlement function is called, users may retrieve their funds. A user who holds yTokens to maturity may call `withdraw(uint series, uint256 amount)` specifying the series of the yToken, and the amount of yToken to settle and retrieve the associated Ether. Likewise, a repo holder may close her repo and retrieve the associated Ether by calling `close(uint series)` specifying the series of the yToken.

### Liquidation

In order to maintain sufficient collateralization for a repo, when a repo becomes close to becoming undercollateralized, any holder of yTokens of the appropriate series may tender the yTokens and liquidate some or all of the nearly-undercollateralized repo. A repo becomes available for liquidation when the amount of collateral drops below a minimum collateralization ratio. A holder of yToken may liquidate some or all of a repo by calling `liquidate(uint series, address bum, uint256 amount)` specifying a series of the yTokens to be liquidated, the address of the holder of the repo to be liquidated (the `bum`), and the amount of yTokens to contribute to the liquidation. 
