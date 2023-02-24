const addresses = {
  '1' : {
      'supportedTokens': [
        "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", // WETH
        "0x6B175474E89094C44Da98b954EedeAC495271d0F", // DAI
      ],
  },
  '42' : {
      'supportedTokens': [
        "0xd0A1E359811322d97991E03f863a0C30C2cF029C", // WETH
        "0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa", // DAI
      ],
  }
}

const func = async function ({ deployments, getNamedAccounts, getChainId }) {
  const { deploy, read, execute } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId()

  if (chainId === '31337') { // buidlerevm's chainId
    console.log('Local deployments not implemented')
    return
  } else {
    const lender = await deploy('FlashLender', {
      from: deployer,
      deterministicDeployment: true,
      args: [
        addresses[chainId]['supportedTokens'],
        10000,
      ],
    })
    console.log(`Deployed FlashLender to ${lender.address}`);
  }
};

module.exports = func;
module.exports.tags = ["FlashLender"];