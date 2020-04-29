pragma solidity ^0.6.0;

/* import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IVat.sol";
import "./interfaces/IPot.sol";


///@dev yDai is a yToken targeting Dai
contract YDai is Ownable() {
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

    /// @dev Mint yDai. Only callable by its Controller contract.
    function mint(address user, uint256 amount) public onlyOwner {
        _mint(user, amount);
    }

    /// @dev Burn yDai. Only callable by its Controller contract.
    function burn(address user, uint256 amount) public onlyOwner {
        _burn(user, amount);
    }
} */