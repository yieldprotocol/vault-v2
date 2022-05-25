import { keccak256, defaultAbiCoder, toUtf8Bytes, solidityPack } from 'ethers/lib/utils'
import { BigNumberish } from 'ethers'
import { ecsign } from 'ethereumjs-util'

// Private keys for hardhat's mnemonic.
export const privateKey0 = Buffer.from('ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80', 'hex')
export const privateKey1 = Buffer.from('59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d', 'hex')
export const privateKey2 = Buffer.from('5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a', 'hex')
export const privateKey3 = Buffer.from('7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6', 'hex')
export const privateKey4 = Buffer.from('47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a', 'hex')
export const privateKey5 = Buffer.from('8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba', 'hex')
export const privateKey6 = Buffer.from('92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e', 'hex')
export const privateKey7 = Buffer.from('4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356', 'hex')
export const privateKey8 = Buffer.from('dbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97', 'hex')
export const privateKey9 = Buffer.from('2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6', 'hex')

export const signPacked = (digest: any, privateKey: any) => {
  const { v, r, s } = ecsign(Buffer.from(digest.slice(2), 'hex'), privateKey)
  return '0x' + r.toString('hex') + s.toString('hex') + v.toString(16)
}

export const sign = (digest: any, privateKey: any) => {
  return ecsign(Buffer.from(digest.slice(2), 'hex'), privateKey)
}

export const SIGNATURE_TYPEHASH = keccak256(
  toUtf8Bytes('Signature(address user,address delegate,uint256 nonce,uint256 deadline)')
)

export const PERMIT_TYPEHASH = keccak256(
  toUtf8Bytes('Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)')
)

export const DAI_TYPEHASH = '0xea2aa0a1be11a07ed86d755c93467f4f82362b452371d1ba94d1715123511acb'
export const CHAI_SEPARATOR = '0x0b50407de9fa158c2cba01a99633329490dfd22989a150c20e8c7b4c1fb0fcc3'

// Returns the EIP712 hash which should be signed by the user
// in order to make a call to `addDelegateBySignature`
export function getSignatureDigest(
  separator: string,
  signature: {
    user: string
    delegate: string
  },
  signatureCount: BigNumberish,
  deadline: BigNumberish
) {
  return keccak256(
    solidityPack(
      ['bytes1', 'bytes1', 'bytes32', 'bytes32'],
      [
        '0x19',
        '0x01',
        separator,
        keccak256(
          defaultAbiCoder.encode(
            ['bytes32', 'address', 'address', 'uint256', 'uint256'],
            [SIGNATURE_TYPEHASH, signature.user, signature.delegate, signatureCount, deadline]
          )
        ),
      ]
    )
  )
}

// Returns the EIP712 hash which should be signed by the user
// in order to make a call to `permit`
export function getPermitDigest(
  separator: string,
  approve: {
    owner: string
    spender: string
    value: BigNumberish
  },
  nonce: BigNumberish,
  deadline: BigNumberish
) {
  return keccak256(
    solidityPack(
      ['bytes1', 'bytes1', 'bytes32', 'bytes32'],
      [
        '0x19',
        '0x01',
        separator,
        keccak256(
          defaultAbiCoder.encode(
            ['bytes32', 'address', 'address', 'uint256', 'uint256', 'uint256'],
            [PERMIT_TYPEHASH, approve.owner, approve.spender, approve.value, nonce, deadline]
          )
        ),
      ]
    )
  )
}

// Works also for Chai
export function getDaiDigest(
  separator: string,
  approve: {
    owner: string
    spender: string
    can: boolean
  },
  nonce: BigNumberish,
  deadline: BigNumberish
) {
  return keccak256(
    solidityPack(
      ['bytes1', 'bytes1', 'bytes32', 'bytes32'],
      [
        '0x19',
        '0x01',
        separator,
        keccak256(
          defaultAbiCoder.encode(
            ['bytes32', 'address', 'address', 'uint256', 'uint256', 'bool'],
            [DAI_TYPEHASH, approve.owner, approve.spender, nonce, deadline, approve.can]
          )
        ),
      ]
    )
  )
}

// Gets an EIP712 domain separator
export function getDomainSeparator(name: string, contractAddress: string, version: string, chainId: number) {
  return keccak256(
    defaultAbiCoder.encode(
      ['bytes32', 'bytes32', 'bytes32', 'uint256', 'address'],
      [
        keccak256(toUtf8Bytes('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')),
        keccak256(toUtf8Bytes(name)),
        keccak256(toUtf8Bytes(version)),
        chainId,
        contractAddress,
      ]
    )
  )
}