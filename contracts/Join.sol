// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/utils/contracts/token/IERC20.sol";
import "@yield-protocol/vault-interfaces/IJoin.sol";
import "./AccessControl.sol";


contract Join is IJoin, AccessControl() {
    IERC20 public override token;
    uint256 public storedBalance;
    // bytes6  public asset;   // Collateral Type
    // uint    public dec;
    // uint    public live;  // Active Flag

    constructor(IERC20 token_) {
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

    /// @dev With a positive `amount`, `join` will `transferFrom` the user the `amount`, minus any unaccounted `token` already present.
    /// Users can `transfer` to this contract and then execute `join`, as well as `approve` this contract and let `join` pull the tokens.
    function join(address user, int128 amount)
        external override
        auth
        returns (int128)
    {
        if (amount >= 0) {
            // require(live == 1, "GemJoin/not-live");
            uint256 amount_ = uint128(amount);
            uint256 initialBalance = token.balanceOf(address(this));
            uint256 surplus = initialBalance - storedBalance;
            uint256 required = surplus >= amount_ ? 0 : amount_ - surplus;
            storedBalance = initialBalance + required;
            if (required > 0) {
                require(token.transferFrom(user, address(this), required), "Failed transfer"); // TODO: Consider best practices about safe transfers
            }
        } else {
            uint256 amount_ = uint128(-amount);
            storedBalance -= amount_;                                  // To withdraw surplus tokens we can do a `join` for zero tokens first.
            require(token.transfer(user, amount_), "Failed transfer"); // TODO: Consider best practices about safe transfers
        }
        return amount;
    }
}