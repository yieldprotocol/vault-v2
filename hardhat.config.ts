import '@nomiclabs/hardhat-waffle'
import '@nomiclabs/hardhat-etherscan'
import 'hardhat-gas-reporter'
import 'hardhat-typechain'
import 'solidity-coverage'
import 'hardhat-deploy'


export default {
  defaultNetwork: 'hardhat',
  solidity: {
    version: '0.8.1',
    settings: {
      optimizer: {
        enabled: true,
        runs: 20000
      },
    }
  },
  namedAccounts: {
    deployer: 0,
    owner: 1,
    other: 2,
  },
  gasReporter: {
    enabled: true
  },
  typechain: {
    outDir: 'typechain',
    target: 'ethers-v5',
  },
};
