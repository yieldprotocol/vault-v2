pragma solidity ^0.6.2;

import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "./interfaces/IVat.sol";
import "./interfaces/IPot.sol";
import "./YToken.sol";


///@dev yDai is a yToken targeting Dai
contract YDai {
    using DecimalMath for uint256;
    using DecimalMath for uint8;

    event Matured(uint256 rate, uint256 chi);

    IERC20 public underlying;
    ITreasury public treasury;

    // TODO: Move to Constants.sol
    // Fixed point precisions from MakerDao
    uint8 constant public wad = 18;
    uint8 constant public ray = 27;
    uint8 constant public rad = 45;

    bool public isMature;
    uint256 public maturity;
    uint256 public maturityChi;  // accumulator (for dsr) at maturity in ray units
    uint256 public maturityRate; // accumulator (for stability fee) at maturity in ray units

    constructor(
        address underlying_,
        address treasury_,
        uint256 maturity_
    ) public {
        underlying = IERC20(underlying_);
        treasury = ITreasury(treasury_);
        maturity = maturity_;
    }

    /// @dev Return debt in underlying of an user
    /// TODO: This needs to move to Treasury.sol, which also needs then to have the maturity data
    function debtOf(address user) public view returns (uint256) {
        if (isMature){
            (, uint256 rate,,,) = vat.ilks("ETH-A");
            return debt[user].muld(rate.divd(maturityRate, ray), ray);
        } else {
            return debt[user];
        }
    }

    /// @dev Mature yToken to make redeemable.
    function mature() public returns (bool) {
        require(
            // solium-disable-next-line security/no-block-members
            now > maturity,
            "YToken: Too early to mature"
        );
        (, maturityRate,,,) = vat.ilks("ETH-A"); // Retrieve the MakerDAO DSR
        maturityRate = Math.max(maturityRate, ray.unit()); // Floor it at 1.0
        maturityChi = pot.chi();
        isMature = true;
        emit Matured(maturityRate, maturityChi);
        return true;
    }

        /// @dev Mint yTokens by posting an equal amount of underlying.
    function mint(uint256 amount) public returns (bool) {
        require(
            // RTODO: Replace for a treasury.DSRstore() call
            underlying.transferFrom(msg.sender, address(this), amount) == true,
            "YToken: Failed transfer"
        );
        _mint(msg.sender, amount);
        return true;
    }

    /// @dev Burn yTokens and return an equal amount of underlying.
    function redeem(uint256 amount) public returns (bool) {
        require(
            // solium-disable-next-line security/no-block-members
            isMature,
            "YToken: Not matured yet"
        );
        _burn(msg.sender, amount);
        require(
            treasury.disburse(msg.sender, amount) == true,
            "YToken: Failed disburse"
        );
        return true;
    }

    /// @dev Mint yTokens by locking its market value in collateral. Debt is recorded in the vault.
    function borrow(uint256 amount) public returns (bool) {
        // The vault will revert if there is not enough unlocked collateral
        treasury.lock(msg.sender, debt[msg.sender]);
        _mint(msg.sender, amount);
        return true;
    }

    /// @dev Burn yTokens and unlock its market value in collateral. Debt is erased in the vault.
    function repay(uint256 amount) public returns (bool) {
        _burn(msg.sender, amount);
        treasury.unlock(msg.sender, amount); // If repaying more than the debt, this should revert.
        return true;
    }
}