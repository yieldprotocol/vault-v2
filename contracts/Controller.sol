// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/math/Math.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IController.sol";
import "./interfaces/IFYDai.sol";
import "./helpers/Delegable.sol";
import "./helpers/DecimalMath.sol";
import "./helpers/Orchestrated.sol";


/**
 * @dev The Controller manages collateral and debt levels for all users.
 */
contract Controller is IController, Orchestrated(), Delegable(), DecimalMath {
    using SafeMath for uint256;

    event Posted(bytes32 indexed collateral, address indexed user, int256 amount);
    event Borrowed(bytes32 indexed collateral, uint256 indexed maturity, address indexed user, int256 amount);

    ITreasury public override treasury;

    struct Underlying {
        bool registered;
        IERC20 erc20;
    }

    struct Collateral {
        bool registered;
        IERC20 erc20;
        uint256 dust;
    }

    struct Series {
        bool registered;
        IFYToken fyToken;
        Underlying underlying;
    }

    struct Vault { // TODO: Model after MakerDAO CDPs
        bool registered;
        Collateral collateral;
        Series series;
        uint256 assets;
        uint256 debt;
        uint256 lock;
    }

    mapping(IERC20 => Underlying) public override underlyings;
    mapping(IERC20 => Collateral) public override collaterals;
    mapping(IERC20 => mapping(IERC20 => IOracle)) public override oracles;                       // Underlying => Collateral => Oracle
    mapping(IERC20 => mapping(uint256 => Series)) public override series;                        // Underlying => Maturity => fyToken
    mapping(IERC20 => mapping(IFYToken => mapping(address => Vault))) public override vaults;    // Collateral => fyToken => user => Vault
    
    bool public live = true;

    /// @dev Set up address Treasury.
    constructor (
        address treasury_
    ) public {
        treasury = ITreasury(treasury_);
    }

    modifier onlyLive() {
        require(live == true, "Controller: Not available during unwind");
        _;
    }

    modifier validCollateral(IERC20 collateral) {
        require(
            collaterals[collateral].registered == true,
            "Controller: Unregistered collateral"
        );
        _;
    }

    modifier validUnderlying(IERC20 underlying) {
        require(
            underlyings[underlying].registered == true,
            "Controller: Unregistered underlying"
        );
        _;
    }

    modifier validSeries(IERC20 underlying, uint256 maturity) {
        require(
            series[underlying][maturity].registered == true,
            "Controller: Unregistered series"
        );
        _;
    }

    modifier ownsVault(address user, Vault vault) {
        require(
            vaults[vault.collateral][vault.series.fyToken][user].registered == true,
            "Controller: Does not own vault"
        );
        _;
    }

    modifier unlocked(Vault vault) {
        require(
            vault.lock == false,
            "Controller: Vault locked"
        );
        _;
    }

    /// @dev Disables post, withdraw, borrow and repay. To be called only when Treasury shuts down.
    function shutdown() 
        public override
    {
        require(
            treasury.live() == false,
            "Controller: Treasury is live"
        );
        live = false;
    }

    function isCollateralized(Vault vault) public view override returns (bool) {
        return powerOf(vault) >= fyTokenToUnderlying(vault, vault.assets);
    }

    /// @dev Return if the collateral of a vault is between zero and the dust level
    function notDust(Vault vault)
        public view returns (bool)
    {
        return vault.assets == 0 || vault.collateral.dust < vault.assets;
    }

    function addUnderlying(IERC20 underlying)
        public
        onlyOwner
    {
        underlyings[underlying].registered = true;
        underlyings[underlying].erc20 = underlying;
    }

    function addCollateral(IERC20 collateral)
        public
        onlyOwner
    {
        collaterals[collateral].registered = true;
        collaterals[collateral].erc20 = collateral;
    }

    function setCollateral(IERC20 collateral, bytes32 what, bytes32 value)
        public
        onlyOwner validCollateral(collateral)
    {
        if (what == "dust") collaterals[collateral].dust = uint256(value);
        else revert("Controller: Unrecongnized parameter");
    }

    function addOracle(IERC20 underlying, IERC20 collateral, IOracle oracle)
        public
        onlyOwner validCollateral(collateral) validUnderlying(underlying)
    {
        oracles[underlying][collateral] = oracle;
    }

    function addSeries(IERC20 underlying, IFYToken fyToken)
        public
        onlyOwner validUnderlying(underlying) validMaturity(maturity)
    {
        series[underlying][fyToken.maturity].registered = true;
        series[underlying][fyToken.maturity].underlying = underlying;
        series[underlying][fyToken.maturity].fyToken = fyToken;
    }

    function addVault()
        public
    {
    }

    function fyTokenToUnderlying(Vault vault, uint256 amount)
        public view override
        validVault(vault)
        returns (uint256)
    {
        IFYToken fyToken = vault.series.fyToken;
        if (fyToken.isMature()) {
            return muld(
                amount,
                oracles[vault.series.underlying][vault.collateral].rateChange(fyToken.maturity())
                // TODO: A function for oracles to store the rate at the given maturities
                // TODO: The oracle for a wrapped token should return the inverse of savings rate
            );
        }
        else return amount;
    }

    function underlyingToFYToken(Vault vault, uint256 amount)
        public view override
        returns (uint256)
    {
        IFYToken fyToken = vault.series.fyToken;
        if (fyToken.isMature()) {
            return divdrup(
                amount,
                oracles[vault.series.underlying][vault.collateral].rateChange(fyToken.maturity())
                // TODO: A function for oracles to store the rate at the given maturities
                // TODO: The oracle for a wrapped token should return the inverse of savings rate
            );
        }
        else return amount;
    }

    function powerOf(Vault vault)
        public view override
        validVault(vault)
        returns (uint256)
    {
        return muld(vault.assets, oracles[vault.underlying.erc20][vault.collateral.erc20].rate());
    }

    function locked(Vault vault)
        public view override
        validVault(vault)
        returns (uint256)
    {
        return vault.assets - divdrup(
            fyTokenToUnderlying(vault),
            oracles[vault.underlying.erc20][vault.collateral.erc20].rate()
        );
    }

    function post(IERC20 collateral, address from, address to, Vault vault, uint256 amount)
        public override 
        validCollateral(collateral)
        ownsVault(to, vault)
        unlocked(vault)
        onlyLive
    {
        vault.assets += amount;
        require(notDust(vault), "Controller: Dust");
        treasury.push(collateral, from, amount);
    }

    function move(address from, address to, Vault vaultFrom, Vault vaultTo, uint256 amount)
        public override 
        ownsVault(from, vaultFrom) // Refactor as `hasRights`
        ownsVault(to, vaultTo)
        unlocked(vaultFrom)
        unlocked(vaultTo)
        onlyLive
    {
        require(vaultFrom.collateral == vaultTo.collateral, "Controller: Collaterals do not match");
        vaultFrom.assets -= amount;
        vaultTo.assets += amount;
        require(isCollateralized(vaultFrom), "Controller: Too much debt");
        require(notDust(vaultFrom), "Controller: Dust");
        require(notDust(vaultTo), "Controller: Dust");
    }

    function withdraw(IERC20 collateral, address from, address to, Vault vault, uint256 amount)
        public override 
        validCollateral(collateral)
        ownsVault(from, vault)
        unlocked(vault)
        onlyLive
    {
        vault.assets -= amount;

        require(
            isCollateralized(vault),
            "Controller: Too much debt"
        );
        require(
            notDust(vault),
            "Controller: Dust"
        );

        treasury.pull(collateral, to, amount);
    }

    /// @dev Borrow fyTokens
    function borrow(address from, address to, Vault vault, uint256 amount)
        public override 
        validCollateral(collateral)
        ownsVault(from, vault)
        unlocked(vault)
        onlyLive
    {
        vault.debt += amount;

        require(
            isCollateralized(vault),
            "Controller: Too much debt"
        );

        vault.series.fyToken.mint(to, amount);
        emit Borrowed(collateral, maturity, from, toInt256(fyDaiAmount));
    }

    /// @dev Repay with fyTokens
    function repay(address from, address to, Vault vault, uint256 amount)
        public override 
        validCollateral(collateral)
        ownsVault(to, vault)
        unlocked(vault)
        onlyLive
        returns (uint256)
    {
        uint256 toRepay = Math.min(amount, vault.debt);
        vault.series.fyToken.burn(from, toRepay);
        vault.debt -= toRepay;
        return toRepay;
    }
    
    /// @dev Repay with underlying Tokens
    function repayWithUnderlying(address from, address to, Vault vault, uint256 amount)
        public override 
        ownsVault(to, vault)
        unlocked(vault)
        onlyLive
        returns (uint256)
    {
        uint256 amountFYToken = underlyingToFYToken(vault, amount);
        uint256 toRepayFYToken = Math.min(amountFYToken, vault.debt);
        uint256 toRepay = fyTokenToUnderlying(vault, amount);
        treasury.push(vault.collateral, from, toRepay);
        vault.debt -= toRepayFYToken;
        return toRepayFYToken;
    }
}
