import { ethers, network, waffle } from 'hardhat'
import { YieldEnvironment } from './shared/fixtures'
import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { expect } from 'chai'
import { ETH, DAI, USDC } from '../src/constants'
import {
  Witch,
  Cauldron,
  FlashJoin,
  OracleMock,
  ERC20Mock,
  CollateralWand,
  ISourceMock,
  EmergencyBrake,
  FYToken,
} from '../typechain'

import CollateralWandArtifact from '../artifacts/@yield-protocol/vault-v2/contracts/CollateralWand.sol/CollateralWand.json'
import FlashJoinArtifact from '../artifacts/@yield-protocol/vault-v2/contracts/FlashJoin.sol/FlashJoin.json'
import ERC20MockArtifact from '../artifacts/@yield-protocol/vault-v2/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import EmergencyBrakeArtifact from '../artifacts/@yield-protocol/utils-v2/contracts/utils/EmergencyBrake.sol/EmergencyBrake.json'
import ChainlinkAggregatorV3MockArtifact from '../artifacts/@yield-protocol/vault-v2/contracts/mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol/ChainlinkAggregatorV3Mock.json'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { LadleWrapper } from '../src/ladleWrapper'
import { BigNumber } from 'ethers'

const { deployContract } = waffle

function bytesToString(bytes: string): string {
  return ethers.utils.parseBytes32String(bytes + '0'.repeat(66 - bytes.length))
}
function stringToBytes32(x: string): string {
  return ethers.utils.formatBytes32String(x)
}
function bytesToBytes32(bytes: string): string {
  return stringToBytes32(bytesToString(bytes))
}

const TESTASSET = ethers.utils.formatBytes32String('10').slice(0, 14)

/**
 * @dev This script tests the CollateralWand
 */
describe('Chainlink Collateral Wand-V2', async function () {
  this.timeout(0)

  let ladle: LadleWrapper
  let witch: Witch

  let ownerAcc: SignerWithAddress
  let dummyAcc: SignerWithAddress
  let cauldron: Cauldron

  let collateralWand: CollateralWand

  let joinNew: FlashJoin
  let asset: ERC20Mock
  let aggregator: ISourceMock
  let cloak: EmergencyBrake
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  let env: YieldEnvironment

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [USDC, DAI, ETH], [seriesId])
  }

  before(async () => {
    this.timeout(0)

    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    dummyAcc = signers[1]
    env = await fixture()
    ladle = env.ladle
    witch = env.witch
    cauldron = env.cauldron

    cloak = (await deployContract(ownerAcc, EmergencyBrakeArtifact, [
      ownerAcc.address,
      ownerAcc.address,
    ])) as EmergencyBrake

    collateralWand = (await deployContract(ownerAcc, CollateralWandArtifact, [
      cauldron.address,
      ladle.address,
      witch.address,
      cloak.address,
      env.spotOracle.address,
    ])) as unknown as CollateralWand

    await collateralWand.grantRole(
      id(
        collateralWand.interface,
        'addChainlinkCollateral(bytes6,address,address,address,(bytes6,address,bytes6,address,address)[],(bytes6,uint32,uint64,uint96,uint24,uint8)[],(bytes6,bytes6,uint32,uint96,uint24,uint8)[],(bytes6,bytes6[])[])'
      ),
      ownerAcc.address
    )

    //Create asset
    asset = (await deployContract(ownerAcc, ERC20MockArtifact, ['Test', 'TEST'])) as ERC20Mock

    // Chainlink
    aggregator = (await deployContract(ownerAcc, ChainlinkAggregatorV3MockArtifact)) as ISourceMock
    await aggregator.set(WAD)

    joinNew = (await deployContract(ownerAcc, FlashJoinArtifact, [asset.address])) as FlashJoin
    // Giving relevant permissions to the collateral wand
    await joinNew.grantRoles([id(joinNew.interface, 'grantRoles(bytes4[],address)')], collateralWand.address)
    await joinNew.grantRole('0x00000000', collateralWand.address)
    await cauldron.grantRoles(
      [
        id(cauldron.interface, 'addAsset(bytes6,address)'),
        id(cauldron.interface, 'addIlks(bytes6,bytes6[])'),
        id(cauldron.interface, 'setSpotOracle(bytes6,bytes6,address,uint32)'),
        id(cauldron.interface, 'setDebtLimits(bytes6,bytes6,uint96,uint24,uint8)'),
      ],
      collateralWand.address
    )
    await ladle.grantRoles([id(ladle.ladle.interface, 'addJoin(bytes6,address)')], collateralWand.address)

    let spotOracle: OracleMock = env.oracles.get(USDC) as OracleMock
    await spotOracle.grantRole(
      id(spotOracle.interface, 'setSource(bytes6,address,bytes6,address,address)'),
      collateralWand.address
    )
    await cloak.grantRoles([id(cloak.interface, 'plan(address,(address,bytes4[])[])')], collateralWand.address)
    await cloak.grantRole('0x00000000', collateralWand.address)
    await witch.grantRoles(
      [
        id(witch.interface, 'point(bytes32,address)'),
        id(witch.interface, 'setIlk(bytes6,uint32,uint64,uint96,uint24,uint8)'),
      ],
      collateralWand.address
    )
  })

  it('Add collateral', async () => {
    await collateralWand.addChainlinkCollateral(
      TESTASSET,
      asset.address,
      joinNew.address,
      ownerAcc.address,
      [
        {
          baseId: ETH,
          base: await cauldron.assets(ETH),
          quoteId: TESTASSET,
          quote: asset.address,
          source: aggregator.address,
        },
      ],
      [
        {
          ilkId: TESTASSET,
          duration: 3600,
          initialOffer: 1000000000000000000,
          line: 1000000,
          dust: 5000,
          dec: 18,
        },
      ],
      [
        {
          baseId: USDC,
          ilkId: TESTASSET,
          ratio: 1000000,
          line: 10000000,
          dust: 0,
          dec: 18,
        },
      ],
      [
        {
          series: seriesId,
          ilkIds: [TESTASSET],
        },
      ]
    )
  })

  it('Borrow on new collateral', async () => {
    let ilk = TESTASSET
    var collateral = (await ethers.getContractAt(
      'ERC20Mock',
      await cauldron.callStatic.assets(ilk),
      ownerAcc
    )) as unknown as ERC20Mock
    let oracle: OracleMock = env.oracles.get(USDC) as OracleMock

    await collateral.connect(ownerAcc).mint(ownerAcc.address, WAD.mul(1000000000))

    console.log(`series: ${seriesId}`)
    console.log(`ilk: ${ilk}`)
    const series = await cauldron.series(seriesId)

    const fyToken = (await ethers.getContractAt('FYToken', series.fyToken, ownerAcc)) as unknown as FYToken

    const ratio = (await cauldron.spotOracles(series.baseId, ilk)).ratio
    var borrowed = BigNumber.from(10)
      .pow(await fyToken.decimals())
      .mul(10)

    const posted = (await oracle?.peek(bytesToBytes32(series.baseId), bytesToBytes32(ilk), borrowed))[0]
      .mul(ratio)
      .div(1000000)
      .mul(101)
      .div(100)

    const collateralBalanceBefore = await collateral.balanceOf(ownerAcc.address)

    // Build vault
    await ladle.connect(ownerAcc).build(seriesId, ilk)
    const logs = await cauldron.queryFilter(cauldron.filters.VaultBuilt(null, null, null, null))
    const vaultId = logs[logs.length - 1].args.vaultId
    console.log(`vault: ${vaultId}`)

    var name = await fyToken.callStatic.name()
    // Post collateral and borrow
    const collateralJoinAddress = await ladle.joins(ilk)

    console.log(`posting ${posted} ilk out of ${await collateral.balanceOf(ownerAcc.address)}`)
    await collateral.connect(ownerAcc).transfer(collateralJoinAddress, posted)
    console.log(`borrowing ${borrowed} ${name}`)
    await ladle.connect(ownerAcc).pour(vaultId, ownerAcc.address, posted, borrowed)
    console.log(`posted and borrowed`)

    if ((await cauldron.balances(vaultId)).art.toString() !== borrowed.toString()) throw 'art mismatch'
    if ((await cauldron.balances(vaultId)).ink.toString() !== posted.toString()) throw 'ink mismatch'

    // Repay fyFRAX and withdraw collateral
    await fyToken.connect(ownerAcc).transfer(fyToken.address, borrowed)
    console.log(`repaying ${borrowed} ${name} and withdrawing ${posted} ilk`)
    await ladle.connect(ownerAcc).pour(vaultId, ownerAcc.address, posted.mul(-1), borrowed.mul(-1))
    console.log(`repaid and withdrawn`)
    expect(await collateral.balanceOf(ownerAcc.address)).to.be.eq(collateralBalanceBefore)
  })
})
