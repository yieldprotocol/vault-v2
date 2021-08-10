import { ethers } from 'ethers'

export const CHI = ethers.utils.formatBytes32String('chi').slice(0, 14)
export const RATE = ethers.utils.formatBytes32String('rate').slice(0, 14)
