import { constants, id } from '@yield-protocol/utils-v2'

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

const { WAD, MAX256 } = constants

import NotionalJoinArtifact from '../artifacts/contracts/other/notional/NotionalJoin.sol/NotionalJoin.json'
import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import FCashMockArtifact from '../artifacts/contracts/other/notional/FCashMock.sol/FCashMock.json'

import { NotionalJoin } from '../typechain/NotionalJoin'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { FCashMock } from '../typechain/FCashMock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract } = waffle

describe('Join1155', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let otherAcc: SignerWithAddress
  let other: string
  let join: NotionalJoin
  let fCash: FCashMock
  let underlying: ERC20Mock
  const maturity: string = '1656288000'
  const currencyId: string = '2'
  const fCashId: string = '563373963149313'

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    otherAcc = signers[1]
    other = await otherAcc.getAddress()
  })

  beforeEach(async () => {
    underlying = (await deployContract(ownerAcc, ERC20MockArtifact, ['', ''])) as ERC20Mock
    fCash = (await deployContract(ownerAcc, FCashMockArtifact, [underlying.address, fCashId])) as FCashMock
    join = (await deployContract(ownerAcc, NotionalJoinArtifact, [
      fCash.address,
      underlying.address,
      maturity,
      currencyId
    ])) as NotionalJoin

    await join.grantRoles(
      [
        id(join.interface, 'join(address,uint128)'),
        id(join.interface, 'exit(address,uint128)'),
        id(join.interface, 'retrieve(address,address)'),
        id(join.interface, 'retrieveERC1155(address,uint256,address)'),
      ],
      owner
    )

    await fCash.mint(owner, fCashId, WAD.mul(100), '0x00')
    await fCash.setApprovalForAll(join.address, true)
  })

  it('pulls fCash from user', async () => {
    expect(await join.join(owner, WAD))
      .to.emit(fCash, 'TransferSingle')
      .withArgs(join.address, owner, join.address, fCashId, WAD)
    expect(await join.storedBalance()).to.equal(WAD)
  })

  describe('with fCashs in the join', async () => {
    beforeEach(async () => {
      await fCash.safeTransferFrom(owner, join.address, fCashId, WAD, '0x00')
    })

    it('accepts surplus as a transfer', async () => {
      expect(await join.join(owner, WAD)).to.not.emit(fCash, 'TransferSingle')
      expect(await join.storedBalance()).to.equal(WAD)
    })

    it('combines surplus and fCashs pulled from the user', async () => {
      expect(await join.join(owner, WAD.mul(2)))
        .to.emit(fCash, 'TransferSingle')
        .withArgs(join.address, owner, join.address, fCashId, WAD)
      expect(await join.storedBalance()).to.equal(WAD.mul(2))
    })

    describe('with a positive stored balance', async () => {
      beforeEach(async () => {
        await join.join(owner, WAD)
      })

      it('pushes fCashs to user', async () => {
        expect(await join.exit(owner, WAD))
          .to.emit(fCash, 'TransferSingle')
          .withArgs(join.address, join.address, owner, fCashId, WAD)
        expect(await join.storedBalance()).to.equal(0)
      })

      describe('after maturity', async () => {
        beforeEach(async () => {
          //
        })

        // Doesn't allow to join
        // Allows to redeem fCash for underlying

          // Once fCash is redeemed
          // Pushes underlying to user

        // Allows to redeem on first exit
      })  
    })
  })
})
