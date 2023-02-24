const func = async function ({ deployments, getNamedAccounts, getChainId }) {
  const { deploy, read, execute } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId()

  if (chainId === '31337') { // buidlerevm's chainId
    console.log('Local deployments not implemented')
    return
  } else {
    const lender = await deploy('FlashMinter', {
      from: deployer,
      deterministicDeployment: true,
      args: [
        "FlashMinter",
        "FLS",
        "115792089237316195423570985008687907853269984665640564039457584007913129639935",
      ],
    })
    console.log(`Deployed FlashMinter to ${lender.address}`);
  }
};

module.exports = func;
module.exports.tags = ["FlashMinter"];