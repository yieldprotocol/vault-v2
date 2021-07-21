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

  pool = new ethers.utils.Interface([
    "function sellBase(address to, uint128 min)",
    "function sellFYToken(address to, uint128 min)",
    "function mint(address to, bool, uint256 minTokensMinted)",
    "function mintWithBase(address to, uint256 fyTokenToBuy, uint256 minTokensMinted)",
    "function burnForBase(address to, uint256 minBaseOut)",
    "function burn(address to, uint256 minBaseOut, uint256 minFYTokenOut)",
  ]);

  tlmModule = new ethers.utils.Interface([
    "function approve(bytes6 seriesId)",
    "function sell(bytes6 seriesId, address to, uint256 fyDaiToSell)",
  ]);

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

  public async setFee(fee: BigNumberish): Promise<ContractTransaction> {
    return this.ladle.setFee(fee)
  }

  public async borrowingFee(): Promise<BigNumberish> {
    return this.ladle.borrowingFee()
  }

  public async addJoin(assetId: string, join: string): Promise<ContractTransaction> {
    return this.ladle.addJoin(assetId, join)
  }

  public async addPool(assetId: string, pool: string): Promise<ContractTransaction> {
    return this.ladle.addPool(assetId, pool)
  }

  public async setModule(module: string, set: boolean): Promise<ContractTransaction> {
    return this.ladle.setModule(module, set)
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

  public async batch(actions: Array<BatchAction>, overrides?: PayableOverrides): Promise<ContractTransaction> {
    const ops = new Array<BigNumberish>()
    const data = new Array<BytesLike>()
    actions.forEach(action => {
      ops.push(action.op)
      data.push(action.data)
    });
    if (overrides === undefined) return this.ladle.batch(ops, data)
    else return this.ladle.batch(ops, data, overrides)
  }

  public buildAction(seriesId: string, ilkId: string): BatchAction {
    return new BatchAction(OPS.BUILD, ethers.utils.defaultAbiCoder.encode(['bytes6', 'bytes6'], [seriesId, ilkId]))
  }

  public async build(seriesId: string, ilkId: string): Promise<ContractTransaction> {
    return this.batch([this.buildAction(seriesId, ilkId)])
  }

  public tweakAction(vaultId: string, seriesId: string, ilkId: string): BatchAction {
    return new BatchAction(OPS.TWEAK, ethers.utils.defaultAbiCoder.encode(['bytes12', 'bytes6', 'bytes6'], [vaultId, seriesId, ilkId]))
  }

  public async tweak(vaultId: string, seriesId: string, ilkId: string): Promise<ContractTransaction> {
    return this.batch([this.tweakAction(vaultId, seriesId, ilkId)])
  }

  public giveAction(vaultId: string, to: string): BatchAction {
    return new BatchAction(OPS.GIVE, ethers.utils.defaultAbiCoder.encode(['bytes12', 'address'], [vaultId, to]))
  }

  public async give(vaultId: string, to: string): Promise<ContractTransaction> {
    return this.batch([this.giveAction(vaultId, to)])
  }

  public destroyAction(vaultId: string): BatchAction {
    return new BatchAction(OPS.DESTROY, ethers.utils.defaultAbiCoder.encode(['bytes12'], [vaultId]))
  }

  public async destroy(vaultId: string): Promise<ContractTransaction> {
    return this.batch([this.destroyAction(vaultId)])
  }

  public stirAction(from: string, to: string, ink: BigNumberish, art: BigNumberish): BatchAction {
    return new BatchAction(OPS.STIR, ethers.utils.defaultAbiCoder.encode(['bytes12', 'bytes12', 'uint128', 'uint128'], [from, to, ink, art]))
  }

  public async stir(from: string, to: string, ink: BigNumberish, art: BigNumberish): Promise<ContractTransaction> {
    return this.batch([this.stirAction(from, to, ink, art)])
  }

  public pourAction(vaultId: string, to: string, ink: BigNumberish, art: BigNumberish): BatchAction {
    return new BatchAction(OPS.POUR, ethers.utils.defaultAbiCoder.encode(['bytes12', 'address', 'int128', 'int128'], [vaultId, to, ink, art]))
  }

  public async pour(vaultId: string, to: string, ink: BigNumberish, art: BigNumberish): Promise<ContractTransaction> {
    return this.batch([this.pourAction(vaultId, to, ink, art)])
  }

  public closeAction(vaultId: string, to: string, ink: BigNumberish, art: BigNumberish): BatchAction {
    return new BatchAction(OPS.CLOSE, ethers.utils.defaultAbiCoder.encode(['bytes12', 'address', 'int128', 'int128'], [vaultId, to, ink, art]))
  }

  public async close(vaultId: string, to: string, ink: BigNumberish, art: BigNumberish): Promise<ContractTransaction> {
    return this.batch([this.closeAction(vaultId, to, ink, art)])
  }

  public serveAction(vaultId: string, to: string, ink: BigNumberish, base: BigNumberish, max: BigNumberish): BatchAction {
    return new BatchAction(OPS.SERVE, ethers.utils.defaultAbiCoder.encode(['bytes12', 'address', 'uint128', 'uint128', 'uint128'], [vaultId, to, ink, base, max]))
  }

  public async serve(vaultId: string, to: string, ink: BigNumberish, base: BigNumberish, max: BigNumberish): Promise<ContractTransaction> {
    return this.batch([this.serveAction(vaultId, to, ink, base, max)])
  }

  public repayAction(vaultId: string, to: string, ink: BigNumberish, min: BigNumberish): BatchAction {
    return new BatchAction(OPS.REPAY, ethers.utils.defaultAbiCoder.encode(['bytes12', 'address', 'int128', 'uint128'], [vaultId, to, ink, min]))
  }

  public async repay(vaultId: string, to: string, ink: BigNumberish, min: BigNumberish): Promise<ContractTransaction> {
    return this.batch([this.repayAction(vaultId, to, ink, min)])
  }

  public repayVaultAction(vaultId: string, to: string, ink: BigNumberish, max: BigNumberish): BatchAction {
    return new BatchAction(OPS.REPAY_VAULT, ethers.utils.defaultAbiCoder.encode(['bytes12', 'address', 'int128', 'uint128'], [vaultId, to, ink, max]))
  }

  public async repayVault(vaultId: string, to: string, ink: BigNumberish, max: BigNumberish): Promise<ContractTransaction> {
    return this.batch([this.repayVaultAction(vaultId, to, ink, max)])
  }

  public repayLadleAction(vaultId: string): BatchAction {
    return new BatchAction(OPS.REPAY_LADLE, ethers.utils.defaultAbiCoder.encode(['bytes12'], [vaultId]))
  }

  public async repayLadle(vaultId: string): Promise<ContractTransaction> {
    return this.batch([this.repayLadleAction(vaultId)])
  }

  public retrieveAction(assetId: string, isAsset: boolean, to: string): BatchAction {
    return new BatchAction(OPS.RETRIEVE, ethers.utils.defaultAbiCoder.encode(['bytes6', 'bool', 'address'], [assetId, isAsset, to]))
  }

  public async retrieve(assetId: string, isAsset: boolean, to: string): Promise<ContractTransaction> {
    return this.batch([this.retrieveAction(assetId, isAsset, to)])
  }

  public rollAction(vaultId: string, newSeriesId: string, loan: BigNumberish, max: BigNumberish): BatchAction {
    return new BatchAction(OPS.ROLL, ethers.utils.defaultAbiCoder.encode(['bytes12', 'bytes6', 'uint8', 'uint128'], [vaultId, newSeriesId, loan, max]))
  }

  public async roll(vaultId: string, newSeriesId: string, loan: BigNumberish, max: BigNumberish): Promise<ContractTransaction> {
    return this.batch([this.rollAction(vaultId, newSeriesId, loan, max)])
  }

  public forwardPermitAction(id: string, isAsset: boolean, spender: string, amount: BigNumberish, deadline: BigNumberish, v: BigNumberish, r: Buffer, s: Buffer): BatchAction {
    return new BatchAction(OPS.FORWARD_PERMIT, ethers.utils.defaultAbiCoder.encode(
      ['bytes6', 'bool', 'address', 'uint256', 'uint256', 'uint8', 'bytes32', 'bytes32'],
      [id, isAsset, spender, amount, deadline, v, r, s]
    ))
  }

  public async forwardPermit(id: string, isAsset: boolean, spender: string, amount: BigNumberish, deadline: BigNumberish, v: BigNumberish, r: Buffer, s: Buffer): Promise<ContractTransaction> {
    return this.batch([this.forwardPermitAction(id, isAsset, spender, amount, deadline, v, r, s)])
  }

  public forwardDaiPermitAction(id: string, isAsset: boolean, spender: string, nonce: BigNumberish, deadline: BigNumberish, approved: boolean, v: BigNumberish, r: Buffer, s: Buffer): BatchAction {
    return new BatchAction(OPS.FORWARD_DAI_PERMIT, ethers.utils.defaultAbiCoder.encode(
      ['bytes6', 'bool', 'address', 'uint256', 'uint256', 'bool', 'uint8', 'bytes32', 'bytes32'],
      [id, isAsset, spender, nonce, deadline, approved, v, r, s]
    ))
  }

  public async forwardDaiPermit(id: string, isAsset: boolean, spender: string, nonce: BigNumberish, deadline: BigNumberish, approved: boolean, v: BigNumberish, r: Buffer, s: Buffer): Promise<ContractTransaction> {
    return this.batch([this.forwardDaiPermitAction(id, isAsset, spender, nonce, deadline, approved, v, r, s)])
  }

  public joinEtherAction(etherId: string): BatchAction {
    return new BatchAction(OPS.JOIN_ETHER, ethers.utils.defaultAbiCoder.encode(['bytes6'], [etherId]))
  }

  public async joinEther(etherId: string, overrides?: any): Promise<ContractTransaction> {
    return this.batch([this.joinEtherAction(etherId)], overrides)
  }

  public exitEtherAction(to: string): BatchAction {
    return new BatchAction(OPS.EXIT_ETHER, ethers.utils.defaultAbiCoder.encode(['address'], [to]))
  }

  public async exitEther(to: string): Promise<ContractTransaction> {
    return this.batch([this.exitEtherAction(to)])
  }

  public transferToPoolAction(seriesId: string, base: boolean, wad: BigNumberish): BatchAction {
    return new BatchAction(OPS.TRANSFER_TO_POOL, ethers.utils.defaultAbiCoder.encode(['bytes6', 'bool', 'uint128'], [seriesId, base, wad]))
  }

  public async transferToPool(seriesId: string, base: boolean, wad: BigNumberish): Promise<ContractTransaction> {
    return this.batch([this.transferToPoolAction(seriesId, base, wad)])
  }

  public routeAction(seriesId: string, poolCall: string): BatchAction {
    return new BatchAction(OPS.ROUTE, ethers.utils.defaultAbiCoder.encode(['bytes6', 'bytes'], [seriesId, poolCall]))
  }

  public async route(seriesId: string, poolCall: string): Promise<ContractTransaction> {
    return this.batch([this.routeAction(seriesId, poolCall)])
  }

  public transferToFYTokenAction(seriesId: string, wad: BigNumberish): BatchAction {
    return new BatchAction(OPS.TRANSFER_TO_FYTOKEN, ethers.utils.defaultAbiCoder.encode(['bytes6', 'uint256'], [seriesId, wad]))
  }

  public async transferToFYToken(seriesId: string, wad: BigNumberish): Promise<ContractTransaction> {
    return this.batch([this.transferToFYTokenAction(seriesId, wad)])
  }

  public redeemAction(seriesId: string, to: string, wad: BigNumberish): BatchAction {
    return new BatchAction(OPS.REDEEM, ethers.utils.defaultAbiCoder.encode(['bytes6', 'address', 'uint256'], [seriesId, to, wad]))
  }

  public async redeem(seriesId: string, to: string, wad: BigNumberish): Promise<ContractTransaction> {
    return this.batch([this.redeemAction(seriesId, to, wad)])
  }


  public sellBaseAction(seriesId: string, receiver: string, min: BigNumberish): BatchAction {
    return new BatchAction(OPS.ROUTE, ethers.utils.defaultAbiCoder.encode(
      ['bytes6', 'bytes'],
      [
        seriesId,
        this.pool.encodeFunctionData('sellBase', [receiver, min])
      ]
    ))
  }

  public async sellBase(seriesId: string, receiver: string, min: BigNumberish): Promise<ContractTransaction> {
    return this.batch([this.sellBaseAction(seriesId, receiver, min)])
  }

  public sellFYTokenAction(seriesId: string, receiver: string, min: BigNumberish): BatchAction {
    return new BatchAction(OPS.ROUTE, ethers.utils.defaultAbiCoder.encode(
      ['bytes6', 'bytes'],
      [
        seriesId,
        this.pool.encodeFunctionData('sellFYToken', [receiver, min])
      ]
    ))
  }

  public async sellFYToken(seriesId: string, receiver: string, min: BigNumberish): Promise<ContractTransaction> {
    return this.batch([this.sellFYTokenAction(seriesId, receiver, min)])
  }

  public mintWithBaseAction(seriesId: string, receiver: string, fyTokenToBuy: BigNumberish, minTokensMinted: BigNumberish): BatchAction {
    return new BatchAction(OPS.ROUTE, ethers.utils.defaultAbiCoder.encode(
      ['bytes6', 'bytes'],
      [
        seriesId,
        this.pool.encodeFunctionData('mintWithBase', [receiver, fyTokenToBuy, minTokensMinted])
      ]
    ))
  }

  public async mintWithBase(seriesId: string, receiver: string, fyTokenToBuy: BigNumberish, minTokensMinted: BigNumberish): Promise<ContractTransaction> {
    return this.batch([this.mintWithBaseAction(seriesId, receiver, fyTokenToBuy, minTokensMinted)])
  }

  public burnForBaseAction(seriesId: string, receiver: string, minBaseOut: BigNumberish): BatchAction {
    return new BatchAction(OPS.ROUTE, ethers.utils.defaultAbiCoder.encode(
      ['bytes6', 'bytes'],
      [
        seriesId,
        this.pool.encodeFunctionData('burnForBase', [receiver, minBaseOut])
      ]
    ))
  }

  public async burnForBase(seriesId: string, receiver: string, minBaseOut: BigNumberish): Promise<ContractTransaction> {
    return this.batch([this.burnForBaseAction(seriesId, receiver, minBaseOut)])
  }

  public tlmApproveAction(tlmModuleAddress: string, seriesId: string): BatchAction {
    const tlmApproveCall = this.tlmModule.encodeFunctionData('approve', [seriesId])

    return new BatchAction(OPS.MODULE, ethers.utils.defaultAbiCoder.encode(
      ['address', 'bytes'],
      [tlmModuleAddress, tlmApproveCall]
    ))
  }

  public async tlmApprove(tlmModuleAddress: string, seriesId: string): Promise<ContractTransaction> {
    return this.batch([this.tlmApproveAction(tlmModuleAddress, seriesId)])
  }

  public tlmSellAction(tlmModuleAddress: string, seriesId: string, receiver: string, amount: BigNumberish): BatchAction {
    const tlmSellCall = this.tlmModule.encodeFunctionData('sell', [seriesId, receiver, amount])

    return new BatchAction(OPS.MODULE, ethers.utils.defaultAbiCoder.encode(
      ['address', 'bytes'],
      [tlmModuleAddress, tlmSellCall]
    ))
  }

  public async tlmSell(tlmModuleAddress: string, seriesId: string, receiver: string, amount: BigNumberish): Promise<ContractTransaction> {
    return this.batch([this.tlmSellAction(tlmModuleAddress, seriesId, receiver, amount)])
  }
}
  