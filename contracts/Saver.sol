pragma solidity ^0.6.0;

import "@hq20/contracts/contracts/access/AuthorizedAccess.sol";
import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ISaver.sol";
import "./Constants.sol";


/// @dev Saver holds Chai.
contract Saver is ISaver, AuthorizedAccess(), Constants() {
    using DecimalMath for uint256;

    IERC20 internal _chai;

    constructor (address chai_) public {
        // These could be hardcoded for mainnet deployment.
        _chai = IERC20(chai_);
    }

    /// @dev Returns the amount of Chai in this contract.
    function savings() public view override returns(uint256){
        return _chai.balanceOf(address(this));
    }

    /// @dev Moves Chai into the contract
    function join(uint256 chai) public override onlyAuthorized("Saver: Not Authorized") {
        join(msg.sender, chai);
    }

    /// @dev Moves Chai into the contract
    function join(address user, uint256 chai) public override onlyAuthorized("Saver: Not Authorized") {
        require(
            _chai.transferFrom(msg.sender, address(this), chai),
            "Saver: Chai transfer fail"
        );
    }

    /// @dev Moves Chai out of the contract
    function exit(uint256 chai) public override onlyAuthorized("Saver: Not Authorized") {
        exit(msg.sender, chai);
    }

    /// @dev Moves Chai out of the contract
    function exit(address user, uint256 chai) public override onlyAuthorized("Saver: Not Authorized") {
        require(
            _chai.transfer(user, chai),
            "Saver: Chai transfer fail"
        );
    }
}
