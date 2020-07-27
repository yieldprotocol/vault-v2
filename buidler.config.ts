import { usePlugin } from "@nomiclabs/buidler/config";

usePlugin("@nomiclabs/buidler-truffle5");
usePlugin("solidity-coverage");
usePlugin("buidler-gas-reporter");

export default {
    defaultNetwork: "buidlerevm",
    solc: {
        version: "0.6.10",
        optimizer: {
            enabled: true,
            runs: 200
        },
    },
    gasReporter: {
        enabled: true
    },
    paths: {
        artifacts: "./build"
    }
};
