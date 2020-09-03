import { BigNumber, BigNumberish } from 'ethers'
import { formatBytes32String } from 'ethers/lib/utils'
import { expect } from 'chai'

export const chainId = 31337 // buidlerevm chain id
export const name = 'Yield'

/// @dev Converts a bignumberish to a BigNumber (this is useful for compatibility between BN and BigNumber)
export const bnify = (num: BigNumberish) => BigNumber.from(num.toString())

/// @dev 2^256 -1
export const MAX = bnify('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')

/// @dev Converts a BigNumberish to WAD precision, for BigNumberish up to 10 decimal places
export function toWad(value: BigNumberish): BigNumber {
  let exponent = BigNumber.from(10).pow(BigNumber.from(8))
  return BigNumber.from((value as any) * 10 ** 10).mul(exponent)
}

/// @dev Converts a BigNumberish to RAY precision, for BigNumberish up to 10 decimal places
export function toRay(value: BigNumberish): BigNumber {
  let exponent = BigNumber.from(10).pow(BigNumber.from(17))
  return BigNumber.from((value as any) * 10 ** 10).mul(exponent)
}

/// @dev Converts a BigNumberish to RAD precision, for BigNumberish up to 10 decimal places
export function toRad(value: BigNumberish): BigNumber {
  let exponent = BigNumber.from(10).pow(BigNumber.from(35))
  return BigNumber.from((value as any) * 10 ** 10).mul(exponent)
}

/// @dev Adds two BigNumberishs
/// I.e. addBN(ray(x), ray(y)) = ray(x - y)
export function addBN(x: BigNumberish, y: BigNumberish): BigNumber {
  return BigNumber.from(x).add(BigNumber.from(y))
}

/// @dev Substracts a BigNumberish from another
/// I.e. subBN(ray(x), ray(y)) = ray(x - y)
export function subBN(x: BigNumberish, y: BigNumberish): BigNumber {
  return BigNumber.from(x).sub(BigNumber.from(y))
}

/// @dev Multiplies a BigNumberish in any precision by a BigNumberish in RAY precision, with the output in the first parameter's precision.
/// I.e. mulRay(wad(x), ray(y)) = wad(x*y)
export function mulRay(x: BigNumberish, ray: BigNumberish): BigNumber {
  return BigNumber.from(x).mul(BigNumber.from(ray)).div(UNIT)
}

/// @dev Divides x by y, rounding up
export function divrup(x: BigNumber, y: BigNumber): BigNumber {
  const z = BigNumber.from(x).mul(10).div(BigNumber.from(y))
  if (z.mod(10).gt(0)) return z.div(10).add(1)
  return z.div(10)
}

// Checks if 2 bignumberish are almost-equal with up to `precision` room for wiggle which by default is 1
export function almostEqual(x: BigNumberish, y: BigNumberish, precision: BigNumberish = 1) {
  x = bnify(x)
  y = bnify(y)

  if (x.gt(y)) {
    expect(x.sub(y).lte(precision)).to.be.true
  } else {
    expect(y.sub(x).lte(precision)).to.be.true
  }
}

/// @dev Divides a BigNumberish in any precision by a BigNumberish in RAY precision, with the output in the first parameter's precision.
/// I.e. divRay(wad(x), ray(y)) = wad(x/y)
export function divRay(x: BigNumberish, ray: BigNumberish): BigNumber {
  return UNIT.mul(BigNumber.from(x)).div(BigNumber.from(ray))
}

/// @dev Divides a BigNumberish in any precision by a BigNumberish in RAY precision, with the output in the first parameter's precision.
/// Rounds up, careful if using negative numbers.
/// I.e. divRay(wad(x), ray(y)) = wad(x/y)
export function divrupRay(x: BigNumberish, ray: BigNumberish): BigNumber {
  const z = UNIT.mul(10).mul(BigNumber.from(x)).div(BigNumber.from(ray))
  if (z.mod(10).gt(0)) return z.div(10).add(1)
  return z.div(10)
}

export const CHAI = formatBytes32String('CHAI')
export const WETH = formatBytes32String('ETH-A')
export const INVALID_COLLATERAL = formatBytes32String('INVALID')
export const Line = formatBytes32String('Line')
export const spotName = formatBytes32String('spot')
export const linel = formatBytes32String('line')

const UNIT: BigNumber = BigNumber.from(10).pow(BigNumber.from(27))

export const limits = toRad(10000)

export const spot = toRay(260) // At the time of writing, spot is 259.625048333333333333333333333, a reasonable range is [50, 1000]
export const chi1 = toRay(1.01) // At the time of writing, chi is 1.018008449363110619399951035, a reasonable upper boundary is 1.2
export const rate1 = toRay(1.02) // At the time of writing, rate is 1.020041883692153436559184034, a reasonable upper boundary is 1.2
export const precision = 10 // Loss in wei that is tolerated with each operation

export const daiDebt1 = toWad(120).toString()
export const daiTokens1 = mulRay(daiDebt1, rate1).toString()
export const wethTokens1 = divRay(daiTokens1, spot).toString()
export const chaiTokens1 = divRay(daiTokens1, chi1).toString()
export const tag = divRay(toRay(1.0), spot)
export const fix = divRay(toRay(1.0), mulRay(spot, toRay(1.1)))
