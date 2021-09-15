import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { constants, signatures, id } from '@yield-protocol/utils-v2'
const { WAD, MAX128 } = constants
const MAX = MAX128
import { ETH } from '../src/constants'

import RestrictedERC20MockArtifact from '../artifacts/contracts/mocks/RestrictedERC20Mock.sol/RestrictedERC20Mock.json'

import { Cauldron } from '../typechain/Cauldron'
import { Join } from '../typechain/Join'
import { FYToken } from '../typechain/FYToken'
import { PoolMock } from '../typechain/PoolMock'
import { RestrictedERC20Mock as ERC20Mock } from '../typechain/RestrictedERC20Mock'
import { WETH9Mock } from '../typechain/WETH9Mock'
import { Ladle } from '../typechain/Ladle'
import { Router } from '../typechain/Router'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture, deployContract } = waffle

import { YieldEnvironment } from './shared/fixtures'

describe('Ladle - route', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let other: string
  let cauldron: Cauldron
  let ladle: Ladle
  let router: Router
  let token: ERC20Mock
  let token2: ERC20Mock
  let fyToken: FYToken
  let base: ERC20Mock
  let ilk: ERC20Mock
  let pool: PoolMock
  let ilkJoin: Join
  let wethJoin: Join
  let weth: WETH9Mock

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId, otherIlkId], [seriesId])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    otherAcc = signers[1]
    other = await otherAcc.getAddress()
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const otherIlkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ethId = ETH
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const cachedVaultId = '0x' + '00'.repeat(12)
  let ethVaultId: string

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle.ladle
    router = (await ethers.getContractAt('Router', await ladle.router(), ownerAcc)) as Router
    base = env.assets.get(baseId) as ERC20Mock
    ilk = env.assets.get(ilkId) as ERC20Mock
    fyToken = env.series.get(seriesId) as FYToken
    pool = env.pools.get(seriesId) as PoolMock

    ilkJoin = env.joins.get(ilkId) as Join

    wethJoin = env.joins.get(ethId) as Join
    weth = (await ethers.getContractAt('WETH9Mock', await wethJoin.asset())) as WETH9Mock

    ethVaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ethId) as string

    token = (await deployContract(ownerAcc, RestrictedERC20MockArtifact, ['MTK', 'Mock Token'])) as ERC20Mock
    token2 = (await deployContract(ownerAcc, RestrictedERC20MockArtifact, ['MTK', 'Mock Token'])) as ERC20Mock

    await ladle.grantRoles(
      [id(ladle.interface, 'addToken(address,bool)'), id(ladle.interface, 'addIntegration(address,bool)')],
      owner
    )
    await token.grantRoles([id(token.interface, 'mint(address,uint256)')], owner)
    await token2.grantRoles([id(token2.interface, 'mint(address,uint256)')], ladle.address)
  })

  it('tokens can be added and removed', async () => {
    expect(await ladle.addToken(token.address, true)).to.emit(ladle, 'TokenAdded')
    expect(await ladle.tokens(token.address)).to.be.true
    expect(await ladle.addToken(token.address, false)).to.emit(ladle, 'TokenAdded')
    expect(await ladle.tokens(token.address)).to.be.false
  })

  it('integrations can be added and removed', async () => {
    expect(await ladle.addIntegration(cauldron.address, true)).to.emit(ladle, 'IntegrationAdded')
    expect(await ladle.integrations(cauldron.address)).to.be.true
    expect(await ladle.addIntegration(cauldron.address, false)).to.emit(ladle, 'IntegrationAdded')
    expect(await ladle.integrations(cauldron.address)).to.be.false
  })

  it('only the Ladle can use the Router', async () => {
    await expect(router.route(cauldron.address, '0x00000000')).to.be.revertedWith('Only owner')
  })

  describe('with tokens and integrations', async () => {
    beforeEach(async () => {
      await ladle.addToken(token.address, true)
      await ladle.addIntegration(token2.address, true)
      await ladle.addIntegration(owner, true)
    })

    it("transactions can't be routed to EOAs", async () => {
      await expect(ladle.route(owner, '0x00000000')).to.be.revertedWith('Target is not a contract')
    })

    it('unknown tokens cannot be transferred through the Ladle', async () => {
      await expect(ladle.transfer(token2.address, other, WAD)).to.be.revertedWith('Unknown token')
    })

    it('added tokens can be transferred through the Ladle', async () => {
      await token.mint(owner, WAD)
      await token.approve(ladle.address, WAD)
      expect(await ladle.transfer(token.address, other, WAD)).to.emit(token, 'Transfer')
      await expect(ladle.transfer(token2.address, other, WAD)).to.be.revertedWith('Unknown token')
    })

    it('unknown integrations cannot be called through the Ladle', async () => {
      const routedCall = token2.interface.encodeFunctionData('approve', [other, WAD])
      await expect(ladle.route(token.address, routedCall)).to.be.revertedWith('Unknown integration')
    })

    it('authorizations are stripped when calling integrations through the Ladle', async () => {
      const routedCall = token2.interface.encodeFunctionData('mint', [owner, WAD])
      await expect(ladle.route(token2.address, routedCall)).to.be.revertedWith('Access denied') // The `mint` auth we gave to Ladle is stripped
    })

    it('functions in added integrations can be called through the Ladle', async () => {
      const routedCall = token2.interface.encodeFunctionData('approve', [other, WAD])
      expect(await ladle.route(token2.address, routedCall)).to.emit(token2, 'Approval') // Public functions can be called
    })
  })
})
