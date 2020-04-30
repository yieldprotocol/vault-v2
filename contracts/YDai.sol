pragma solidity ^0.6.0;

import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IPot.sol";
import "./interfaces/IVat.sol";
import "./Constants.sol";


///@dev yDai is a yToken targeting Dai
contract YDai is Constants, Ownable, ERC20 {
    using DecimalMath for uint256;
    using DecimalMath for uint8;

    event Matured(uint256 rate, uint256 chi);

    IVat public vat;
    IPot public pot;

    bool public isMature;
    uint256 public maturity;
    uint256 public maturityChi;  // accumulator (for dsr) at maturity in ray units
    uint256 public maturityRate; // accumulator (for stability fee) at maturity in ray units

    constructor(
        string memory name,
        string memory symbol,
        address vat_,
        address pot_,
        uint256 maturity_
    ) public ERC20(name, symbol) Ownable() {
        vat = IVat(vat_);
        pot = IPot(pot_);
        maturity = maturity_;
    }

    /// @dev Mature yDai and capture maturity data
    /// TODO: Should we just take maturityRate and maturityChi as parameters?
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
}