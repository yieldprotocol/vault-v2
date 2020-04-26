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

    /// @dev Mature yDai and capture maturity data
    function mature() public {
        require(
            // solium-disable-next-line security/no-block-members
            now > maturity,
            "YDai: Too early to mature"
        );
        (, maturityRate,,,) = vat.ilks("ETH-A"); // Retrieve the MakerDAO DSR
        maturityRate = Math.max(maturityRate, ray.unit()); // Floor it at 1.0
        maturityChi = pot.chi();
        isMature = true;
        emit Matured(maturityRate, maturityChi);
    }

    /// @dev Mint yDai.
    function mint(address user, uint256 amount) public {
        _mint(user, amount);
    }

    /// @dev Burn yTokens and unlock its market value in collateral. Debt is erased in the vault.
    function burn(address user, uint256 amount) public {
        _burn(user, amount);
    }
}