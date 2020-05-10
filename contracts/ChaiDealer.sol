pragma solidity ^0.6.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ISaver.sol";
import "./Constants.sol";
import "./Dealer.sol";


/// @dev A ChaiDealer takes chai as collateral and issues yDai. Chai is saved in the Saver.
contract ChaiDealer is Dealer {

    ISaver internal _saver;
    // IYDai internal _yDai;
    // IERC20 internal _token;
    // IOracle internal _tokenOracle; // The oracle should return the price adjusted by collateralization

    // mapping(address => uint256) internal posted; // In Erc20
    // mapping(address => uint256) internal debt;   // In Dai/yDai

    constructor (
        address saver_,
        address yDai_,
        address chai_,
        address chaiOracle_
    ) public Dealer(yDai_, chai_, chaiOracle_) {
        _saver = ISaver(saver_);
    }

    /// @dev Collateral not in use for debt
    //
    //                       debtOf(user)(wad)
    // posted[user](wad) - -----------------------
    //                       daiOracle.get()(ray)
    //
    /* function unlockedOf(address user) public returns (uint256) {
        uint256 locked = debtOf(user)
            .divd(_tokenOracle.price(), RAY);
        if (locked > posted[user]) return 0; // Unlikely
        return posted[user].sub(locked);
    } */

    /// @dev Return debt in underlying of an user
    //
    //                        rate_now
    // debt_now = debt_mat * ----------
    //                        rate_mat
    //
    /* function debtOf(address user) public view returns (uint256) {
        if (_yDai.isMature()){
            return debt[user].muld(_yDai.rate(), RAY);
        }
        else {
            return debt[user];
        }
    } */

    /// @dev Takes chai from `from` address and gives it to the Saver
    // from --- Chai ---> saver
    function post(address from, uint256 chai) public override {
        // TODO: Consider a require on super.post()
        super.post(from, chai);                // Grab chai and update posted
        _token.approve(address(_saver), chai); // Saver will take chai
        _saver.join(address(this), chai);      // Send chai to Saver
    }

    /// @dev Takes chai from Saver and gives it to `to` address
    // us --- Token ---> to
    function withdraw(address to, uint256 chai) public override {
        _saver.exit(address(this), chai);      // Take chai from Saver
        super.withdraw(to, chai);              // Check collateralization, send chai to user and update posted
        // TODO: Consider a require on super.withdraw()
    }

    /// @dev Mint yDai for address `to` by locking its market value in collateral, user debt is increased.
    //
    // posted[user](wad) >= (debt[user](wad)) * amount (wad)) * collateralization (ray)
    //
    // us --- yDai ---> user
    // debt++
    /* function borrow(address to, uint256 yDai) public {
        require(
            _yDai.isMature() != true,
            "Dealer: No mature borrow"
        );
        require(
            posted[to] >= (debtOf(to).add(yDai))
                .divd(_tokenOracle.price(), RAY),
            "Dealer: Post more collateral"
        );
        debt[to] = debt[to].add(yDai);
        _yDai.mint(to, yDai);
    } */

    /// @dev Burns yDai from `from` address, user debt is decreased.
    //                                                  debt_maturity
    // debt_discounted = debt_nominal - repay_amount * ---------------
    //                                                  debt_nominal
    //
    // user --- Dai ---> us
    // debt--
    /* function repay(address from, uint256 yDai) public {
        uint256 debtProportion = debt[from].mul(RAY.unit())
            .divd(debtOf(from).mul(RAY.unit()), RAY);
        _yDai.burn(from, yDai);
        debt[from] = debt[from].sub(yDai.muld(debtProportion, RAY)); // Will revert if not enough debt
    } */
}