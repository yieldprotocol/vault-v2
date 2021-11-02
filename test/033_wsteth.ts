import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { ethers, waffle } from 'hardhat'

import { ETH, DAI, USDC, WSTETH, STETH } from '../src/constants'
import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants

import { getLastVaultId } from '../src/helpers'
import { parseEther } from 'ethers/lib/utils'
const { loadFixture } = waffle
const { deployContract } = waffle

import { Cauldron } from '../typechain/Cauldron'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { LidoOracle } from '../typechain/LidoOracle'
import { LidoMock } from '../typechain/LidoMock'
import { STETHMock } from '../typechain/STETHMock'
import { ChainlinkAggregatorV3Mock } from '../typechain/ChainlinkAggregatorV3Mock'
import { YieldEnvironment } from './shared/fixtures'
import { ChainlinkMultiOracle } from '../typechain/ChainlinkMultiOracle'
import { CompositeMultiOracle } from '../typechain/CompositeMultiOracle'
import { expect } from 'chai'
import { Wand } from '../typechain/Wand'
import { Witch } from '../typechain/Witch'
import { WETH9Mock } from '../typechain/WETH9Mock'
import { PoolMock } from '../typechain/PoolMock'
import { ISourceMock } from '../typechain/ISourceMock'
import { USDCMock } from '../typechain/USDCMock'

import LidoOracleArtifact from '../artifacts/contracts/oracles/lido/LidoOracle.sol/LidoOracle.json'
import CompositeMultiOracleArtifact from '../artifacts/contracts/oracles/composite/CompositeMultiOracle.sol/CompositeMultiOracle.json'
import ChainlinkAggregatorV3MockArtifact from '../artifacts/contracts/mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol/ChainlinkAggregatorV3Mock.json'
import USDCMockArtifact from '../artifacts/contracts/mocks/USDCMock.sol/USDCMock.json'
import STETHMockArtifact from '../artifacts/contracts/mocks/STETHMock.sol/STETHMock.json'
import WETH9MockArtifact from '../artifacts/contracts/mocks/WETH9Mock.sol/WETH9Mock.json'
import LidoMockArtifact from '../artifacts/contracts/mocks/oracles/lido/LidoMock.sol/LidoMock.json'
import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'

var WSTETHADD = '0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0'

function bytes6ToBytes32(x: string): string {
  return x + '00'.repeat(26)
}

describe('WstETH', function () {
  this.timeout(0)
  let ownerAcc: SignerWithAddress
  let owner: string
  let env: YieldEnvironment
  let cauldron: Cauldron
  let wand: Wand
  let witch: Witch
  let fyToken: FYToken
  let usdc: USDCMock
  let wsteth: ERC20Mock
  let steth: STETHMock
  let chainlinkMultiOracle: ChainlinkMultiOracle
  let compositeMultiOracle: CompositeMultiOracle
  let lidoOracle: LidoOracle
  let lidoMock: LidoMock
  let stethEthAggregator: ChainlinkAggregatorV3Mock
  let weth: WETH9Mock

  const baseId = USDC
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  const oneUSDC = WAD.div(1000000000000)

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [USDC, ETH], [seriesId])
  }

  beforeEach(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
    env = await loadFixture(fixture)

    wand = env.wand
    witch = env.witch
    cauldron = env.cauldron

    usdc = env.assets.get(USDC) as USDCMock
    weth = (env.assets.get(ETH) as unknown) as WETH9Mock
    steth = (await deployContract(ownerAcc, STETHMockArtifact)) as STETHMock
    wsteth = (await deployContract(ownerAcc, ERC20MockArtifact, [
      'Wrapped liquid staked Ether 2.0',
      'wstETH',
    ])) as ERC20Mock

    await wsteth.mint(ownerAcc.address, parseEther('1000000'))
    WSTETHADD = wsteth.address

    // Get ChainlinkMultiOracle
    chainlinkMultiOracle = (env.oracles.get(ETH) as unknown) as ChainlinkMultiOracle
    const usdcSource = (await ethers.getContractAt(
      'ISourceMock',
      (await chainlinkMultiOracle.sources(USDC, ETH))[0]
    )) as ISourceMock
    await usdcSource.set(WAD.div(2500)) // ETH wei per USDC

    // Setting up Lido Oracle
    lidoMock = (await deployContract(ownerAcc, LidoMockArtifact)) as LidoMock
    lidoOracle = (await deployContract(ownerAcc, LidoOracleArtifact, [
      bytes6ToBytes32(WSTETH),
      bytes6ToBytes32(STETH),
    ])) as LidoOracle
    await lidoOracle.grantRole(id(lidoOracle.interface, 'setSource(address)'), owner)
    await lidoOracle['setSource(address)'](lidoMock.address) //mockOracle
    await lidoMock.set('1008339308050006006')
    console.log('here2')
    // Setting up stethEth Chainlink oracle
    stethEthAggregator = (await deployContract(
      ownerAcc,
      ChainlinkAggregatorV3MockArtifact
    )) as ChainlinkAggregatorV3Mock
    await stethEthAggregator.set('992966330000000000')
    await chainlinkMultiOracle.setSource(STETH, steth.address, ETH, weth.address, stethEthAggregator.address)

    // Setting up composite multi oracle
    compositeMultiOracle = (await deployContract(ownerAcc, CompositeMultiOracleArtifact)) as CompositeMultiOracle
    await compositeMultiOracle.grantRoles(
      [
        id(compositeMultiOracle.interface, 'setSource(bytes6,bytes6,address)'),
        id(compositeMultiOracle.interface, 'setPath(bytes6,bytes6,bytes6[])'),
      ],
      owner
    )
    console.log('here3')
    // Set up the CompositeMultiOracle to draw from the ChainlinkMultiOracle
    await compositeMultiOracle.setSource(WSTETH, STETH, lidoOracle.address)
    await compositeMultiOracle.setSource(STETH, ETH, chainlinkMultiOracle.address)
    await compositeMultiOracle.setSource(USDC, ETH, chainlinkMultiOracle.address)

    // Set path for wsteth-steth-eth.USDC
    await compositeMultiOracle.setPath(WSTETH, USDC, [STETH, ETH])
  })

  it('WstETH could be added as an asset', async () => {
    console.log('here')
    await wand.addAsset(WSTETH, WSTETHADD)
  })

  it('Make WstETH into an ilk', async () => {
    await witch.setIlk(WSTETH, 4 * 60 * 60, WAD.div(2), 1000000, 0, 18)
    await wand.makeIlk(USDC, WSTETH, lidoOracle.address, 1000000, 1000000, 1000000, 6)
  })

  it('Borrow USDC with wstETH collateral', async () => {
    await cauldron.grantRoles([id(cauldron.interface, 'addIlks(bytes6,bytes6[])')], owner)
    await cauldron.addIlks(seriesId, [WSTETH])

    // Build a vault
    await env.ladle.build(seriesId, WSTETH)
    var vaultId = await getLastVaultId(cauldron)

    var join = await env.ladle.joins(WSTETH)

    // Transfer the amount to join before pouring
    await wsteth.transfer(join, parseEther('1'))

    // Pour the amount into the pool & borrow
    expect(await env.ladle.pour(vaultId, ownerAcc.address, parseEther('0.5'), parseEther('0.000001'))).to.emit(
      cauldron,
      'VaultPoured'
    )

    expect(await fyToken.balanceOf(ownerAcc.address)).to.eq(parseEther('0.000001'))
  })
})
