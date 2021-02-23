import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { BigNumber } from 'ethers'

import { Vat } from '../typechain/Vat'
import { CDPProxy } from '../typechain/CDPProxy'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock as ERC20 } from '../typechain/ERC20Mock'
import { OracleMock as Oracle } from '../typechain/OracleMock'

import { YieldEnvironment, WAD, RAY } from './shared/fixtures'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract, loadFixture } = waffle

describe('Vat - Level', () => {
  let ownerAcc: SignerWithAddress
  let owner: string
  let env: YieldEnvironment
  let vat: Vat
  let cdpProxy: CDPProxy
  let fyToken: FYToken
  let base: ERC20
  let ilk: ERC20
  let oracle: Oracle

  const baseId =  ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId =  ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  let vaultId: string

  const mockAssetId =  ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const mockSeriesId =  ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const emptyAssetId = '0x000000000000'
  const mockVaultId =  ethers.utils.hexlify(ethers.utils.randomBytes(12))
  const mockAddress =  ethers.utils.getAddress(ethers.utils.hexlify(ethers.utils.randomBytes(20)))
  const emptyAddress =  ethers.utils.getAddress('0x0000000000000000000000000000000000000000')

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId], [seriesId])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  const maturity = 1640995199;

  beforeEach(async () => {
    env = await loadFixture(fixture);
    vat = env.vat
    cdpProxy = env.cdpProxy
    base = env.assets.get(baseId) as ERC20
    ilk = env.assets.get(ilkId) as ERC20
    oracle = env.oracles.get(ilkId) as Oracle
    fyToken = env.series.get(seriesId) as FYToken
    vaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string

    await oracle.setSpot(RAY.mul(2))
    await cdpProxy.frob(vaultId, WAD, WAD)
  })

  it('before maturity, level is ink * spot - art', async () => {
    expect(await vat.level(vaultId)).to.equal(WAD)

    await oracle.setSpot(RAY.mul(4))
    expect(await vat.level(vaultId)).to.equal(WAD.mul(3))

    await oracle.setSpot(RAY.mul(1))
    expect(await vat.level(vaultId)).to.equal(0)

    await oracle.setSpot(RAY.div(2))
    expect(await vat.level(vaultId)).to.equal(WAD.div(-2))
  })
})
