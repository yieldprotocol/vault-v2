const fs = require('fs')
const path = require('path')
import "@nomiclabs/hardhat-truffle5";
import "solidity-coverage";
import "hardhat-deploy";
import "hardhat-gas-reporter";

function nodeUrl(network: any) {
    let infuraKey
    try {
      infuraKey = fs.readFileSync(path.resolve(__dirname, '.infuraKey')).toString().trim()
    } catch(e) {
      infuraKey = ''
    }
    return `https://${network}.infura.io/v3/${infuraKey}`
  }
  
  let mnemonic = process.env.MNEMONIC;
  if (!mnemonic) {
    try {
      mnemonic = fs.readFileSync(path.resolve(__dirname, '.secret')).toString().trim()
    } catch(e){}
  }
  const accounts = mnemonic ? {
    mnemonic,
  }: undefined;

export default {
    defaultNetwork: "hardhat",
    networks: {
      kovan: {
        accounts,
        url: nodeUrl('kovan'),
        timeoutBlocks: 200,     // # of blocks before a deployment times out  (minimum/default: 50)
        gasPrice: 10000000000,  // 10 gwei
        skipDryRun: false       // Skip dry run before migrations? (default: false for public nets )
      },
      goerli: {
        accounts,
        url: nodeUrl('goerli'),
      },
      rinkeby: {
        accounts,
        url: nodeUrl('rinkeby')
      },
      ropsten: {
        accounts,
        url: nodeUrl('ropsten')
      },
      mainnet: {
        accounts,
        url: nodeUrl('mainnet'),
        timeoutBlocks: 200,     // # of blocks before a deployment times out  (minimum/default: 50)
        gasPrice: 50000000000,  // 50 gwei
        skipDryRun: false       // Skip dry run before migrations? (default: false for public nets )
      },
      coverage: {
        url: 'http://127.0.0.1:8555',
      },
    },
    solidity: {
        compilers: [
            {
              version: "0.8.0"
            },
            {
              version: "0.7.5",
              settings: { } 
            }
        ],
        settings: {
            optimizer: {
                enabled: true,
                runs: 20000
            },
        },
    },
    gasReporter: {
        enabled: true
    },
    paths: {
        artifacts: "./build",
        coverage: "./coverage",
        coverageJson: "./coverage.json",
    },
};