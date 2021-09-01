import { ethers } from 'ethers'

export const CHI = ethers.utils.formatBytes32String('chi').slice(0, 14)
export const RATE = ethers.utils.formatBytes32String('rate').slice(0, 14)
export const DAI = ethers.utils.formatBytes32String('DAI').slice(0, 14)
export const USDC = ethers.utils.formatBytes32String('USDC').slice(0, 14)
export const ETH = ethers.utils.formatBytes32String('ETH').slice(0, 14)
