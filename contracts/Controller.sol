pragma solidity ^0.6.2;

import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IOracle.sol";
import "./Constants.sol";


/// @dev Controller is the top layer that implements rules and keeps the system state
contract Controller is Ownable, Constants {
    using DecimalMath for uint256;
    using DecimalMath for int256;
    using DecimalMath for uint8;

    ITreasury internal _treasury;
    IERC20 internal _weth;
    IERC20 internal _dai;
    IYDai internal _yDai;
    IOracle internal _daiOracle;

    mapping(address => uint256) internal posted; // In WETH
    mapping(address => uint256) internal debt; // In DAI

    uint256 public stability; // accumulator (for stability fee) at maturity in ray units
    uint256 public collateralization; // accumulator (for stability fee) at maturity in ray units

    constructor (address treasury_, address yDai_, address daiOracle_) public {
        _treasury = ITreasury(treasury_);
        _yDai = IYDai(yDai_);
        _daiOracle = IOracle(daiOracle_);
    }

    /// @dev Collateral not in use for debt
    ///
    ///                       debtOf(user)(wad)
    /// posted[user](wad) - -----------------------
    ///                       daiOracle.get()(ray)
    ///
    function unlockedOf(address user) public view returns (uint256) {
        // TODO: Reverts when unlocked collateral goes into the negative
        return posted[user].sub(debtOf(user).divd(_daiOracle.get(), ray));
    }

    /// @dev Moves Eth collateral from user into Treasury controlled Maker Eth vault
    function post(address user, uint256 amount) public {
        posted[user] = posted[user].add(amount);
        _treasury.post(user, amount);
    }

    /// @dev Moves Eth collateral from Treasury controlled Maker Eth vault back to user
    function withdraw(address user, uint256 amount) public {
        require(
            unlockedOf(user) >= amount,
            "Accounts: Free more collateral"
        )
        posted[user] = posted[user].sub(amount); // Will revert if not enough posted
        _treasury.withdraw(user, amount);
    }

    /// @dev Mint yTokens by locking its market value in collateral. Debt is recorded in the vault.
    ///
    /// posted[user](wad) >= (debt[user](wad)) * amount (wad)) * collateralization (ray)
    ///
    function borrow(address user, uint256 amount) public {
        require(
            _yDai.isMature != true,
            "Accounts: No mature borrow"
        );
        require(
            posted[user] >= (debtOf(user).add(amount)).muld(collateralization, ray),
            "Accounts: Post more collateral"
        )
        debt[user] = debt[user].add(amount); // TODO: Check collateralization ratio
        _treasury.mint(user, amount);
    }

    /// @dev Moves Dai from user into Treasury controlled Maker Dai vault
    function repay(address user, uint256 amount) public {
        // TODO: Needs to reverse the `debtOf` formula
        debt[user] = debt[user].sub(amount); // Will revert if not enough debt
        _treasury.repay(user, amount);
    }

    /// @dev Mint yTokens by posting an equal amount of underlying.
    function mint(address user, uint256 amount) public {
        _treasury.mint(user, amount);
    }

    /// @dev Burn yTokens and return an equal amount of underlying.
    function redeem(address user, uint256 amount) public returns (bool) {
        require(
            _yDai.isMature() == true,
            "Accounts: Only mature redeem"
        );
        _treasury.burn(user, amount);
    }

    /// @dev Return debt in underlying of an user
    /// TODO: This needs to move to Treasury.sol, which also needs then to have the maturity data
    function debtOf(address user) public view returns (uint256) {
        if (_yDai.isMature){
            (, uint256 rate,,,) = vat.ilks("ETH-A");
            return debt[user].muld(rate.divd(maturityRate, ray), ray);
        } else {
            return debt[user];
        }
    }
}