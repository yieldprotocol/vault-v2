import { keccak256, defaultAbiCoder, toUtf8Bytes, solidityPack } from 'ethers/lib/utils'
import { BigNumberish } from 'ethers'
import { ecsign } from 'ethereumjs-util'

export const userPrivateKey = Buffer.from('d49743deccbccc5dc7baa8e69e5be03298da8688a15dd202e20f15d5e0e9a9fb', 'hex')

export const sign = (digest: any, privateKey: any) => {
  const { v, r, s } = ecsign(Buffer.from(digest.slice(2), 'hex'), privateKey)
  return '0x' + r.toString('hex') + s.toString('hex') + v.toString(16)
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
  name: string,
  address: string,
  chainId: number,
  signature: {
    user: string
    delegate: string
  },
  signatureCount: BigNumberish,
  deadline: BigNumberish
) {
  const DOMAIN_SEPARATOR = getDomainSeparator(name, address, chainId)
  return keccak256(
    solidityPack(
      ['bytes1', 'bytes1', 'bytes32', 'bytes32'],
      [
        '0x19',
        '0x01',
        DOMAIN_SEPARATOR,
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
  name: string,
  address: string,
  chainId: number,
  approve: {
    owner: string
    spender: string
    value: BigNumberish
  },
  nonce: BigNumberish,
  deadline: BigNumberish
) {
  const DOMAIN_SEPARATOR = getDomainSeparator(name, address, chainId)
  return keccak256(
    solidityPack(
      ['bytes1', 'bytes1', 'bytes32', 'bytes32'],
      [
        '0x19',
        '0x01',
        DOMAIN_SEPARATOR,
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

export function getDaiDigest(
  name: string,
  address: string,
  chainId: number,
  approve: {
    owner: string
    spender: string
    can: boolean
  },
  nonce: BigNumberish,
  deadline: BigNumberish
) {
  const DOMAIN_SEPARATOR = getDomainSeparator(name, address, chainId)
  return keccak256(
    solidityPack(
      ['bytes1', 'bytes1', 'bytes32', 'bytes32'],
      [
        '0x19',
        '0x01',
        DOMAIN_SEPARATOR,
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

// Gets the EIP712 domain separator
export function getDomainSeparator(name: string, contractAddress: string, chainId: number) {
  return keccak256(
    defaultAbiCoder.encode(
      ['bytes32', 'bytes32', 'bytes32', 'uint256', 'address'],
      [
        keccak256(toUtf8Bytes('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')),
        keccak256(toUtf8Bytes(name)),
        keccak256(toUtf8Bytes('1')),
        chainId,
        contractAddress,
      ]
    )
  )
}

export function getChaiDigest(
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
        CHAI_SEPARATOR,
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
