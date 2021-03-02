import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  // do nothing
};
export default func;

func.id = 'deploy_test'
func.tags = ['DeployTest'];
func.dependencies = ['MockAssets'];