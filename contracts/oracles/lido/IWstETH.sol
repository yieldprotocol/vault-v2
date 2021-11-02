// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;
import '@yield-protocol/utils-v2/contracts/token/IERC20.sol';

interface IWstETH is IERC20 {
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

    /**
     * @notice Exchanges stETH to wstETH
     * @param _stETHAmount amount of stETH to wrap in exchange for wstETH
     * @dev Requirements:
     *  - `_stETHAmount` must be non-zero
     *  - msg.sender must approve at least `_stETHAmount` stETH to this
     *    contract.
     *  - msg.sender must have at least `_stETHAmount` of stETH.
     * User should first approve _stETHAmount to the WstETH contract
     * @return Amount of wstETH user receives after wrap
     */
    function wrap(uint256 _stETHAmount) external returns (uint256);

    /**
     * @notice Exchanges wstETH to stETH
     * @param _wstETHAmount amount of wstETH to uwrap in exchange for stETH
     * @dev Requirements:
     *  - `_wstETHAmount` must be non-zero
     *  - msg.sender must have at least `_wstETHAmount` wstETH.
     * @return Amount of stETH user receives after unwrap
     */
    function unwrap(uint256 _wstETHAmount) external returns (uint256);
}
