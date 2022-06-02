import { BigNumber, ethers } from 'ethers'

export const WAD = BigNumber.from(10).pow(18)
export const RAY = BigNumber.from(10).pow(27)
export const MAX128 = BigNumber.from(2).pow(128).sub(1)
export const MAX256 = BigNumber.from(2).pow(256).sub(1)
export const THREE_MONTHS: number = 3 * 30 * 24 * 60 * 60

export const ETH = ethers.utils.formatBytes32String('ETH').slice(0, 14)
export const DAI = ethers.utils.formatBytes32String('DAI').slice(0, 14)
export const USDC = ethers.utils.formatBytes32String('USDC').slice(0, 14)
