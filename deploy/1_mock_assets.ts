import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
// import { ERC20Mock } from '../typechain/ERC20Mock'
// import { ethers } from 'hardhat'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {deployer} = await hre.getNamedAccounts();
  const {deploy, execute, get, read} = hre.deployments;
  const useProxy = !hre.network.live;

  const assetIds = ['BASE', 'ILK1', 'ILK2']
  const assets: Array<string> = []
  for (let assetId of assetIds) {
    // proxy only in non-live network (localhost and hardhat network) enabling HCR (Hot Contract Replacement)
    // in live network, proxy is disabled and constructor is invoked
    console.log(`Here: ${deployer}`)
    const deployment = await deploy(assetId, {
      from: deployer,
      contract: 'ERC20Mock',
      deterministicDeployment: true,
      // proxy: useProxy && 'postUpgrade',
      args: [assetId, assetId],
      log: true,
    });
    // const ERC20 = await ethers.getContract(assetId, deployer) or https://docs.ethers.io/v5/api/contract/example/
    await execute(assetId, { from: deployer }, 'approve', deployer, 1)
    console.log(`Deployed ${assetId} to ${deployment.address}`);
    assets.push(deployment.address)
    // (await get('ERC20Mock'))
  }

  // return !useProxy; // when live network, record the script as executed to prevent rexecution
};
export default func;
func.id = 'mock_assets'; // id required to prevent reexecution
func.tags = ['MockAssets'];
