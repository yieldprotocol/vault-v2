usePlugin("@nomiclabs/buidler-truffle5");
usePlugin("solidity-coverage");
usePlugin("buidler-gas-reporter");

module.exports = {
    solc: {
        version: "0.6.2"
    },
    gasReporter: {
        enabled: true
    }
};