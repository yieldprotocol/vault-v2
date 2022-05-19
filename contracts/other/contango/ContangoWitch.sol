// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "../../Witch.sol";

contract ContangoWitch is Witch {
    constructor(ICauldron cauldron_, ILadle ladle_) Witch(cauldron_, ladle_) {}
}
