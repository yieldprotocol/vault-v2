const func = async function ({ deployments, getNamedAccounts, getChainId }) {
  const { deploy, read, execute } = deployments
  const { deployer } = await getNamedAccounts()
  const chainId = await getChainId()

  const assetIds = ['BASE', 'ILK1', 'ILK2']
  // const assets
  for (let assetId of assetIds) {
    /*
    const asset = await deploy('ERC20Mock', {
      from: deployer,
      deterministicDeployment: true,
      args: [assetId, assetId]
    });
    assets.push(asset)
    // await execute('ERC20Mock', { from: deployer }, 'approve', join.address, MAX)
    console.log(`Deployed ${assetId} to ${asset.address}`);
    */
  }
}

module.exports = func;
module.exports.tags = ["MockAssets"]
