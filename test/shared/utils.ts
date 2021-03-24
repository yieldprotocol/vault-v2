import { BigNumber } from 'ethers'

export const WAD = BigNumber.from('1000000000000000000')
export const RAY = BigNumber.from('1000000000000000000000000000')
export const MAX = BigNumber.from(2).pow(256).sub(1)
export const THREE_MONTHS: number = 3 * 30 * 24 * 60 * 60
