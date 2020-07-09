pragma solidity ^0.6.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../helpers/DecimalMath.sol";
import "../interfaces/IVat.sol";
import "../interfaces/IGemJoin.sol";
import "../interfaces/IDaiJoin.sol";
import "../interfaces/IChai.sol";
import "../interfaces/IYDai.sol";
import "../interfaces/IDealer.sol";
import "../interfaces/IMarket.sol";
import "../interfaces/IFlashMinter.sol";
// import "@nomiclabs/buidler/console.sol";


/// @dev The Market contract exchanges Dai for yDai at a price defined by a specific formula.
contract Splitter is IFlashMinter, DecimalMath {

    bytes32 public constant WETH = "ETH-A";
    bool constant public MTY = true;
    bool constant public YTM = false;

    IVat public vat;
    IERC20 public weth;
    IERC20 public dai;
    IGemJoin public wethJoin;
    IDaiJoin public daiJoin;
    IChai public chai;
    IYDai public yDai;
    IDealer public dealer;
    IMarket public market;

    constructor(
        address vat_,
        address weth_,
        address dai_,
        address wethJoin_,
        address daiJoin_,
        address chai_,
        address yDai_,
        address dealer_,
        address market_
    ) public {
        vat = IVat(vat_);
        weth = IERC20(weth_);
        dai = IERC20(dai_);
        wethJoin = IGemJoin(wethJoin_);
        daiJoin = IDaiJoin(daiJoin_);
        chai = IChai(chai_);
        yDai = IYDai(chai_);
        dealer = IDealer(yDai_);
        market = IMarket(market_);

        vat.hope(daiJoin_);
        vat.hope(wethJoin_);
    }

    /// @dev Safe casting from uint256 to int256
    function toInt(uint256 x) internal pure returns(int256) {
        require(
            x <= 57896044618658097711785492504343953926634992332820282019728792003956564819967,
            "Treasury: Cast overflow"
        );
        return int256(x);
    }

    function makerToYield(address user, uint256 yDaiAmount, uint256 wethAmount, uint256 daiAmount) public {
        // The user specifies the yDai he wants to mint to cover his maker debt, the weth to be passed on as collateral, and the dai debt to move
        // Flash mint the yDai
        yDai.flashMint(user, yDaiAmount, abi.encode(MTY, wethAmount, daiAmount));
    }

    function yieldToMaker(address user, uint256 yDaiAmount, uint256 wethAmount) public {
        // The user specifies the yDai he wants to move, and the weth to be passed on as collateral
        // Flash mint the yDai
        yDai.flashMint( user, yDaiAmount, abi.encode(YTM, wethAmount, 0)); // The daiAmount encoded is ignored
    }

    function executeOnFlashMint(address user, uint256 yDaiAmount, bytes calldata data) external override {
        (bool direction, uint256 wethAmount, uint256 daiAmount) = abi.decode(data, (bool, uint256, uint256));
        if(direction == MTY) _makerToYield(user, yDaiAmount, wethAmount, daiAmount); // TODO: Consider parameter order
        if(direction == YTM) _yieldToMaker(user, yDaiAmount, wethAmount, daiAmount); // TODO: Consider parameter order
    }

    function _makerToYield(address user, uint256 yDaiAmount, uint256 wethAmount, uint256 daiAmount) internal {
        // Sell the YDai for Chai
        // TODO: Calculate how much dai, then chai is needed, and use buyChai
        // Splitter will hold the chai temporarily - TODO: Consider SafeCast
        market.sellYDai(address(this), address(this), uint128(yDaiAmount));
        // Unpack the Chai into Dai
        chai.exit(address(this), chai.balanceOf(address(this)));
        // Put the Dai in Maker
        // TODO: daiJoin.hope(splitter.address, { from: user });
        daiJoin.join(user, daiAmount);
        // Pay the debt in Maker
        (, uint256 rate,,,) = vat.ilks("ETH-A");            // Retrieve the MakerDAO stability fee for Weth
        // TODO: vat.hope(splitter.address, { from: user });
        vat.frob(
            "ETH-A",
            user,
            user,
            user,
            -toInt(wethAmount),                           // Weth collateral to add
            -toInt(divd(daiAmount, rate))  // Dai debt to remove
        );
        // Remove the collateral from Maker
        vat.flux("ETH-A", user, address(this), wethAmount);
        wethJoin.exit(address(this), wethAmount); // Splitter will hold the weth temporarily
        // Add the collateral to Yield
        dealer.post(WETH, address(this), user, wethAmount);
        // Borrow the Dai
        // TODO: dealer.addProxy(splitter.address, { from: user });
        dealer.borrow(WETH, yDai.maturity(), user, user, yDaiAmount);
    }

    function _yieldToMaker(address user, uint256 yDaiAmount, uint256 wethAmount, uint256 daiAmount) internal {
        // Pay the Yield debt
        dealer.repayYDai(WETH, yDai.maturity(), user, user, yDaiAmount); // repayYDai wil only take what is needed
        // Withdraw the collateral from Yield
        uint256 wethAmount = dealer.posted(WETH, user);
        // TODO: dealer.addProxy(splitter.address, { from: user });
        dealer.withdraw(WETH, user, address(this), wethAmount);
        // Post the collateral to Maker
        // TODO: wethJoin.hope(splitter.address, { from: user });
        wethJoin.join(user, wethAmount);
        // Borrow the Dai from Maker
        (, uint256 rate,,,) = vat.ilks("ETH-A");            // Retrieve the MakerDAO stability fee for Weth
        // TODO: vat.hope(splitter.address, { from: user });
        vat.frob(
            "ETH-A",
            user,
            user,
            user,
            toInt(wethAmount),                           // Weth collateral to add
            toInt(divd(daiAmount, rate))  // Dai debt to remove
        );
        vat.move(user, address(this), daiAmount);
        daiJoin.exit(address(this), daiAmount); // Splitter will hold the dai temporarily
        // Wrap the Dai into Chai
        chai.join(address(this), dai.balanceOf(address(this)));
        // Sell the Chai for YDai at Market - It should make up for what was taken with repayYdai
        // Splitter will hold the chai temporarily - TODO: Consider SafeCast
        market.sellChai(address(this), address(this), uint128(chai.balanceOf(address(this))));
        yDai.transfer(user, yDai.balanceOf(address(this)));
    }
}