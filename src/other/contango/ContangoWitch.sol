// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/src/token/TransferHelper.sol";
import "../../Witch.sol";
import "./interfaces/IContangoWitchListener.sol";
import "./interfaces/IContangoWitch.sol";

contract ContangoWitch is Witch, IContangoWitch {
    using Math for uint256;
    using TransferHelper for *;
    using Cast for uint256;

    struct InsuranceLine {
        uint32 duration; // Time that the insurance auction take to cover the maximum debt insured
        uint64 maxInsuredProportion; // Maximum proportion of debt that is covered by the insurance fund at the insurance auction end (1e18 = 100%)
        uint64 insurancePremium; // Proportion of the collateral that is sent to the insurance fund for healthy liquidations (1e18 = 100%)
    }

    IContangoWitchListener public immutable contango;

    mapping(bytes6 => mapping(bytes6 => InsuranceLine)) public insuranceLines;
    address public insuranceFund;

    constructor(
        IContangoWitchListener contango_,
        ICauldron cauldron_,
        ILadle ladle_,
        address insuranceFund_
    ) Witch(cauldron_, ladle_) {
        contango = contango_;
        insuranceFund = insuranceFund_;
    }

    function _auctionStarted(
        bytes12 vaultId,
        DataTypes.Auction memory auction_,
        DataTypes.Line memory line
    ) internal override returns (DataTypes.Vault memory vault) {
        vault = super._auctionStarted(vaultId, auction_, line);
        contango.auctionStarted(vaultId);
    }

    function _collateralBought(
        bytes12 vaultId,
        address buyer,
        uint256 ink,
        uint256 art
    ) internal override {
        super._collateralBought(vaultId, buyer, ink, art);
        contango.collateralBought(vaultId, buyer, ink, art);
    }

    function _auctionEnded(bytes12 vaultId, address owner) internal override {
        super._auctionEnded(vaultId, owner);
        contango.auctionEnded(vaultId, owner);
    }

    function setInsuranceLine(
        bytes6 ilkId,
        bytes6 baseId,
        uint32 duration,
        uint64 maxInsuredProportion,
        uint64 insurancePremium
    ) external override auth {
        insuranceLines[ilkId][baseId] = InsuranceLine(
            duration,
            maxInsuredProportion,
            insurancePremium
        );
        emit InsuranceLineSet(
            ilkId,
            baseId,
            duration,
            maxInsuredProportion,
            insurancePremium
        );
    }

    function setInsuranceFund(address insuranceFund_) external override auth {
        insuranceFund = insuranceFund_;
        emit InsuranceFundSet(insuranceFund);
    }

    function _discountDebt(
        bytes6 ilkId,
        bytes6 baseId,
        bytes6 seriesId,
        uint256 auctionStart,
        uint256 auctionDuration,
        uint256 artIn
    ) internal view virtual override returns (uint256 requiredArtIn) {
        InsuranceLine memory line = insuranceLines[ilkId][baseId];
        uint256 topUp = line.duration == 0
            ? 0
            : artIn.wmul(
                // TODO remove this and return only the discount
                ONE_HUNDRED_PERCENT -
                    _debtProportionNow(line, auctionStart, auctionDuration)
            );

        if (topUp > 0) {
            // two step verification to avoid possible overflow when summing up both balances
            uint256 insuranceFYTokenBalance = cauldron
                .series(seriesId)
                .fyToken
                .balanceOf(insuranceFund);
            if (insuranceFYTokenBalance < topUp) {
                uint256 insuranceBaseBalance = IERC20(
                    ladle.joins(baseId).asset()
                ).balanceOf(insuranceFund);
                if (insuranceBaseBalance < topUp - insuranceFYTokenBalance) {
                    // TODO assumes 1:1 fyToken:base
                    topUp = insuranceFYTokenBalance + insuranceBaseBalance;
                }
            }
        }

        requiredArtIn = artIn - topUp;
    }

    function _debtProportionNow(
        InsuranceLine memory line,
        uint256 auctionStart,
        uint256 auctionDuration
    ) internal view returns (uint256 debtProportionNow) {
        uint256 elapsed = block.timestamp - (auctionStart + auctionDuration);
        uint256 discount = elapsed < line.duration
            ? (line.maxInsuredProportion * elapsed) / line.duration
            : line.maxInsuredProportion;
        debtProportionNow = ONE_HUNDRED_PERCENT - discount;
    }

    function _topUpDebt(
        bytes12 vaultId,
        DataTypes.Auction memory auction,
        uint256 artIn,
        bool baseTopUp
    ) internal override returns (uint256 requiredArtIn) {
        InsuranceLine memory insuranceLine = insuranceLines[auction.ilkId][
            auction.baseId
        ];
        uint256 duration = lines[auction.ilkId][auction.baseId].duration;

        if (
            insuranceLine.duration == 0 ||
            auction.start + duration > block.timestamp
        ) {
            requiredArtIn = artIn;
        } else {
            requiredArtIn = artIn.wdivup(
                _debtProportionNow(insuranceLine, auction.start, duration)
            );

            uint256 topUpAmount = requiredArtIn - artIn;

            if (topUpAmount != 0) {
                uint256 debtToppedUp = baseTopUp
                    ? cauldron.debtToBase(auction.seriesId, topUpAmount.u128())
                    : topUpAmount;

                IFYToken fyToken = cauldron.series(auction.seriesId).fyToken;
                uint256 fyTokenBalance = fyToken.balanceOf(insuranceFund);

                uint256 payWithFYToken = fyTokenBalance > debtToppedUp
                    ? debtToppedUp
                    : fyTokenBalance;
                if (payWithFYToken != 0) {
                    // Take fyTokens from insurance fund
                    fyToken.safeTransferFrom(
                        insuranceFund,
                        address(fyToken),
                        payWithFYToken
                    );
                    fyToken.burn(address(this), payWithFYToken);
                }

                uint256 payWithBase = debtToppedUp - payWithFYToken;
                if (payWithBase != 0) {
                    IJoin baseJoin = ladle.joins(auction.baseId);
                    if (baseJoin == IJoin(address(0))) {
                        revert JoinNotFound(auction.baseId);
                    }

                    // Take underlying from insurance fund
                    IERC20(baseJoin.asset()).safeTransferFrom(
                        insuranceFund,
                        address(baseJoin),
                        payWithBase
                    );
                    baseJoin.join(address(this), payWithBase.u128());
                }

                emit LiquidationInsured(vaultId, topUpAmount, debtToppedUp);
            }
        }
    }

    function _calcInsurancePremium(
        DataTypes.Auction memory auction_,
        uint256 liquidatorCut
    ) internal view override returns (uint256 premium) {
        uint256 insurancePremium = insuranceLines[auction_.ilkId][
            auction_.baseId
        ].insurancePremium;

        if (_shouldItPayInsurancePremium(insurancePremium, auction_)) {
            premium = liquidatorCut.wmul(insurancePremium);
        }
    }

    function _payInk(
        DataTypes.Auction memory auction,
        address to,
        uint256 liquidatorCut,
        uint256 auctioneerCut,
        uint256 insurancePremium
    ) internal override returns (uint256, uint256) {
        if (insurancePremium > 0) {
            _join(auction.ilkId).exit(insuranceFund, insurancePremium.u128());
        }

        return
            super._payInk(
                auction,
                to,
                liquidatorCut,
                auctioneerCut,
                insurancePremium
            );
    }

    function _shouldItPayInsurancePremium(
        uint256 insurancePremium,
        DataTypes.Auction memory auction
    ) internal view returns (bool) {
        uint256 duration = lines[auction.ilkId][auction.baseId].duration;
        // Only charge premium for non-insured liquidations
        return
            insurancePremium > 0 && block.timestamp <= auction.start + duration;
    }
}
