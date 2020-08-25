// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IVat.sol";
import "./interfaces/IDaiJoin.sol";
import "./interfaces/IGemJoin.sol";
import "./interfaces/IPot.sol";
import "./interfaces/IChai.sol";
import "./interfaces/ITreasury.sol";
import "./helpers/DecimalMath.sol";
import "./helpers/Orchestrated.sol";



/**
 * @dev Treasury manages asset transfers between all contracts in the Yield Protocol and other external contracts such as Chai and MakerDAO.
 * Treasury doesn't have any transactional functions available for regular users.
 * All transactional methods are to be available only for orchestrated contracts.
 * Treasury will ensure that all Weth is always stored as collateral in MAkerDAO.
 * Treasury will use all Dai to pay off system debt in MakerDAO first, and if there is no system debt the surplus Dai will be wrapped as Chai.
 * Treasury will use any Chai it holds when requested to provide Dai. If there isn't enough Chai, it will borrow Dai from MakerDAO.
 */
contract Treasury is ITreasury, Orchestrated(), DecimalMath {
    bytes32 constant WETH = "ETH-A";

    IVat public override vat;
    IWeth public override weth;
    IERC20 public override dai;
    IDaiJoin public override daiJoin;
    IGemJoin public override wethJoin;
    IPot public override pot;
    IChai public override chai;
    address public unwind;

    bool public override live = true;

    /// @dev As part of the constructor:
    /// Treasury allows the `chai` and `wethJoin` contracts to take as many tokens as wanted.
    /// Treasury approves the `daiJoin` and `wethJoin` contracts to move assets in MakerDAO.
    constructor (
        address vat_,
        address weth_,
        address dai_,
        address wethJoin_,
        address daiJoin_,
        address pot_,
        address chai_
    ) public {
        // These could be hardcoded for mainnet deployment.
        dai = IERC20(dai_);
        chai = IChai(chai_);
        pot = IPot(pot_);
        weth = IWeth(weth_);
        daiJoin = IDaiJoin(daiJoin_);
        wethJoin = IGemJoin(wethJoin_);
        vat = IVat(vat_);
        vat.hope(wethJoin_);
        vat.hope(daiJoin_);

        dai.approve(address(chai), uint256(-1));      // Chai will never cheat on us
        weth.approve(address(wethJoin), uint256(-1)); // WethJoin will never cheat on us
    }

    /// @dev Only while the Treasury is not unwinding due to a MakerDAO shutdown.
    modifier onlyLive() {
        require(live == true, "Treasury: Not available during unwind");
        _;
    }

    /// @dev Safe casting from uint256 to int256
    function toInt(uint256 x) internal pure returns(int256) {
        require(
            x <= uint256(type(int256).max),
            "Treasury: Cast overflow"
        );
        return int256(x);
    }

    /// @dev Disables pulling and pushing. Can only be called if MakerDAO shuts down.
    function shutdown() public override {
        require(
            vat.live() == 0,
            "Treasury: MakerDAO is live"
        );
        live = false;
    }

    /// @dev Returns the Treasury debt towards MakerDAO, in Dai.
    /// We have borrowed (rate * art)
    /// Borrowing limit (rate * art) <= (ink * spot)
    function debt() public view override returns(uint256) {
        (, uint256 rate,,,) = vat.ilks(WETH);            // Retrieve the MakerDAO stability fee for Weth
        (, uint256 art) = vat.urns(WETH, address(this)); // Retrieve the Treasury debt in MakerDAO
        return muld(art, rate);
    }

    /// @dev Returns the Treasury borrowing capacity from MakerDAO, in Dai.
    /// We can borrow (ink * spot)
    function power() public view returns(uint256) {
        (,, uint256 spot,,) = vat.ilks(WETH);            // Collateralization ratio for Weth
        (uint256 ink,) = vat.urns(WETH, address(this));  // Treasury Weth collateral in MakerDAO
        return muld(ink, spot);
    }

    /// @dev Returns the amount of chai in this contract, converted to Dai.
    function savings() public view override returns(uint256){
        return muld(chai.balanceOf(address(this)), pot.chi());
    }

    /// @dev Takes dai from user and pays as much system debt as possible, saving the rest as chai.
    /// User needs to have approved Treasury to take the Dai.
    /// This function can only be called by other Yield contracts, not users directly.
    /// @param from Wallet to take Dai from.
    /// @param daiAmount Dai quantity to take.
    function pushDai(address from, uint256 daiAmount)
        public override
        onlyOrchestrated("Treasury: Not Authorized")
        onlyLive
    {
        require(dai.transferFrom(from, address(this), daiAmount));  // Take dai from user to Treasury

        // Due to the DSR being mostly lower than the SF, it is better for us to
        // immediately pay back as much as possible from the current debt to
        // minimize our future stability fee liabilities. If we didn't do this,
        // the treasury would simultaneously owe DAI (and need to pay the SF) and
        // hold Chai, which is inefficient.
        uint256 toRepay = Math.min(debt(), daiAmount);
        if (toRepay > 0) {
            daiJoin.join(address(this), toRepay);
            // Remove debt from vault using frob
            (, uint256 rate,,,) = vat.ilks(WETH); // Retrieve the MakerDAO stability fee
            vat.frob(
                WETH,
                address(this),
                address(this),
                address(this),
                0,                           // Weth collateral to add
                -toInt(divd(toRepay, rate))  // Dai debt to remove
            );
        }

        uint256 toSave = daiAmount - toRepay;         // toRepay can't be greater than dai
        if (toSave > 0) {
            chai.join(address(this), toSave);    // Give dai to Chai, take chai back
        }
    }

    /// @dev Takes Chai from user and pays as much system debt as possible, saving the rest as chai.
    /// User needs to have approved Treasury to take the Chai.
    /// This function can only be called by other Yield contracts, not users directly.
    /// @param from Wallet to take Chai from.
    /// @param chaiAmount Chai quantity to take.
    function pushChai(address from, uint256 chaiAmount)
        public override
        onlyOrchestrated("Treasury: Not Authorized")
        onlyLive
    {
        require(chai.transferFrom(from, address(this), chaiAmount));
        uint256 daiAmount = chai.dai(address(this));

        uint256 toRepay = Math.min(debt(), daiAmount);
        if (toRepay > 0) {
            chai.draw(address(this), toRepay);     // Grab dai from Chai, converted from chai
            daiJoin.join(address(this), toRepay);
            // Remove debt from vault using frob
            (, uint256 rate,,,) = vat.ilks(WETH); // Retrieve the MakerDAO stability fee
            vat.frob(
                WETH,
                address(this),
                address(this),
                address(this),
                0,                           // Weth collateral to add
                -toInt(divd(toRepay, rate))  // Dai debt to remove
            );
        }
        // Anything that is left from repaying, is chai savings
    }

    /// @dev Takes Weth collateral from user into the Treasury Maker vault
    /// User needs to have approved Treasury to take the Weth.
    /// This function can only be called by other Yield contracts, not users directly.
    /// @param from Wallet to take Weth from.
    /// @param wethAmount Weth quantity to take.
    function pushWeth(address from, uint256 wethAmount)
        public override
        onlyOrchestrated("Treasury: Not Authorized")
        onlyLive
    {
        require(weth.transferFrom(from, address(this), wethAmount));

        wethJoin.join(address(this), wethAmount); // GemJoin reverts if anything goes wrong.
        // All added collateral should be locked into the vault using frob
        vat.frob(
            WETH,
            address(this),
            address(this),
            address(this),
            toInt(wethAmount), // Collateral to add - WAD
            0 // Normalized Dai to receive - WAD
        );
    }

    /// @dev Returns dai using chai savings as much as possible, and borrowing the rest.
    /// This function can only be called by other Yield contracts, not users directly.
    /// @param to Wallet to send Dai to.
    /// @param daiAmount Dai quantity to send.
    function pullDai(address to, uint256 daiAmount)
        public override
        onlyOrchestrated("Treasury: Not Authorized")
        onlyLive
    {
        uint256 toRelease = Math.min(savings(), daiAmount);
        if (toRelease > 0) {
            chai.draw(address(this), toRelease);     // Grab dai from Chai, converted from chai
        }

        uint256 toBorrow = daiAmount - toRelease;    // toRelease can't be greater than dai
        if (toBorrow > 0) {
            (, uint256 rate,,,) = vat.ilks(WETH); // Retrieve the MakerDAO stability fee
            // Increase the dai debt by the dai to receive divided by the stability fee
            // `frob` deals with "normalized debt", instead of DAI.
            // "normalized debt" is used to account for the fact that debt grows
            // by the stability fee. The stability fee is accumulated by the "rate"
            // variable, so if you store Dai balances in "normalized dai" you can
            // deal with the stability fee accumulation with just a multiplication.
            // This means that the `frob` call needs to be divided by the `rate`
            // while the `GemJoin.exit` call can be done with the raw `toBorrow`
            // number.
            vat.frob(
                WETH,
                address(this),
                address(this),
                address(this),
                0,
                toInt(divdrup(toBorrow, rate))      // We need to round up, otherwise we won't exit toBorrow
            );
            daiJoin.exit(address(this), toBorrow); // `daiJoin` reverts on failures
        }

        require(dai.transfer(to, daiAmount));                            // Give dai to user
    }

    /// @dev Returns chai using chai savings as much as possible, and borrowing the rest.
    /// This function can only be called by other Yield contracts, not users directly.
    /// @param to Wallet to send Chai to.
    /// @param chaiAmount Chai quantity to send.
    function pullChai(address to, uint256 chaiAmount)
        public override
        onlyOrchestrated("Treasury: Not Authorized")
        onlyLive
    {
        uint256 chi = pot.chi();
        uint256 daiAmount = muld(chaiAmount, chi);   // dai = price * chai
        uint256 toRelease = Math.min(savings(), daiAmount);
        // As much chai as the Treasury has, can be used, we borrwo dai and convert it to chai for the rest

        uint256 toBorrow = daiAmount - toRelease;    // toRelease can't be greater than daiAmount
        if (toBorrow > 0) {
            (, uint256 rate,,,) = vat.ilks(WETH); // Retrieve the MakerDAO stability fee
            // Increase the dai debt by the dai to receive divided by the stability fee
            vat.frob(
                WETH,
                address(this),
                address(this),
                address(this),
                0,
                toInt(divdrup(toBorrow, rate))       // We need to round up, otherwise we won't exit toBorrow
            ); // `vat.frob` reverts on failure
            daiJoin.exit(address(this), toBorrow);  // `daiJoin` reverts on failures
            chai.join(address(this), toBorrow);     // Grab chai from Chai, converted from dai
        }

        require(chai.transfer(to, chaiAmount));                            // Give dai to user
    }

    /// @dev Moves Weth collateral from Treasury controlled Maker Eth vault to `to` address.
    /// This function can only be called by other Yield contracts, not users directly.
    /// @param to Wallet to send Weth to.
    /// @param wethAmount Weth quantity to send.
    function pullWeth(address to, uint256 wethAmount)
        public override
        onlyOrchestrated("Treasury: Not Authorized")
        onlyLive
    {
        // Remove collateral from vault using frob
        vat.frob(
            WETH,
            address(this),
            address(this),
            address(this),
            -toInt(wethAmount), // Weth collateral to remove - WAD
            0              // Dai debt to add - WAD
        );
        wethJoin.exit(to, wethAmount); // `GemJoin` reverts on failures
    }

    /// @dev Registers the one contract that will take assets from the Treasury if MakerDAO shuts down.
    /// This function can only be called by the contract owner, which should only be possible during deployment.
    /// This function allows Unwind to take all the Chai savings and operate with the Treasury MakerDAO vault.
    /// @param unwind_ The address of the Unwild.sol contract.
    function registerUnwind(address unwind_)
        public
        onlyOwner
    {
        require(
            unwind == address(0),
            "Treasury: Unwind already set"
        );
        unwind = unwind_;
        chai.approve(address(unwind), uint256(-1)); // Unwind will never cheat on us
        vat.hope(address(unwind));                  // Unwind will never cheat on us
    }
}
