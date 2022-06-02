import { Contract } from '@ethersproject/contracts'
import { Signer } from '@ethersproject/abstract-signer/src.ts/index'

export const sendStatic = async (
  contractInstance: Contract,
  contractMethod: string,
  contractCaller: Signer,
  contractParams: Array<any>,
  callValue = '0'
): Promise<any> => {
  const returnValue = await contractInstance
    .connect(contractCaller)
    .callStatic[contractMethod](...contractParams, { value: callValue })
  await contractInstance.connect(contractCaller)[contractMethod](...contractParams, { value: callValue })
  return returnValue
}
