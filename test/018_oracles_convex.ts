import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
import { parseEther } from '@ethersproject/units'
import { ETH,CVX3CRV } from '../src/constants'

import { ChainlinkAggregatorV3Mock } from '../typechain/ChainlinkAggregatorV3Mock'
import {DummyConvexCurveOracle} from '../typechain/DummyConvexCurveOracle'
import {CurvePoolMock} from '../typechain/CurvePoolMock'

import ChainlinkAggregatorV3MockArtifact from '../artifacts/contracts/mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol/ChainlinkAggregatorV3Mock.json'
import DummyConvexCurveOracleArtifact from '../artifacts/contracts/oracles/convex/DummyConvexCurveOracle.sol/DummyConvexCurveOracle.json'
import CurvePoolMockArtifact from '../artifacts/contracts/mocks/oracles/convex/CurvePoolMock.sol/CurvePoolMock.json'
const { deployContract } = waffle

function bytes6ToBytes32(x: string): string {
  return x + '00'.repeat(26)
}

describe('Oracles - Convex', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let DummyConvexCurveOracle: DummyConvexCurveOracle
  let daiEthAggregator: ChainlinkAggregatorV3Mock
  let usdcEthAggregator: ChainlinkAggregatorV3Mock
  let usdtEthAggregator: ChainlinkAggregatorV3Mock
  let curvePool: CurvePoolMock

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
    curvePool = await deployContract(ownerAcc,CurvePoolMockArtifact) as unknown as CurvePoolMock
    await curvePool.set('1019568078072415210')
    usdcEthAggregator = (await deployContract(ownerAcc, ChainlinkAggregatorV3MockArtifact)) as unknown as ChainlinkAggregatorV3Mock
    daiEthAggregator = (await deployContract(ownerAcc, ChainlinkAggregatorV3MockArtifact)) as unknown as ChainlinkAggregatorV3Mock
    usdtEthAggregator = (await deployContract(ownerAcc, ChainlinkAggregatorV3MockArtifact)) as unknown as ChainlinkAggregatorV3Mock
    await usdcEthAggregator.set('230171858101077')
    await daiEthAggregator.set('230213930000000')
    await usdtEthAggregator.set('230334420255290')

    DummyConvexCurveOracle = (await deployContract(ownerAcc, DummyConvexCurveOracleArtifact, [
        bytes6ToBytes32(CVX3CRV),
        bytes6ToBytes32(ETH),
        curvePool.address,
        daiEthAggregator.address,
        usdcEthAggregator.address,
        usdtEthAggregator.address,
    ])) as unknown as DummyConvexCurveOracle
    
  })

  it('How many ETH for one cvx3CRV', async () => {
    const eth = (await DummyConvexCurveOracle.callStatic.get(bytes6ToBytes32(CVX3CRV), bytes6ToBytes32(ETH), parseEther('1')))[0]
    expect(eth).equals('234675878990471')
      // console.log((eth.toString()))
  })

  it('How many CVX3CRV for one ETH', async () => {
    const cvx3crv = (await DummyConvexCurveOracle.callStatic.get(bytes6ToBytes32(ETH), bytes6ToBytes32(CVX3CRV), parseEther('1')))[0]
    expect(cvx3crv).equals('4261196354315583239214')
  })
})