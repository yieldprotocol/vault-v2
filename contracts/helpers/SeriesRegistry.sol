pragma solidity ^0.6.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IYDai.sol";

contract SeriesRegistry is Ownable() {
    mapping(uint256 => IYDai) public series;                 // YDai series, indexed by maturity
    uint256[] public seriesIterator;                                // We need to know all the series

    /// @dev Only series added through `addSeries` are valid.
    modifier validSeries(uint256 maturity) {
        require(
            containsSeries(maturity),
            "Controller: Unrecognized series"
        );
        _;
    }

    /// @dev Returns if a series has been added to the Controller, for a given series identified by maturity
    function containsSeries(uint256 maturity) public view returns (bool) {
        return address(series[maturity]) != address(0);
    }

    /// @dev Adds an yDai series to this Controller
    function addSeries(address yDaiContract) public onlyOwner {
        uint256 maturity = IYDai(yDaiContract).maturity();
        require(
            !containsSeries(maturity),
            "Controller: Series already added"
        );
        series[maturity] = IYDai(yDaiContract);
        seriesIterator.push(maturity);
    }
}