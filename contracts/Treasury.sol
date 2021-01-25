// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;


import "./interfaces/ITreasury.sol";
import "./helpers/DecimalMath.sol";
import "./helpers/Orchestrated.sol";


contract Treasury is ITreasury, Orchestrated(), DecimalMath {
    bool public override live = true;

    mapping(IERC20 => bool) public knownTokens;

    /// @dev Only while the Treasury is not unwinding due to a MakerDAO shutdown.
    modifier onlyLive() {
        require(live == true, "Treasury: Not available during unwind");
        _;
    }

    modifier knownToken(IERC20 token) {
        require(knownTokens[token] == true, "Treasury: Unregistered token");
        _;
    }

    /// @dev Disables pulling and pushing. Can only be called if MakerDAO shuts down.
    function shutdown()
        public override
        onlyOwner
    {
        live = false;
    }

    function registerToken(IERC20 token)
        public override
        onlyOwner
    {
        knownTokens[token] = true;
    }

    /// @dev Takes token from user.
    function push(IERC20 token, address from, uint256 amount)
        public override
        onlyOrchestrated("Treasury: Not Authorized")
        onlyLive
        knownToken(token)
    {
        require(token.transferFrom(from, address(this), amount)); // TODO: Require message and safetransfer
    }

    /// @dev Returns token to user.
    function pull(IERC20 token, address to, uint256 amount)
        public override
        onlyOrchestrated("Treasury: Not Authorized")
        onlyLive
        knownToken(token)
    {
        require(token.transfer(to, amount)); // TODO: Require message and safetransfer
    }
}
