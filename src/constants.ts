import { ethers } from 'ethers'

export const CHI = ethers.utils.formatBytes32String('CHI').slice(0, 14)
export const RATE = ethers.utils.formatBytes32String('RATE').slice(0, 14)

export const ETH = ethers.utils.formatBytes32String('00').slice(0, 14)
export const DAI = ethers.utils.formatBytes32String('01').slice(0, 14)
export const USDC = ethers.utils.formatBytes32String('02').slice(0, 14)
export const WBTC = ethers.utils.formatBytes32String('03').slice(0, 14)
export const WSTETH = ethers.utils.formatBytes32String('04').slice(0, 14)
export const STETH = ethers.utils.formatBytes32String('05').slice(0, 14)
export const LINK = ethers.utils.formatBytes32String('06').slice(0, 14)
export const ENS = ethers.utils.formatBytes32String('07').slice(0, 14)
export const YVDAI = ethers.utils.formatBytes32String('08').slice(0, 14)
export const YVUSDC = ethers.utils.formatBytes32String('09').slice(0, 14)
export const CVX3CRV = ethers.utils.formatBytes32String('10').slice(0, 14)
/**
 *
 * █▀ ▀█▀ █▀█ █▀█ █
 * ▄█  █  █▄█ █▀▀ ▄
 *
 * When adding a new constant, please base it on the constants found in this file:
 * https://github.com/yieldprotocol/environments-v2/blob/main/shared/constants.ts
 */
