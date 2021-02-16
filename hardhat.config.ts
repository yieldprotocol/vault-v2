import "@nomiclabs/hardhat-waffle";
import "hardhat-typechain";
import "solidity-coverage";

export default {
  defaultNetwork: "hardhat",
  solidity: {
    version: "0.8.1",
    settings: {
      optimizer: {
        enabled: true,
        runs: 20000
      },
    }
  },
  gasReporter: {
    enabled: true
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v5",
  },
};
