import { keccak256, toUtf8Bytes } from 'ethers/lib/utils'
import { Interface } from '@ethersproject/abi'
export * as constants from "./constants"
export * as signatures from "./signatures"

export const id = (abi : Interface, signature: string) => {
  if (abi.functions[signature] === undefined) throw Error(`${signature} doesn't exist`)
  return keccak256(toUtf8Bytes(signature)).slice(0, 10)
}