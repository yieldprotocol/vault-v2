usePlugin("@nomiclabs/buidler-truffle5");
usePlugin("solidity-coverage");
usePlugin("buidler-gas-reporter");

module.exports = {
    solc: {
        version: "0.6.2",
        optimizer: {
            enabled: true,
            runs: 20000
        },
    },
    gasReporter: {
        enabled: true
    }
};