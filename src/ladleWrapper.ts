import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { ethers, BigNumberish, ContractTransaction, BytesLike, PayableOverrides } from 'ethers'
import { Ladle } from '../typechain/Ladle'
import { OPS } from './constants'

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

  public async batch(vaultId: string, actions: Array<BatchAction>, overrides?: PayableOverrides): Promise<ContractTransaction> {
    const ops = new Array<BigNumberish>()
    const data = new Array<BytesLike>()
    actions.forEach(action => {
      ops.push(action.op)
      data.push(action.data)
    });
    if (overrides === undefined) return this.ladle.batch(vaultId, ops, data)
    else return this.ladle.batch(vaultId, ops, data, overrides)
  }

  public buildData(seriesId: string, ilkId: string): BatchAction {
    return new BatchAction(OPS.BUILD, ethers.utils.defaultAbiCoder.encode(['bytes6', 'bytes6'], [seriesId, ilkId]))
  }

  public async build(vaultId: string, seriesId: string, ilkId: string): Promise<ContractTransaction> {
    return this.batch(vaultId, [this.buildData(seriesId, ilkId)])
  }

  public tweakData(seriesId: string, ilkId: string): BatchAction {
    return new BatchAction(OPS.TWEAK, ethers.utils.defaultAbiCoder.encode(['bytes6', 'bytes6'], [seriesId, ilkId]))
  }

  public async tweak(vaultId: string, seriesId: string, ilkId: string): Promise<ContractTransaction> {
    return this.batch(vaultId, [this.tweakData(seriesId, ilkId)])
  }

  public giveData(to: string): BatchAction {
    return new BatchAction(OPS.GIVE, ethers.utils.defaultAbiCoder.encode(['address'], [to]))
  }

  public async give(vaultId: string, to: string): Promise<ContractTransaction> {
    return this.batch(vaultId, [this.giveData(to)])
  }

  public destroyData(): BatchAction {
    return new BatchAction(OPS.DESTROY, ethers.utils.defaultAbiCoder.encode(['uint256'], [0]))  // The data will be ignored
  }

  public async destroy(vaultId: string): Promise<ContractTransaction> {
    return this.batch(vaultId, [this.destroyData()])
  }

  public stirToData(from: string, ink: BigNumberish, art: BigNumberish): BatchAction {
    return new BatchAction(OPS.STIR_TO, ethers.utils.defaultAbiCoder.encode(['bytes12', 'uint128', 'uint128'], [from, ink, art]))
  }

  public stirFromData(to: string, ink: BigNumberish, art: BigNumberish): BatchAction {
    return new BatchAction(OPS.STIR_FROM, ethers.utils.defaultAbiCoder.encode(['bytes12', 'uint128', 'uint128'], [to, ink, art]))
  }

  public async stir(from: string, to: string, ink: BigNumberish, art: BigNumberish): Promise<ContractTransaction> {
    return this.batch(from, [this.stirFromData(to, ink, art)])
  }

  public async stirTo(from: string, to: string, ink: BigNumberish, art: BigNumberish): Promise<ContractTransaction> {
    return this.batch(to, [this.stirToData(from, ink, art)])
  }

  public pourData(to: string, ink: BigNumberish, art: BigNumberish): BatchAction {
    return new BatchAction(OPS.POUR, ethers.utils.defaultAbiCoder.encode(['address', 'int128', 'int128'], [to, ink, art]))
  }

  public async pour(vaultId: string, to: string, ink: BigNumberish, art: BigNumberish): Promise<ContractTransaction> {
    return this.batch(vaultId, [this.pourData(to, ink, art)])
  }

  public closeData(to: string, ink: BigNumberish, art: BigNumberish): BatchAction {
    return new BatchAction(OPS.CLOSE, ethers.utils.defaultAbiCoder.encode(['address', 'int128', 'int128'], [to, ink, art]))
  }

  public async close(vaultId: string, to: string, ink: BigNumberish, art: BigNumberish): Promise<ContractTransaction> {
    return this.batch(vaultId, [this.closeData(to, ink, art)])
  }

  public serveData(to: string, ink: BigNumberish, base: BigNumberish, max: BigNumberish): BatchAction {
    return new BatchAction(OPS.SERVE, ethers.utils.defaultAbiCoder.encode(['address', 'uint128', 'uint128', 'uint128'], [to, ink, base, max]))
  }

  public async serve(vaultId: string, to: string, ink: BigNumberish, base: BigNumberish, max: BigNumberish): Promise<ContractTransaction> {
    return this.batch(vaultId, [this.serveData(to, ink, base, max)])
  }

  public repayData(to: string, ink: BigNumberish, min: BigNumberish): BatchAction {
    return new BatchAction(OPS.REPAY, ethers.utils.defaultAbiCoder.encode(['address', 'int128', 'uint128'], [to, ink, min]))
  }

  public async repay(vaultId: string, to: string, ink: BigNumberish, min: BigNumberish): Promise<ContractTransaction> {
    return this.batch(vaultId, [this.repayData(to, ink, min)])
  }

  public repayVaultData(to: string, ink: BigNumberish, max: BigNumberish): BatchAction {
    return new BatchAction(OPS.REPAY_VAULT, ethers.utils.defaultAbiCoder.encode(['address', 'int128', 'uint128'], [to, ink, max]))
  }

  public async repayVault(vaultId: string, to: string, ink: BigNumberish, max: BigNumberish): Promise<ContractTransaction> {
    return this.batch(vaultId, [this.repayVaultData(to, ink, max)])
  }

  public rollData(newSeriesId: string, max: BigNumberish): BatchAction {
    return new BatchAction(OPS.ROLL, ethers.utils.defaultAbiCoder.encode(['bytes6', 'uint128'], [newSeriesId, max]))
  }

  public async roll(vaultId: string, newSeriesId: string, max: BigNumberish): Promise<ContractTransaction> {
    return this.batch(vaultId, [this.rollData(newSeriesId, max)])
  }

  public forwardPermitData(seriesId: string, asset: boolean, spender: string, amount: BigNumberish, deadline: BigNumberish, v: BigNumberish, r: Buffer, s: Buffer): BatchAction {
    return new BatchAction(OPS.FORWARD_PERMIT, ethers.utils.defaultAbiCoder.encode(
      ['bytes6', 'bool', 'address', 'uint256', 'uint256', 'uint8', 'bytes32', 'bytes32'],
      [seriesId, asset, spender, amount, deadline, v, r, s]
    ))
  }

  public async forwardPermit(vaultId: string, seriesId: string, asset: boolean, spender: string, amount: BigNumberish, deadline: BigNumberish, v: BigNumberish, r: Buffer, s: Buffer): Promise<ContractTransaction> {
    // The vaultId parameter is irrelevant to forwardPermit, but necessary when included in a batch
    return this.batch(vaultId, [this.forwardPermitData(seriesId, asset, spender, amount, deadline, v, r, s)])
  }

  public forwardDaiPermitData(seriesId: string, asset: boolean, spender: string, nonce: BigNumberish, deadline: BigNumberish, approved: boolean, v: BigNumberish, r: Buffer, s: Buffer): BatchAction {
    return new BatchAction(OPS.FORWARD_DAI_PERMIT, ethers.utils.defaultAbiCoder.encode(
      ['bytes6', 'bool', 'address', 'uint256', 'uint256', 'bool', 'uint8', 'bytes32', 'bytes32'],
      [seriesId, asset, spender, nonce, deadline, approved, v, r, s]
    ))
  }

  public async forwardDaiPermit(vaultId: string, seriesId: string, asset: boolean, spender: string, nonce: BigNumberish, deadline: BigNumberish, approved: boolean, v: BigNumberish, r: Buffer, s: Buffer): Promise<ContractTransaction> {
    // The vaultId parameter is irrelevant to forwardDaiPermit, but necessary when included in a batch
    return this.batch(vaultId, [this.forwardDaiPermitData(seriesId, asset, spender, nonce, deadline, approved, v, r, s)])
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
    return this.batch(vaultId, [this.exitEtherData(etherId, to)])
  }

  public transferToPoolData(base: boolean, wad: BigNumberish): BatchAction {
    return new BatchAction(OPS.TRANSFER_TO_POOL, ethers.utils.defaultAbiCoder.encode(['bool', 'uint128'], [base, wad]))
  }

  public async transferToPool(vaultId: string, base: boolean, wad: BigNumberish): Promise<ContractTransaction> {
    return this.batch(vaultId, [this.transferToPoolData(base, wad)])
  }

  public routeData(call: string): BatchAction {
    return new BatchAction(OPS.ROUTE, call)  // `call` is already an encoded function call, no need to abi-encode it again
  }

  public async route(vaultId: string, innerCall: string): Promise<ContractTransaction> {
    return this.batch(vaultId, [this.routeData(innerCall)])
  }

  public transferToFYTokenData(wad: BigNumberish): BatchAction {
    return new BatchAction(OPS.TRANSFER_TO_FYTOKEN, ethers.utils.defaultAbiCoder.encode(['uint256'], [wad]))
  }

  public async transferToFYToken(vaultId: string, seriesId: string, wad: BigNumberish): Promise<ContractTransaction> {
    return this.batch(vaultId, [this.transferToFYTokenData(wad)])
  }

  public redeemData(to: string, wad: BigNumberish): BatchAction {
    return new BatchAction(OPS.REDEEM, ethers.utils.defaultAbiCoder.encode(['address', 'uint256'], [to, wad]))
  }

  public async redeem(vaultId: string, seriesId: string, to: string, wad: BigNumberish): Promise<ContractTransaction> {
    return this.batch(vaultId, [this.redeemData(to, wad)])
  }
}
  