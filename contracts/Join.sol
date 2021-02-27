// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/utils/contracts/token/IERC20.sol";
import "./AccessControl.sol";


library Safe256 {
    /// @dev Safely cast an int128 to an uint128
    function u256(int256 x) internal pure returns (uint256 y) {
        require (x >= 0, "Cast overflow");
        y = uint256(x);
    }
}

contract Join is AccessControl() {
    using Safe256 for int256;

    // --- Auth ---
    /* mapping (address => uint) public wards;
    function rely(address usr) external auth { wards[usr] = 1; }
    function deny(address usr) external auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "GemJoin/not-authorized");
        _;
    } */

    IERC20 public token;
    // bytes6  public asset;   // Collateral Type
    // uint    public dec;
    // uint    public live;  // Active Flag

    constructor(/* address cauldron_, */IERC20 token_) {
        // wards[msg.sender] = 1;
        token = token_;
        // asset = asset_;
        // dec = token.decimals();
        // live = 1;
    }

    /*
    function cage() external auth {
        live = 0;
    }
    */

    function join(address user, int128 amount)
        external
        auth
        returns (int128)
    {
        // console.logInt(amount);
        // console.log(token.balanceOf(address(this)));
        if (amount > 0) {
            // require(live == 1, "GemJoin/not-live");
            // TODO: Consider best practices about safe transfers
            require(token.transferFrom(user, address(this), int256(amount).u256()), "Failed pull");
        } else {
            // TODO: Consider best practices about safe transfers
            require(token.transfer(user, (-int256(amount)).u256()), "Failed push"); 
        }
        return amount;                    // Use this to record in cauldron a balance different from the amount joined
    }
}