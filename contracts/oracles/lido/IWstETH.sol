// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

interface IWstETH {
    /**
     * @notice Get amount of wstETH obtained for a given amount of stETH
     * @param _stETHAmount amount of stETH
     * @return Amount of wstETH obtained for a given stETH amount
     */
    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);

    /**
     * @notice Get amount of stETH obtained for a given amount of wstETH
     * @param _wstETHAmount amount of wstETH
     * @return Amount of stETH obtained for a given wstETH amount
     */
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);

    /**
     * @notice Get amount of stETH obtained for one wstETH
     * @return Amount of stETH obtained for one wstETH
     */
    function stEthPerToken() external view returns (uint256);

    /**
     * @notice Get amount of wstETH obtained for one stETH
     * @return Amount of wstETH obtained for one stETH
     */
    function tokensPerStEth() external view returns (uint256);
}
