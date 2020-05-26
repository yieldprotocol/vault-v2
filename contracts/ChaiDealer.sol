pragma solidity ^0.6.2;

import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IChai.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ITreasury.sol";
import "./Constants.sol";
import "./ERC20Dealer.sol";


/// @dev A ChaiDealer takes chai as collateral and issues yDai. Chai is saved in the Saver.
contract ChaiDealer is ERC20Dealer {
    using DecimalMath for uint256;

    IChai internal _chai;
    IOracle internal _chaiOracle;

    constructor (
        address treasury_,
        address dai_,
        address yDai_,
        address chai_,
        address chaiOracle_
    ) public ERC20Dealer(treasury_, dai_, yDai_, chai_, chaiOracle_) {
        _chai = IChai(chai_);
        _chaiOracle = IOracle(chaiOracle_);
    }

    /// @dev Takes chai from `from` address, unwraps it to dai, and gives it to the Treasury
    // from --- Chai -> Dai ---> treasury
    function post(address from, uint256 chai) public override {
        // TODO: Consider a require on super.post()
        super.post(from, chai);                             // Grab chai and update posted
        uint256 dai = chai.divd(_chaiOracle.price(), RAY);  // dai = chai / price
        _chai.draw(address(this), dai);                     // Grab dai from Chai, converted from chai
        _dai.transfer(address(_treasury), dai);             // Give Treasury the dai
        _treasury.push();                                   // Have Treasury process the dai
    }

    /// @dev Takes dai from Treasury, wraps it to chai, and gives it to `to` address
    // Treasury --- Dai -> Chai ---> to
    function withdraw(address to, uint256 chai) public override {
        uint256 dai = chai.divd(_chaiOracle.price(), RAY);  // dai = chai / price
        _treasury.pull(address(this), dai);                 // Take dai from treasury
        _dai.approve(address(_chai), dai);                  // Chai will take dai
        _chai.join(address(this), dai);                     // Give dai to Chai, take chai back
        super.withdraw(to, chai);                           // Check collateralization, send chai to user and update posted
        // TODO: Consider a require on super.withdraw()
    }

    /// @dev Takes dai from Treasury, and gives it to `to` address
    // Treasury --- Dai ---> to
    function withdrawDai(address to, uint256 dai) public {
        require(
            powerOf(to) >= debtDai(to),
            "ChaiDealer: Undercollateralized"
        );
        require(
            powerOf(to) - debtDai(to) >= dai, // SafeMath not needed
            "ChaiDealer: Free more collateral"
        );
        uint256 chai = dai.muld(_chaiOracle.price(), RAY);  // chai = dai * price
        posted[to] = posted[to].sub(chai);                  // Will revert if not enough posted

        _treasury.pull(to, dai);                            // Take dai from treasury
    }
}