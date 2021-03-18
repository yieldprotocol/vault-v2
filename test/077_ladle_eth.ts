import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { Cauldron } from '../typechain/Cauldron'
import { EthJoin } from '../typechain/EthJoin'
import { Ladle } from '../typechain/Ladle'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle

import { YieldEnvironment, WAD } from './shared/fixtures'

describe('Ladle - eth', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let other: string
  let cauldron: Cauldron
  let ethJoin: EthJoin
  let ladle: Ladle

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId], [seriesId])
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
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ethId = ethers.utils.formatBytes32String('ETH').slice(0, 14)

  let ethVaultId: string

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    ethJoin = env.joins.get(ethId) as EthJoin

    ethVaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ethId) as string
  })

  it('users can pour to post ETH', async () => {
    expect(await ladle.pour(ethVaultId, owner, WAD, 0, { value: WAD }))
      .to.emit(cauldron, 'VaultPoured')
      .withArgs(ethVaultId, seriesId, ethId, WAD, 0)
    expect(await ethers.provider.getBalance(ethJoin.address)).to.equal(WAD)
    expect((await cauldron.balances(ethVaultId)).ink).to.equal(WAD)
  })
})
