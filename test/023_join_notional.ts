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

  let resetChain: number
  let ownerAcc: SignerWithAddress
  let owner: string
  let otherAcc: SignerWithAddress
  let other: string
  let join: NotionalJoin
  let fCash: FCashMock
  let underlying: ERC20Mock
  const maturity: number = 1656288000
  const currencyId: string = '2'
  const fCashId: string = '563373963149313'

  before(async () => {
    resetChain = await ethers.provider.send('evm_snapshot', [])
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    otherAcc = signers[1]
    other = await otherAcc.getAddress()
  })

  after(async () => {
    await ethers.provider.send('evm_revert', [resetChain])
  })

  beforeEach(async () => {
    underlying = (await deployContract(ownerAcc, ERC20MockArtifact, ['', ''])) as ERC20Mock
    fCash = (await deployContract(ownerAcc, FCashMockArtifact, [underlying.address, fCashId])) as FCashMock
    join = (await deployContract(ownerAcc, NotionalJoinArtifact, [
      fCash.address,
      underlying.address,
      maturity,
      currencyId,
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
    await fCash.setAccrual(WAD.mul(2))
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
        await join.join(owner, WAD.mul(2))
      })

      it('pushes fCash to user', async () => {
        expect(await join.exit(owner, WAD))
          .to.emit(fCash, 'TransferSingle')
          .withArgs(join.address, join.address, owner, fCashId, WAD)
        expect(await join.storedBalance()).to.equal(WAD)
      })

      describe('after maturity', async () => {
        let stepBack: number
        beforeEach(async () => {
          stepBack = await ethers.provider.send('evm_snapshot', [])
          await ethers.provider.send('evm_mine', [maturity])
        })

        afterEach(async () => {
          await ethers.provider.send('evm_revert', [stepBack])
        })

        // Doesn't allow to join
        it('does not allow to join after maturity', async () => {
          await expect(join.join(owner, WAD.mul(2))).to.be.revertedWith('Only before maturity')
        })

        // Allows to redeem fCash for underlying
        it('redeems fCash for underlying', async () => {
          expect(await join.redeem())
            .to.emit(join, 'Redeemed')
            .withArgs(WAD.mul(2), WAD.mul(4), WAD.mul(2))
          expect(await join.storedBalance()).to.equal(WAD.mul(4))
          expect(await join.accrual()).to.equal(WAD.mul(2))
        })

        describe('once fCash is redeemed', async () => {
          beforeEach(async () => {
            await join.redeem()
          })

          it('does not allow to redeem again', async () => {
            await expect(join.redeem()).to.be.revertedWith('Already redeemed')
          })  

          it('pushes underlying to user', async () => {
            expect(await join.exit(owner, WAD))
              .to.emit(underlying, 'Transfer')
              .withArgs(join.address, owner, WAD.mul(2))
            expect(await join.storedBalance()).to.equal(WAD.mul(2))
            expect(await underlying.balanceOf(owner)).to.equal(WAD.mul(2))
          })
        })

        it('redeems on first exit', async () => {
          expect(await join.exit(owner, WAD))
            .to.emit(join, 'Redeemed')
            .withArgs(WAD.mul(2), WAD.mul(4), WAD.mul(2))
            .to.emit(underlying, 'Transfer')
            .withArgs(join.address, owner, WAD.mul(2))
          expect(await join.storedBalance()).to.equal(WAD.mul(2))
          expect(await join.accrual()).to.equal(WAD.mul(2))
          expect(await underlying.balanceOf(owner)).to.equal(WAD.mul(2))
        })
      })
    })
  })
})
