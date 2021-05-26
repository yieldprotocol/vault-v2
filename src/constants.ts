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
    REPAY_LADLE:          11,
    RETRIEVE:             12,
    FORWARD_PERMIT:       13,
    FORWARD_DAI_PERMIT:   14,
    JOIN_ETHER:           15,
    EXIT_ETHER:           16,
    TRANSFER_TO_POOL:     17,
    ROUTE:                18,
    TRANSFER_TO_FYTOKEN:  19,
    REDEEM:               20,
    MODULE:               21,
  }

export const CHI = ethers.utils.formatBytes32String('chi').slice(0, 14)
export const RATE = ethers.utils.formatBytes32String('rate').slice(0, 14)
