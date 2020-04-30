pragma solidity ^0.6.2;


interface ITreasury {
    /// @dev Moves Eth collateral from user into Treasury controlled Maker Eth vault
    function post(address from, uint256 amount) external;

    /// @dev Moves Eth collateral from Treasury controlled Maker Eth vault back to user
    function withdraw(address receiver, uint256 amount) external;

    /// @dev Moves Dai from user into Treasury controlled Maker Dai vault
    function repay(address source, uint256 amount) external;

    /// @dev moves Dai from Treasury to user, borrowing from Maker DAO if not enough present.
    function disburse(address receiver, uint256 amount) external;
}
