import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import OracleMockArtifact from '../artifacts/contracts/mocks/OracleMock.sol/OracleMock.json'
import JoinArtifact from '../artifacts/contracts/Join.sol/Join.json'
import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'

import { Vat } from '../typechain/Vat'
import { Join } from '../typechain/Join'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { OracleMock } from '../typechain/OracleMock'
import { CDPProxy } from '../typechain/CDPProxy'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract, loadFixture } = waffle

import { YieldEnvironment, WAD, RAY } from './shared/fixtures'

describe('Vat - flux', () => {
  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let other: string
  let vat: Vat
  let vatFromOther: Vat
  let fyToken: FYToken
  let base: ERC20Mock
  let ilk: ERC20Mock
  let ilkJoin: Join
  let oracle: OracleMock
  let cdpProxy: CDPProxy
  let cdpProxyFromOther: CDPProxy

  const mockAssetId =  ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const MAX = ethers.constants.MaxUint256

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

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  const ilkId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  const otherIlkId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  const mockVaultId = ethers.utils.hexlify(ethers.utils.randomBytes(12));

  let vaultFromId: string
  let vaultToId: string

  beforeEach(async () => {
    env = await loadFixture(fixture);
    vat = env.vat
    cdpProxy = env.cdpProxy
    base = env.assets.get(baseId) as ERC20Mock
    fyToken = env.series.get(seriesId) as FYToken

    vatFromOther = vat.connect(otherAcc)
    cdpProxyFromOther = cdpProxy.connect(otherAcc)

    vaultFromId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string

    // ==== Set testing environment ====
    await vat.build(seriesId, ilkId)
    const event = (await vat.queryFilter(vat.filters.VaultBuilt(null, null, null, null)))[2] // The third vault built, two from fixtures and this one.
    vaultToId = event.args.vaultId

    await cdpProxy.frob(vaultFromId, WAD, 0)
  })

  it('does not allow moving collateral other than to the vault owner', async () => {
    await expect(vatFromOther.flux(vaultFromId, vaultToId, WAD)).to.be.revertedWith('Only vault owner')
  })

  it('does not allow moving collateral to an uninitialized vault', async () => {
    await expect(vat.flux(vaultFromId, mockVaultId, WAD)).to.be.revertedWith('Vault not found')
  })

  it('does not allow moving collateral and becoming undercollateralized', async () => {
    await cdpProxy.frob(vaultFromId, 0, WAD)
    await expect(vat.flux(vaultFromId, vaultToId, WAD)).to.be.revertedWith('Undercollateralized')
  })

  it('does not allow moving collateral to vault of a different ilk', async () => {
    await vat.tweak(vaultToId, seriesId, otherIlkId)
    await expect(vat.flux(vaultFromId, vaultToId, WAD)).to.be.revertedWith('Different collateral')
  })

  it('moves collateral', async () => {
    expect(await vat.flux(vaultFromId, vaultToId, WAD)).to.emit(vat, 'VaultFluxxed').withArgs(vaultFromId, vaultToId, WAD)
    expect((await vat.vaultBalances(vaultFromId)).ink).to.equal(0)
    expect((await vat.vaultBalances(vaultToId)).ink).to.equal(WAD)
  })
})
