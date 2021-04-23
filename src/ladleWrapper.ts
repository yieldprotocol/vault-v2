import { ethers } from 'hardhat'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { BigNumberish, ContractTransaction } from 'ethers'
import { Ladle } from '../typechain/Ladle'

export const OPS = {
  BUILD:                0,
  TWEAK:                1,
  GIVE:                 2,
  DESTROY:              3,
  STIR_TO:              4,
  STIR_FROM:            5,
  POUR:                 6,
  SERVE:                7,
  ROLL:                 8,
  CLOSE:                9,
  REPAY:                10,
  REPAY_VAULT:          11,
  FORWARD_PERMIT:       12,
  FORWARD_DAI_PERMIT:   13,
  JOIN_ETHER:           14,
  EXIT_ETHER:           15,
  TRANSFER_TO_POOL:     16,
  ROUTE:                17,
  TRANSFER_TO_FYTOKEN:  18,
  REDEEM:               19,
}

export class BatchAction {
  op: BigNumberish
  data: string

  constructor(op: BigNumberish, data: string) {
    this.op = op
    this.data = data
  }
}

export class LadleWrapper {
  ladle: Ladle
  address: string

  constructor(ladle: Ladle) {
    this.ladle = ladle
    this.address = ladle.address
  }

  public static async setup(ladle: Ladle) {
    return new LadleWrapper(ladle)
  }

  public connect(account: SignerWithAddress): LadleWrapper {
    return new LadleWrapper(this.ladle.connect(account))
  }

  public async addJoin(assetId: string, join: string): Promise<ContractTransaction> {
    return this.ladle.addJoin(assetId, join)
  }

  public async addPool(assetId: string, pool: string): Promise<ContractTransaction> {
    return this.ladle.addPool(assetId, pool)
  }

  public async setPoolRouter(poolRouter: string): Promise<ContractTransaction> {
    return this.ladle.setPoolRouter(poolRouter)
  }

  public async grantRoles(roles: Array<string>, user: string): Promise<ContractTransaction> {
    return this.ladle.grantRoles(roles, user)
  }

  public async joins(ilkId: string): Promise<string> {
    return this.ladle.joins(ilkId)
  }

  public async pools(seriesId: string): Promise<string> {
    return this.ladle.pools(seriesId)
  }

  public async batch(vaultId: string, ops: Array<BigNumberish>, data: Array<string>): Promise<ContractTransaction> {
    return this.ladle.batch(vaultId, ops, data)
  }

  public buildData(seriesId: string, ilkId: string): BatchAction {
    return new BatchAction(OPS.BUILD, ethers.utils.defaultAbiCoder.encode(['bytes6', 'bytes6'], [seriesId, ilkId]))
  }

  public async build(vaultId: string, seriesId: string, ilkId: string): Promise<ContractTransaction> {
    const action = this.buildData(seriesId, ilkId)
    return this.ladle.batch(vaultId, [action.op], [action.data])
  }

  public tweakData(seriesId: string, ilkId: string): BatchAction {
    return new BatchAction(OPS.TWEAK, ethers.utils.defaultAbiCoder.encode(['bytes6', 'bytes6'], [seriesId, ilkId]))
  }

  public async tweak(vaultId: string, seriesId: string, ilkId: string): Promise<ContractTransaction> {
    const action = this.tweakData(seriesId, ilkId)
    return this.ladle.batch(vaultId, [action.op], [action.data])
  }

  public giveData(to: string): BatchAction {
    return new BatchAction(OPS.GIVE, ethers.utils.defaultAbiCoder.encode(['address'], [to]))
  }

  public async give(vaultId: string, to: string): Promise<ContractTransaction> {
    const action = this.giveData(to)
    return this.ladle.batch(vaultId, [action.op], [action.data])
  }

  public destroyData(): BatchAction {
    return new BatchAction(OPS.DESTROY, ethers.utils.defaultAbiCoder.encode(['uint256'], [0]))  // The data will be ignored
  }

  public async destroy(vaultId: string): Promise<ContractTransaction> {
    const action = this.destroyData()
    return this.ladle.batch(vaultId, [action.op], [action.data])
  }

  public stirToData(from: string, ink: BigNumberish, art: BigNumberish): BatchAction {
    return new BatchAction(OPS.STIR_TO, ethers.utils.defaultAbiCoder.encode(['bytes12', 'uint128', 'uint128'], [from, ink, art]))
  }

  public stirFromData(to: string, ink: BigNumberish, art: BigNumberish): BatchAction {
    return new BatchAction(OPS.STIR_FROM, ethers.utils.defaultAbiCoder.encode(['bytes12', 'uint128', 'uint128'], [to, ink, art]))
  }

  public async stir(from: string, to: string, ink: BigNumberish, art: BigNumberish): Promise<ContractTransaction> {
    const action = this.stirFromData(to, ink, art)
    return this.ladle.batch(from, [action.op], [action.data])
  }

  public async stirTo(from: string, to: string, ink: BigNumberish, art: BigNumberish): Promise<ContractTransaction> {
    const action = this.stirToData(from, ink, art)
    return this.ladle.batch(to, [action.op], [action.data])
  }

  public pourData(to: string, ink: BigNumberish, art: BigNumberish): BatchAction {
    return new BatchAction(OPS.POUR, ethers.utils.defaultAbiCoder.encode(['address', 'int128', 'int128'], [to, ink, art]))
  }

  public async pour(vaultId: string, to: string, ink: BigNumberish, art: BigNumberish): Promise<ContractTransaction> {
    const action = this.pourData(to, ink, art)
    return this.ladle.batch(vaultId, [action.op], [action.data])
  }

  public closeData(to: string, ink: BigNumberish, art: BigNumberish): BatchAction {
    return new BatchAction(OPS.CLOSE, ethers.utils.defaultAbiCoder.encode(['address', 'int128', 'int128'], [to, ink, art]))
  }

  public async close(vaultId: string, to: string, ink: BigNumberish, art: BigNumberish): Promise<ContractTransaction> {
    const action = this.closeData(to, ink, art)
    return this.ladle.batch(vaultId, [action.op], [action.data])
  }

  public serveData(to: string, ink: BigNumberish, base: BigNumberish, max: BigNumberish): BatchAction {
    return new BatchAction(OPS.SERVE, ethers.utils.defaultAbiCoder.encode(['address', 'uint128', 'uint128', 'uint128'], [to, ink, base, max]))
  }

  public async serve(vaultId: string, to: string, ink: BigNumberish, base: BigNumberish, max: BigNumberish): Promise<ContractTransaction> {
    const action = this.serveData(to, ink, base, max)
    return this.ladle.batch(vaultId, [action.op], [action.data])
  }

  public repayData(to: string, ink: BigNumberish, min: BigNumberish): BatchAction {
    return new BatchAction(OPS.REPAY, ethers.utils.defaultAbiCoder.encode(['address', 'int128', 'uint128'], [to, ink, min]))
  }

  public async repay(vaultId: string, to: string, ink: BigNumberish, min: BigNumberish): Promise<ContractTransaction> {
    const action = this.repayData(to, ink, min)
    return this.ladle.batch(vaultId, [action.op], [action.data])
  }

  public repayVaultData(to: string, ink: BigNumberish, max: BigNumberish): BatchAction {
    return new BatchAction(OPS.REPAY_VAULT, ethers.utils.defaultAbiCoder.encode(['address', 'int128', 'uint128'], [to, ink, max]))
  }

  public async repayVault(vaultId: string, to: string, ink: BigNumberish, max: BigNumberish): Promise<ContractTransaction> {
    const action = this.repayVaultData(to, ink, max)
    return this.ladle.batch(vaultId, [action.op], [action.data])
  }

  public rollData(newSeriesId: string, max: BigNumberish): BatchAction {
    return new BatchAction(OPS.ROLL, ethers.utils.defaultAbiCoder.encode(['bytes6', 'uint128'], [newSeriesId, max]))
  }

  public async roll(vaultId: string, newSeriesId: string, max: BigNumberish): Promise<ContractTransaction> {
    const action = this.rollData(newSeriesId, max)
    return this.ladle.batch(vaultId, [action.op], [action.data])
  }

  public forwardPermitData(seriesId: string, asset: boolean, spender: string, amount: BigNumberish, deadline: BigNumberish, v: BigNumberish, r: Buffer, s: Buffer): BatchAction {
    return new BatchAction(OPS.FORWARD_PERMIT, ethers.utils.defaultAbiCoder.encode(
      ['bytes6', 'bool', 'address', 'uint256', 'uint256', 'uint8', 'bytes32', 'bytes32'],
      [seriesId, asset, spender, amount, deadline, v, r, s]
    ))
  }

  public async forwardPermit(vaultId: string, seriesId: string, asset: boolean, spender: string, amount: BigNumberish, deadline: BigNumberish, v: BigNumberish, r: Buffer, s: Buffer): Promise<ContractTransaction> {
    // The vaultId parameter is irrelevant to forwardPermit, but necessary when included in a batch
    const action = this.forwardPermitData(seriesId, asset, spender, amount, deadline, v, r, s)
    return this.ladle.batch(vaultId, [action.op], [action.data])
  }

  public forwardDaiPermitData(seriesId: string, asset: boolean, spender: string, nonce: BigNumberish, deadline: BigNumberish, approved: boolean, v: BigNumberish, r: Buffer, s: Buffer): BatchAction {
    return new BatchAction(OPS.FORWARD_DAI_PERMIT, ethers.utils.defaultAbiCoder.encode(
      ['bytes6', 'bool', 'address', 'uint256', 'uint256', 'bool', 'uint8', 'bytes32', 'bytes32'],
      [seriesId, asset, spender, nonce, deadline, approved, v, r, s]
    ))
  }

  public async forwardDaiPermit(vaultId: string, seriesId: string, asset: boolean, spender: string, nonce: BigNumberish, deadline: BigNumberish, approved: boolean, v: BigNumberish, r: Buffer, s: Buffer): Promise<ContractTransaction> {
    // The vaultId parameter is irrelevant to forwardDaiPermit, but necessary when included in a batch
    const action = this.forwardDaiPermitData(seriesId, asset, spender, nonce, deadline, approved, v, r, s)
    return this.ladle.batch(vaultId, [action.op], [action.data])
  }

  public joinEtherData(etherId: string): BatchAction {
    return new BatchAction(OPS.JOIN_ETHER, ethers.utils.defaultAbiCoder.encode(['bytes6'], [etherId]))
  }

  public async joinEther(vaultId: string, etherId: string, overrides?: any): Promise<ContractTransaction> {
    // The vaultId parameter is irrelevant to joinEther, but necessary when included in a batch
    const action = this.joinEtherData(etherId)
    return this.ladle.batch(vaultId, [action.op], [action.data], overrides)
  }

  public exitEtherData(etherId: string, to: string): BatchAction {
    return new BatchAction(OPS.EXIT_ETHER, ethers.utils.defaultAbiCoder.encode(['bytes6', 'address'], [etherId, to]))
  }

  public async exitEther(vaultId: string, etherId: string, to: string): Promise<ContractTransaction> {
    // The vaultId parameter is irrelevant to exitEther, but necessary when included in a batch
    const action = this.exitEtherData(etherId, to)
    return this.ladle.batch(vaultId, [action.op], [action.data])
  }

  public transferToPoolData(base: boolean, wad: BigNumberish): BatchAction {
    return new BatchAction(OPS.TRANSFER_TO_POOL, ethers.utils.defaultAbiCoder.encode(['bool', 'uint128'], [base, wad]))
  }

  public async transferToPool(vaultId: string, base: boolean, wad: BigNumberish): Promise<ContractTransaction> {
    const action = this.transferToPoolData(base, wad)
    return this.ladle.batch(vaultId, [action.op], [action.data])
  }

  public routeData(call: string): BatchAction {
    return new BatchAction(OPS.ROUTE, call)  // `call` is already an encoded function call, no need to abi-encode it again
  }

  public async route(vaultId: string, innerCall: string): Promise<ContractTransaction> {
    const action = this.routeData(innerCall)
    return this.ladle.batch(vaultId, [action.op], [action.data])
  }

  public transferToFYTokenData(wad: BigNumberish): BatchAction {
    return new BatchAction(OPS.TRANSFER_TO_FYTOKEN, ethers.utils.defaultAbiCoder.encode(['uint256'], [wad]))
  }

  public async transferToFYToken(vaultId: string, seriesId: string, wad: BigNumberish): Promise<ContractTransaction> {
    const action = this.transferToFYTokenData(wad)
    return this.ladle.batch(vaultId, [action.op], [action.data])
  }

  public redeemData(to: string, wad: BigNumberish): BatchAction {
    return new BatchAction(OPS.REDEEM, ethers.utils.defaultAbiCoder.encode(['address', 'uint256'], [to, wad]))
  }

  public async redeem(vaultId: string, seriesId: string, to: string, wad: BigNumberish): Promise<ContractTransaction> {
    const action = this.redeemData(to, wad)
    return this.ladle.batch(vaultId, [action.op], [action.data])
  }
}
  