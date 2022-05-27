import { ethers, network, waffle } from 'hardhat'
import { YieldEnvironment } from './shared/fixtures'
import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { expect } from 'chai'
import { ETH, DAI, USDC } from '../src/constants'
import {
  Wand,
  Witch,
  Cauldron,
  SeriesWand,
  YieldMath,
  FlashJoin,
  DAIMock,
  FYToken,
  OracleMock,
  ERC20Mock,
  CollateralWand,
  ISourceMock,
  AggregatorV3Interface,
  EmergencyBrake,
  Pool,
} from '../typechain'

import YieldMathArtifact from '../artifacts/@yield-protocol/yieldspace-v2/contracts/YieldMath.sol/YieldMath.json'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { LadleWrapper } from '../src/ladleWrapper'
import { BigNumber } from '@ethersproject/bignumber'
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
const ONE64 = BigNumber.from('18446744073709551616') // In 64.64 format
const secondsInOneYear = BigNumber.from(31557600)
const secondsIn30Years = secondsInOneYear.mul(30) // Seconds in 30 years

/**
 * @dev This script tests the SeriesWand
 */
describe('Chainlink Series Wand-V2', async function () {
  this.timeout(0)

  let ladle: LadleWrapper
  let witch: Witch
  let yieldMath: YieldMath
  let ownerAcc: SignerWithAddress
  let dummyAcc: SignerWithAddress
  let cauldron: Cauldron
  let wand: SeriesWand
  let join: FlashJoin
  let fyToken: FYToken
  let pool: Pool
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const seriesId3 = ethers.utils.hexlify(ethers.utils.randomBytes(6))

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

    yieldMath = (await deployContract(ownerAcc, YieldMathArtifact)) as YieldMath

    const wandFactory = await ethers.getContractFactory('SeriesWand')
    wand = (await wandFactory.deploy(cauldron.address, ladle.address)) as unknown as SeriesWand

    join = (await ethers.getContractAt('FlashJoin', await ladle.joins(USDC))) as FlashJoin

    await join.grantRoles([id(join.interface, 'grantRoles(bytes4[],address)')], wand.address)
    await join.grantRole('0x00000000', wand.address)
    await cauldron.grantRoles(
      [id(cauldron.interface, 'addSeries(bytes6,bytes6,address)'), id(cauldron.interface, 'addIlks(bytes6,bytes6[])')],
      wand.address
    )
    await ladle.grantRoles([id(ladle.ladle.interface, 'addPool(bytes6,address)')], wand.address)
    await wand.grantRole(id(wand.interface, 'addSeries(bytes6,bytes6,bytes6[],address,address)'), ownerAcc.address)

    //Deploy Fytoken
    const fyTokenFactory = await ethers.getContractFactory('FYToken', {
      libraries: {
        SafeERC20Namer: env.safeERC20NamerLibrary.address,
      },
    })
    fyToken = (await fyTokenFactory.deploy(
      USDC,
      env.spotOracle.address,
      join.address,
      BigNumber.from('1680271200'), // Maturity
      'temp', // Name
      'temp' // Symbol
    )) as unknown as FYToken
    await fyToken.grantRole('0x00000000', wand.address)
    //Deploy Pool
    const PoolFactory = await ethers.getContractFactory('Pool', {
      libraries: {
        YieldMath: yieldMath.address,
      },
    })
    pool = (await PoolFactory.deploy(
      await cauldron.assets(USDC),
      fyToken.address,
      ONE64.div(secondsIn30Years), // Timestretch
      ONE64.mul(75).div(100),
      ONE64.mul(100).div(75)
    )) as unknown as Pool
    // await pool.grantRole('0x00000000', wand.address)
  })

  it('Create a series', async () => {
    await wand.addSeries(
      seriesId3, // seriesId
      USDC, // baseId
      [DAI, ETH], // Ilks
      fyToken.address,
      pool.address
    )
  })

  it('Borrow test', async () => {
    let ilk = ETH
    var collateral = (await ethers.getContractAt(
      'ERC20Mock',
      await cauldron.callStatic.assets(ilk),
      ownerAcc
    )) as unknown as ERC20Mock
    let oracle: OracleMock = env.oracles.get(ilk) as OracleMock

    await collateral.connect(ownerAcc).mint(ownerAcc.address, WAD.mul(1000))

    console.log(`series: ${seriesId3}`)
    console.log(`ilk: ${ilk}`)
    const series = await cauldron.series(seriesId3)

    const fyToken = (await ethers.getContractAt('FYToken', series.fyToken, ownerAcc)) as unknown as FYToken

    const dust = (await cauldron.debt(series.baseId, ilk)).min
    const ratio = (await cauldron.spotOracles(series.baseId, ilk)).ratio
    var borrowed = BigNumber.from(10)
      .pow(await fyToken.decimals())
      .mul(dust)

    const posted = (await oracle?.peek(bytesToBytes32(series.baseId), bytesToBytes32(ilk), borrowed))[0]
      .mul(ratio)
      .div(1000000)
      .mul(101)
      .div(100)

    const collateralBalanceBefore = await collateral.balanceOf(ownerAcc.address)

    // Build vault
    await ladle.connect(ownerAcc).build(seriesId3, ilk)
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
