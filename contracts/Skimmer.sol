pragma solidity ^0.6.2;

import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IVat.sol";
import "./interfaces/IJug.sol";
import "./interfaces/IPot.sol";
import "./interfaces/IChai.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IDealer.sol";
import "./interfaces/IYDai.sol";
import "./Constants.sol";


/// @dev A splitter moves positions and weth collateral from Dealers (using the IDealer interface) to MakerDAO.
contract Skimmer is Ownable(), Constants {
    using SafeMath for uint256;
    using DecimalMath for uint256;
    using DecimalMath for uint8;

    address constant beneficiary = 0x0000000000000000000000000000000000000000;

    IVat internal _vat;
    IJug internal _jug;
    IPot internal _pot;
    IChai internal _chai;
    ITreasury internal _treasury;
    IDealer internal _dealer;

    // TODO: Series related code is repeated with Dealer, can be extracted into a parent class.
    mapping(uint256 => IYDai) public series;                 // YDai series, indexed by maturity
    uint256[] internal seriesIterator;                                // We need to know all the series

    constructor (
        address vat_,
        address jug_,
        address pot_,
        address chai_,
        address treasury_,
        address dealer_
    ) public {
        _vat = IVat(vat_);
        _jug = IJug(jug_);
        _pot = IPot(pot_);
        _chai = IChai(chai_);
        _treasury = ITreasury(treasury_);
        _dealer = IDealer(dealer_);
    }

    /// @dev Returns if a series has been added to the Dealer, for a given series identified by maturity
    function containsSeries(uint256 maturity) public view returns (bool) {
        return address(series[maturity]) != address(0);
    }

    /// @dev Adds an yDai series to this Dealer
    function addSeries(address yDaiContract) public onlyOwner {
        uint256 maturity = IYDai(yDaiContract).maturity();
        require(
            !containsSeries(maturity),
            "Dealer: Series already added"
        );
        series[maturity] = IYDai(yDaiContract);
        seriesIterator.push(maturity);
    }

    /// @dev Calculates how much profit is in the system and transfers it to the beneficiary
    function skim() public {
        uint256 chi = getChi();
        uint256 rate = getRate();
        uint256 profit = _chai.balanceOf(address(_treasury));

        for (uint256 i = 0; i < seriesIterator.length; i += 1) {
            uint256 maturity = seriesIterator[i];
            IYDai yDai = IYDai(series[seriesIterator[i]]);
            require(
                yDai.isMature(),
                "YDai: All yDai mature first"
            );
            uint256 chi0 = yDai.chi0();
            uint256 rate0 = yDai.rate0();
            profit = profit.add(_dealer.systemDebtYDai(WETH, maturity).muld(rate.divd(rate0, RAY), RAY).divd(chi0, RAY));
            profit = profit.add(_dealer.systemDebtYDai(CHAI, maturity).divd(chi0, RAY));
            profit = profit.sub(yDai.totalSupply().divd(chi0, RAY));
        }

        profit = profit.sub(_treasury.debt().divd(chi, RAY));
        profit = profit.sub(_dealer.systemPosted(CHAI));

        _treasury.pullChai(beneficiary, profit);
    }

    function getChi() public returns (uint256) {
        return (now > _pot.rho()) ? _pot.drip() : _pot.chi();
    }

    function getRate() public returns (uint256) {
        uint256 rate;
        (, uint256 rho) = _jug.ilks("ETH-A"); // "WETH" for weth.sol, "ETH-A" for MakerDAO
        if (now > rho) {
            rate = _jug.drip("ETH-A");
        } else {
            (, rate,,,) = _vat.ilks("ETH-A");
        }
        return rate;
    }
}