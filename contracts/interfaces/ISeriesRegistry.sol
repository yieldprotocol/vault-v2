// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "./IYDai.sol";


interface ISeriesRegistry {
    function series(uint256) external view returns (IYDai);
    function seriesIterator(uint256) external view returns (uint256);
    function totalSeries() external view returns (uint256);
    function containsSeries(uint256) external view returns (bool);
}