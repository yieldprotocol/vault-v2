# YieldSpace for Tokenized Vaults

#### DISCLAIMER: Please do not use in production without taking the appropriate steps to ensure maximum security. This code is provided as-is, with no guarantees of any kind.

---

`yieldspace-tv` is a new implementation of [Yieldspace](https://github.com/yieldprotocol/yieldspace-v2) that allows for the use of shares in tokenized vaults as base reserves. This is based on concepts and formulas derived in ["YieldSpace with Yield Bearing Vaults"](https://hackmd.io/lRZ4mgdrRgOpxZQXqKYlFw?both) by Allan Niemerg which was based on the original ["The Yield Protocol: On-Chain Lending With
Interest Rate Discovery"](https://yield.is/Yield.pdf) written by Dan Robinson and Allan Niemerg.

The pool is an [UniV2 style, x/y fixed constant automated market maker](https://uniswap.org/whitepaper.pdf) used for providing liquidity and trading a pair of "fyToken" and related underlying "base" token as described in the papers noted above. In this new version, the base tokens can now be tokenized vault shares.

The use of tokenized vaults as base allows for a higher yield on the base reserves held by the pool. The main changes in the math come from introducing `c` and `mu` into the equation. `c` represents the current value of the tokenized vault shares. `mu` is the _normalization factor_ which is the initial `c0` at first mint.

This repo also serves as Yield's initial foray into the [Foundry development tool](https://github.com/gakonst/foundry) ecosystem. Tests are written in Solidity and use Foundry [cheatcodes](https://github.com/gakonst/foundry/tree/master/forge#cheat-codes).

This repo includes:

- the [latest ABDK Math64x64 library](https://github.com/abdk-consulting/abdk-libraries-solidity/blob/master/ABDKMath64x64.sol), useful for managing large numbers with high precision in a gas optimized way
- custom math libraries ([YieldMath.sol](https://github.com/yieldprotocol/yieldspace-tv/blob/update-yieldmath/src/YieldMath.sol) and [Exp64x64.sol](https://github.com/yieldprotocol/yieldspace-tv/blob/update-yieldmath/src/Exp64x64.sol)) originally written by ABDK for Yield which have now been adapted for the new math
- Pool.sol contract based on the original but now incorporating the new YieldMath as well as some additional features
- [Foundry unit and fuzz tests](https://github.com/yieldprotocol/yieldspace-tv/tree/update-yieldmath/src/test)

Additional notes:

- If too many base tokens are sent to the mint functions (`mint` or `mintWithBase`), the extra base tokens will be sent back to the `to` address
- If too many tokens are sent in to `buyFYToken` or `buyBase`, those tokens are not sent back. The user can retrieve them with `retrieveFYToken` or `retrieveBase`.
- The remaining tokens in the buy functions will typically be small rounding differences and not worth the gas to send back. Also, changing the behavior of the buy functions to match the mint functions would be a breaking change. For that reason, we have chosen to leave the current behavior.

As this repo is still under development, these smart contracts have not yet been deployed.

Detailed documentation can be found in the [Yield docs](docs.yieldprotocol.com).

## Install

### Pre Requisites

Before running any command, [be sure Foundry is installed](https://github.com/gakonst/foundry#installation).

### Setup

```
git clone git@github.com:yieldprotocol/yieldspace-tv.git
cd yieldspace-tv
forge update
```

### Test

Compile and test the smart contracts with Forge:

```
forge test
```

If using forking capability, be sure to add `MAINNET_RPC` to your `.env`.

## Math

In developing this YieldSpace we have used two different libraries for fixed point arithmetic.

- For general use we have used a [decimal-based fixed point math library](https://github.com/yieldprotocol/fyDai/blob/master/contracts/helpers/DecimalMath.sol), trading off performance for clarity.
- For heavy-duty use in the YieldSpace formula, we have used the aforementioned [Math64x64, a binary-based fixed point math library](https://github.com/yieldprotocol/yieldspace-tv/blob/update-yieldmath/src/YieldMath.sol), trading off clarity for performance.

## Security

In developing the code in this repository we have set the highest bar possible for security. `yieldspace-tv` has been audited by [ABDK Consulting](https://www.abdk.consulting/) and the report can be found [here](https://github.com/yieldprotocol/yieldspace-tv/blob/main/audit/ABDK_Yield_yieldspace_tv_v_1_0.pdf).

We have also used fuzzing tests for the Pool and YieldMath contracts, allowing us to find edge cases and vulnerabilities that we would have missed otherwise.

## Bug Bounty

Yield is offering bounties for bugs disclosed through [Immunefi](https://immunefi.com/bounty/yieldprotocol). The bounty reward is up to $500,000, depending on severity. Please include full details of the vulnerability and steps/code to reproduce. We ask that you permit us time to review and remediate any findings before public disclosure.

## Contributing

This project doesn't include any governance or upgradability features. If you have a contribution to make, please reach us out on Discord and we will consider it for a future release or product.

## Acknowledgements

We would like to thank Dan Robinson (Paradigm), Georgios Konstantopoulos (Paradigm), SamCZSun (Paradigm), Mikhail Vladimirov (ABDK), Gustavo Grieco (Trail of Bits), Martin Lundfall (dAppHub), Noah Zinsmeister (Uniswap), and Transmissions11 (Paradigm) for their feedback and advice. We wouldn't be here without them.
