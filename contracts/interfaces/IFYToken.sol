// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/utils/contracts/token/IERC20.sol";
import "./IOracle.sol";


interface IFYToken is IERC20 {
    /// @dev Token that is returned on redemption. Also called underlying.
    function asset() external view returns (IERC20);

    /// @dev Oracle that returns the accrual of the borrowing rate, which is accrued after maturity.
    function oracle() external view returns (IOracle);

    /// @dev Unix time at which redemption of fyToken for underlying are possible
    function maturity() external view returns (uint32);
    
    /// @dev Record price data at maturity
    function mature() external;

    /// @dev Burn fyToken after maturity for an amount of underlying.
    // function redeem(uint256 amount) external returns (uint256);

    /// @dev Mint fyToken.
    /// This function can only be called by other Yield contracts, not users directly.
    /// @param to Wallet to mint the fyToken in.
    /// @param fyTokenAmount Amount of fyToken to mint.
    function mint(address to, uint256 fyTokenAmount) external;

    /// @dev Burn fyToken.
    /// This function can only be called by other Yield contracts, not users directly.
    /// @param from Wallet to burn the fyToken from.
    /// @param fyTokenAmount Amount of fyToken to burn.
    function burn(address from, uint256 fyTokenAmount) external;
}