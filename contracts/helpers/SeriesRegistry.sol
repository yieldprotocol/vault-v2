pragma solidity ^0.6.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/ISeriesRegistry.sol";
import "../interfaces/IYDai.sol";

contract SeriesRegistry is ISeriesRegistry, Ownable() {
    mapping(uint256 => IYDai) public override series;                 // YDai series, indexed by maturity
    uint256[] public override seriesIterator;                         // We need to know all the series

    /// @dev Only series added through `addSeries` are valid.
    modifier validSeries(uint256 maturity) {
        require(
            containsSeries(maturity),
            "Controller: Unrecognized series"
        );
        _;
    }

    /// @dev Return the total number of series registered
    function totalSeries() public view override returns (uint256) {
        return seriesIterator.length;
    }

    /// @dev Returns if a series has been added to the Controller, for a given series identified by maturity
    function containsSeries(uint256 maturity) public view override returns (bool) {
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