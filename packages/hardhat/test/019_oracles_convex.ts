import { ethers, waffle } from 'hardhat'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { expect } from 'chai'
import { parseEther } from '@ethersproject/units'
import { ETH, CVX3CRV, USDC, DAI } from '../src/constants'

import { ChainlinkAggregatorV3Mock } from '../typechain/ChainlinkAggregatorV3Mock'
import { Cvx3CrvOracle } from '../typechain/Cvx3CrvOracle'
import { CurvePoolMock } from '../typechain/CurvePoolMock'
import { ChainlinkMultiOracle } from '../typechain/ChainlinkMultiOracle'
import { CompositeMultiOracle } from '../typechain/CompositeMultiOracle'

import ChainlinkAggregatorV3MockArtifact from '../artifacts/@yield-protocol/vault-v2//contracts/mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol/ChainlinkAggregatorV3Mock.json'
import Cvx3CrvOracleArtifact from '../artifacts/@yield-protocol/vault-v2//contracts/oracles/convex/Cvx3CrvOracle.sol/Cvx3CrvOracle.json'
import CurvePoolMockArtifact from '../artifacts/@yield-protocol/vault-v2//contracts/mocks/oracles/convex/CurvePoolMock.sol/CurvePoolMock.json'
import ChainlinkMultiOracleArtifact from '../artifacts/@yield-protocol/vault-v2//contracts/oracles/chainlink/ChainlinkMultiOracle.sol/ChainlinkMultiOracle.json'
import CompositeMultiOracleArtifact from '../artifacts/@yield-protocol/vault-v2//contracts/oracles/composite/CompositeMultiOracle.sol/CompositeMultiOracle.json'
import WETH9MockArtifact from '../artifacts/@yield-protocol/vault-v2//contracts/mocks/WETH9Mock.sol/WETH9Mock.json'
import DAIMockArtifact from '../artifacts/@yield-protocol/vault-v2//contracts/mocks/DAIMock.sol/DAIMock.json'
import USDCMockArtifact from '../artifacts/@yield-protocol/vault-v2//contracts/mocks/USDCMock.sol/USDCMock.json'

import { id } from '@yield-protocol/utils-v2'
import { DAIMock, USDCMock, WETH9Mock } from '../typechain'
const { deployContract } = waffle

function bytes6ToBytes32(x: string): string {
  return x + '00'.repeat(26)
}

describe('Oracles - Convex', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let dummyAcc: SignerWithAddress
  let owner: string
  let cvx3CrvOracle: Cvx3CrvOracle
  let daiEthAggregator: ChainlinkAggregatorV3Mock
  let usdcEthAggregator: ChainlinkAggregatorV3Mock
  let usdtEthAggregator: ChainlinkAggregatorV3Mock
  let curvePool: CurvePoolMock

  let weth: WETH9Mock
  let dai: DAIMock
  let usdc: USDCMock

  let chainlinkMultiOracle: ChainlinkMultiOracle
  let compositeMultiOracle: CompositeMultiOracle

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
    dummyAcc = signers[1]

    weth = (await deployContract(ownerAcc, WETH9MockArtifact)) as WETH9Mock
    usdc = (await deployContract(ownerAcc, USDCMockArtifact)) as USDCMock
    dai = (await deployContract(ownerAcc, DAIMockArtifact)) as DAIMock

    curvePool = (await deployContract(ownerAcc, CurvePoolMockArtifact)) as unknown as CurvePoolMock
    await curvePool.set('1019568078072415210')
    usdcEthAggregator = (await deployContract(
      ownerAcc,
      ChainlinkAggregatorV3MockArtifact
    )) as unknown as ChainlinkAggregatorV3Mock
    daiEthAggregator = (await deployContract(
      ownerAcc,
      ChainlinkAggregatorV3MockArtifact
    )) as unknown as ChainlinkAggregatorV3Mock
    usdtEthAggregator = (await deployContract(
      ownerAcc,
      ChainlinkAggregatorV3MockArtifact
    )) as unknown as ChainlinkAggregatorV3Mock
    await usdcEthAggregator.set('230171858101077')
    await daiEthAggregator.set('230213930000000')
    await usdtEthAggregator.set('230334420255290')

    chainlinkMultiOracle = (await deployContract(ownerAcc, ChainlinkMultiOracleArtifact, [])) as ChainlinkMultiOracle
    await chainlinkMultiOracle.grantRole(
      id(chainlinkMultiOracle.interface, 'setSource(bytes6,address,bytes6,address,address)'),
      owner
    )

    //Set DAI/ETH chainlink oracle
    await chainlinkMultiOracle.setSource(DAI, dai.address, ETH, weth.address, daiEthAggregator.address)
    //Set USDC/ETH chainlink oracle
    await chainlinkMultiOracle.setSource(USDC, usdc.address, ETH, weth.address, usdcEthAggregator.address)

    compositeMultiOracle = (await deployContract(ownerAcc, CompositeMultiOracleArtifact)) as CompositeMultiOracle
    compositeMultiOracle.grantRoles(
      [
        id(compositeMultiOracle.interface, 'setSource(bytes6,bytes6,address)'),
        id(compositeMultiOracle.interface, 'setPath(bytes6,bytes6,bytes6[])'),
      ],
      owner
    )

    cvx3CrvOracle = (await deployContract(ownerAcc, Cvx3CrvOracleArtifact)) as unknown as Cvx3CrvOracle

    await cvx3CrvOracle.grantRole(
      id(cvx3CrvOracle.interface, 'setSource(bytes32,bytes32,address,address,address,address)'),
      owner
    )
    await cvx3CrvOracle['setSource(bytes32,bytes32,address,address,address,address)'](
      bytes6ToBytes32(CVX3CRV),
      bytes6ToBytes32(ETH),
      curvePool.address,
      daiEthAggregator.address,
      usdcEthAggregator.address,
      usdtEthAggregator.address
    )

    // Set up the CompositeMultiOracle to draw from the ChainlinkMultiOracle
    await compositeMultiOracle.setSource(CVX3CRV, ETH, cvx3CrvOracle.address)
    await compositeMultiOracle.setSource(DAI, ETH, chainlinkMultiOracle.address)
    await compositeMultiOracle.setSource(USDC, ETH, chainlinkMultiOracle.address)
    await compositeMultiOracle.setPath(DAI, CVX3CRV, [ETH])
    await compositeMultiOracle.setPath(USDC, CVX3CRV, [ETH])
  })

  it('cvx3CRV->ETH', async () => {
    const eth = (await cvx3CrvOracle.callStatic.get(bytes6ToBytes32(CVX3CRV), bytes6ToBytes32(ETH), parseEther('1')))[0]
    expect(eth.toString()).equals('234675878990471')
  })

  it('ETH->cvx3CRV', async () => {
    const cvx3crv = (
      await cvx3CrvOracle.callStatic.get(bytes6ToBytes32(ETH), bytes6ToBytes32(CVX3CRV), parseEther('1'))
    )[0]
    expect(cvx3crv.toString()).equals('4261196354315583239214')
  })

  describe('Composite', () => {
    it('retrieves the value at spot price for direct pairs', async () => {
      // DAI-ETH
      expect(
        (await compositeMultiOracle.peek(bytes6ToBytes32(DAI), bytes6ToBytes32(ETH), parseEther('1')))[0]
      ).to.equal('230213930000000')
      expect(
        (await compositeMultiOracle.peek(bytes6ToBytes32(ETH), bytes6ToBytes32(DAI), parseEther('1')))[0]
      ).to.equal('4343785799582153868794')

      // USDC-ETH
      expect((await compositeMultiOracle.peek(bytes6ToBytes32(USDC), bytes6ToBytes32(ETH), '1000000'))[0]).to.equal(
        '230171858101077'
      )
      expect(
        (await compositeMultiOracle.peek(bytes6ToBytes32(ETH), bytes6ToBytes32(USDC), parseEther('1')))[0]
      ).to.equal('4344579777')
    })

    it('retrieves the value at spot price for CVX3CRV -> DAI and reverse', async () => {
      expect(
        (await compositeMultiOracle.peek(bytes6ToBytes32(DAI), bytes6ToBytes32(CVX3CRV), parseEther('1')))[0]
      ).to.equal('980986759228662877')

      expect(
        (await compositeMultiOracle.peek(bytes6ToBytes32(CVX3CRV), bytes6ToBytes32(DAI), parseEther('1')))[0]
      ).to.equal('1019381750663267856')
    })

    it('retrieves the value at spot price for CVX3CRV -> USDC and reverse', async () => {
      expect(
        (await compositeMultiOracle.peek(bytes6ToBytes32(CVX3CRV), bytes6ToBytes32(USDC), parseEther('1')))[0]
      ).to.equal('1019568')

      expect((await compositeMultiOracle.peek(bytes6ToBytes32(USDC), bytes6ToBytes32(CVX3CRV), '1000000'))[0]).to.equal(
        '980807482606353056'
      )
    })
  })
})
