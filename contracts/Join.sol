// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/utils/contracts/token/IERC20.sol";


contract Join {
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

    constructor(/* address vat_, */IERC20 token_) {
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
        // auth
        returns (int128)
    {
        if (amount > 0) {
            // require(live == 1, "GemJoin/not-live");
            // TODO: Consider best practices about safe transfers
            // TODO: Safe casting
            require(token.transferFrom(user, address(this), uint256(int256(amount))), "Failed pull");
        } else {
            // TODO: Consider best practices about safe transfers
            // TODO: Safe casting
            require(token.transfer(user, uint256(-int256(amount))), "Failed push"); 
        }
        return amount;                    // Use this to record in vat a balance different from the amount joined
    }
}