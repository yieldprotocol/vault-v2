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
    REMOVE_REPAY:         11,
    FORWARD_PERMIT:       12,
    FORWARD_DAI_PERMIT:   13,
    JOIN_ETHER:           14,
    EXIT_ETHER:           15,
    TRANSFER_TO_POOL:     16,
    ROUTE:                17,
    TRANSFER_TO_FYTOKEN:  18,
    REDEEM:               19,
    MODULE:               20,
  }

export const CHI = ethers.utils.formatBytes32String('chi').slice(0, 14)
export const RATE = ethers.utils.formatBytes32String('rate').slice(0, 14)
