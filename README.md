# YieldToken
YieldToken is an implementation of zero-coupon Dai bonds. It is inspired by the paper ["The Yield Protocol: On-Chain Lending With
Interest Rate Discovery"](https://yield.is/Yield.pdf) by Dan Robinson and Allan Niemerg.

These smart contracts have been deployed to [Kovan and the Mainnet](http://docs.yield.is), and a web frontend is deployed at [http://app.yield.is](http://app.yield.is)

Detailed documentation can be found in the [Yield docs](http://docs.yield.is).

## Warning
This code is provided as-is, with no guarantees of any kind.

## Install


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
Compile and test the smart contracts with [Buidler](https://buidler.dev/) and Mocha:

```
$ yarn test
```

### Fuzz
You will need to install [echidna](https://github.com/crytic/echidna) separately, and then run:

```
$ echidna-test . --contract WhitepaperInvariant --config contracts/invariants/config.yaml
```

### Start a local blockchain
We use [ganache](https://www.trufflesuite.com/ganache) as a local blockchain:

```
$ yarn ganache
```

### Start a local copy of the mainnet blockchain
We use [ganache](https://www.trufflesuite.com/ganache) to fork the mainnet blockchain:

```
$ yarn mainnet-ganache
```

### Migrate
We use [truffle](https://www.trufflesuite.com/) for migrations, make sure that `truffle-config.js` suits your use case, start a local ganache instance as explained above, and then run truffle:

```
$ npx truffle migrate
```

or

```
$ npx truffle migrate --network mainnet-ganache
```

## Math
In developing fyDai we have used two different libraries for fixed point arithmetic.
 - For general use we have used a [decimal-based fixed point math library](https://github.com/yieldprotocol/fyDai/blob/master/contracts/helpers/DecimalMath.sol), trading off performance for clarity.
 - For heavy-duty use in the YieldSpace formula, we have used a [binary-based fixed point math library](https://github.com/yieldprotocol/fyDai/blob/master/contracts/pool/YieldMath.sol), trading off clarity for performance.

## Security
In developing the code in this repository we have set the highest bar possible for security. We have been fully audited by [Trail of Bits](https://www.trailofbits.com/), with the [results](http://www.yield.is) publicly available. We have also used fuzzing tests for the Pool and YieldMath contracts, allowing us to find edge cases and vulnerabilities that we would have missed otherwise.

## Bug Bounty
Yield is offering bounties for bugs disclosed to us at [security@yield.is](mailto:security@yield.is). The bounty reward is up to $25,000, depending on severity. Please include full details of the vulnerability and steps/code to reproduce. We ask that you permit us time to review and remediate any findings before public disclosure.

## Contributing
This project doesn't include any governance or upgradability features. If you have a contribution to make, please reach us out on Discord and we will consider it for a future release or product.

## Acknowledgements
We would like to thank Dan Robinson (Paradigm), Georgios Konstantopoulos (Paradigm), Sam Sun (Paradigm), Mikhail Vladimirov (ABDK), Gustavo Grieco (Trail of Bits), Martin Lundfall (dAppHub) and Noah Zinsmeister (Uniswap) for their feedback and advice. We wouldn't be here without them.

## License
All files in this repository are released under the [GPLv3](https://github.com/yieldprotocol/fyDai/blob/master/LICENSE.md) license.
