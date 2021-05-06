import { ethers } from 'ethers'

export const OPS = {
    BUILD:                0,
    TWEAK:                1,
    GIVE:                 2,
    DESTROY:              3,
    STIR:                 4,
    POUR:                 5,
    SERVE:                6,
    ROLL:                 7,
    CLOSE:                8,
    REPAY:                9,
    REPAY_VAULT:          10,
    FORWARD_PERMIT:       11,
    FORWARD_DAI_PERMIT:   12,
    JOIN_ETHER:           13,
    EXIT_ETHER:           14,
    TRANSFER_TO_POOL:     15,
    ROUTE:                16,
    TRANSFER_TO_FYTOKEN:  17,
    REDEEM:               18,
    MODULE:               19,
  }

export const CHI = ethers.utils.formatBytes32String('chi')
export const RATE = ethers.utils.formatBytes32String('rate')
