pragma solidity ^0.6.0;

import "@hq20/contracts/contracts/access/AuthorizedAccess.sol";
import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@hq20/contracts/contracts/utils/SafeCast.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IDaiJoin.sol";
import "./interfaces/IGemJoin.sol";
import "./interfaces/IVat.sol";
import "./interfaces/ILender.sol";
import "./Constants.sol";


/// @dev Saver holds Chai.
contract Saver is ISaver, AuthorizedAccess(), Constants() {
    using DecimalMath for uint256;
    using DecimalMath for int256;
    using DecimalMath for uint8;
    using SafeCast for uint256;
    using SafeCast for int256;

    IERC20 internal _chai;

    uint256 public savings; // Make a function

    constructor (address chai_) public {
        // These could be hardcoded for mainnet deployment.
        _chai = IERC20(chai_);
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
        savings = savings.add(chai);
    }

    /// @dev Moves Chai out of the contract
    function exit(uint256 chai) public override onlyAuthorized("Saver: Not Authorized") {
        exit(msg.sender, chai);
    }

    /// @dev Moves Chai out of the contract
    function exit(address user, uint256 chai) public override onlyAuthorized("Saver: Not Authorized") {
        savings = savings.sub(chai, "Saver: Not enough savings");
        require(
            _chai.transfer(user, chai),
            "Saver: Chai transfer fail"
        );
    }
}
