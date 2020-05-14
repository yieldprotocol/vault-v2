pragma solidity ^0.6.0;

import "@hq20/contracts/contracts/access/AuthorizedAccess.sol";
import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IChai.sol";
import "./interfaces/ISaver.sol";
import "./Constants.sol";


/// @dev Saver holds Chai.
contract Saver is ISaver, AuthorizedAccess(), Constants() {
    using DecimalMath for uint256;

    IERC20 internal _dai;
    IChai internal _chai;

    constructor (address dai_, address chai_) public {
        // These could be hardcoded for mainnet deployment.
        _dai = IERC20(dai_);
        _chai = IChai(chai_);
    }

    /// @dev Returns the amount of Dai in this contract.
    function savings() public override returns(uint256){
        return _chai.dai(address(this));
    }

    // Anyone can send chai to saver, no way of stopping it

    /// @dev Moves Dai into the contract and converts it to Chai
    function hold(address user, uint256 dai) public override onlyAuthorized("Saver: Not Authorized") {
        require(
            _dai.transferFrom(user, address(this), dai),
            "Saver: Chai transfer fail"
        );                                 // Take dai from user
        _dai.approve(address(_chai), dai); // Chai will take dai
        _chai.join(address(this), dai);    // Give dai to Chai, take chai back
    }

    // Make another function to withdraw cahi, so that ChaiDealer can use it.

    /// @dev Converts Chai to Dai and gives it to the user
    function release(address user, uint256 dai) public override onlyAuthorized("Saver: Not Authorized") {
        _chai.draw(address(this), dai);     // Grab dai from Chai, converted from chai
        require(                            // Give dai to user
            _dai.transfer(user, dai),
            "Saver: Dai transfer fail"
        );
    }
}